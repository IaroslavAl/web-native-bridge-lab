#if !SWIFT_PACKAGE
import WebKit
import XCTest
@testable import TransportPackage
@testable import BridgeLab

/// Real WKScriptMessage/FrameInfo and URLSession sockets. Not installed React E2E.
/// Requires the opt-in fixture and a fresh dedicated Simulator from scripts/verify.
@MainActor
final class LiveWebKitTests: XCTestCase {
    private var host: LiveHost!
    private let web = "http://127.0.0.1:8787"
    private let api = "http://127.0.0.1:8788"

    override func setUp() async throws {
        // Ordinary runner regressions exclude this opt-in suite; Stage4 requires zero skips.
        let state = try await fixture()
        XCTAssertEqual(state["fixture"] as? String, "PER85-Stage4", "dedicated fixture identity")
        host = LiveHost()
    }

    override func tearDown() async throws {
        host?.close()
        host = nil
    }

    func testRealFrameMetadataRejectedAtAdapterAfterTestOnlyNavigationBypass() async throws {
        host.navigation.allowFrames = true // only outer test delegate, never production policy
        try await host.load(web + "/frames")
        let session = try await hello()
        for (index, origin) in [web, api].enumerated() {
            _ = try await host.js("""
                const frame=document.createElement('iframe'); frame.src=origin+'/frame?tag=frame-'+index;
                frame.onload=()=>frame.contentWindow.postMessage({kind:'probe',session},origin);
                document.body.append(frame); return true;
                """, ["origin": origin, "index": index, "session": session])
        }
        try await host.waitJS("frameResults.length === 2")
        let replies = try await host.js("return frameResults") as! [[String: Any]]
        for result in replies {
            for key in ["hello", "request"] {
                XCTAssertEqual((result[key] as? [String: Any])?["code"] as? String, "ORIGIN_DENIED", "frame \(key) denied")
            }
        }
        XCTAssertEqual(host.observer.frames.count, 2, "actual metadata observations")
        XCTAssertTrue(host.observer.frames.allSatisfy { !$0.isMainFrame && $0.host == "127.0.0.1" && $0.scheme == "http" })
        XCTAssertEqual(Set(host.observer.frames.map(\.port)), Set([8787,8788]), "actual frame origin ports")
        let repeated = try await hello()
        let forbidden = try await events(path: "/forbidden-frame")
        XCTAssertEqual(repeated, session, "iframe calls did not replace main session")
        XCTAssertTrue(forbidden.isEmpty, "no frame API admission")
    }

    func testActualDeniedNavigationFrameAndNewWindowKeepCurrentDocument() async throws {
        try await host.load(web + "/denials")
        let session = try await hello()
        // Production installs no WKUIDelegate. WebKit rejects creation itself;
        // unlike main/frame navigation this does NOT invoke the adapter delegate.
        host.view.uiDelegate = nil
        _ = try await host.js("""
            const f=document.createElement('iframe'); f.src=foreign+'/denied-frame'; document.body.append(f);
            window.popupWasNull=window.open(foreign+'/denied-window','_blank') === null;
            location.href=foreign+'/denied-main'; return true;
            """, ["foreign": api])
        try await eventually("real main/frame navigation denials") { self.host.navigation.denials.count == 2 }
        XCTAssertTrue(host.navigation.denials.contains("frame"))
        XCTAssertTrue(host.navigation.denials.contains("main"))
        let popupWasNull = try await host.js("return popupWasNull") as? Bool
        XCTAssertEqual(popupWasNull, true, "WebKit rejects new window without a UI delegate")
        XCTAssertEqual(host.view.url?.absoluteString, web + "/denials")
        let repeated = try await hello()
        XCTAssertEqual(repeated, session, "denied navigation retains session")
        for path in ["/denied-frame", "/denied-main", "/denied-window"] {
            let hits = try await events(path: path)
            XCTAssertTrue(hits.isEmpty, "denied destination \(path) untouched")
        }
    }

    func testRealMainFrameUncommittedAndInactiveMessagesDenied() async throws {
        host.navigation.forwardCommit = false
        try await host.load(web + "/uncommitted")
        let uncommitted = try await host.js("return await bridge({v:1,type:'hello'})") as! [String: Any]
        XCTAssertEqual(uncommitted["code"] as? String, "ORIGIN_DENIED", "real main frame before adapter commit")
        // Held real didCommit callback is released; no fabricated URL or frame metadata.
        host.navigation.releaseCommit()
        _ = try await hello()
        host.adapter!.provisionalNavigationFailed() // explicit framework-only failure seam
        let inactive = try await host.js("return await bridge({v:1,type:'hello'})") as! [String: Any]
        XCTAssertEqual(inactive["code"] as? String, "ORIGIN_DENIED", "loaded but inactive document")
    }

    func testLiveSameURLReloadCancelsSocketAndFreshIDOneRejectsStaleToken() async throws {
        try await lifetime(kind: "reload")
    }

    func testLiveNavigationCancelsSocketAndFreshIDOneIsIsolated() async throws {
        try await lifetime(kind: "navigation")
    }

    func testActualProvisionalNetworkFailureRevokesAndNextDocumentRecovers() async throws {
        try await host.load(web + "/before-failure")
        let old = try await hello()
        try await startDelay(session: old, tag: "provisional")
        host.view.load(URLRequest(url: URL(string: web + "/abort")!))
        try await eventually("real didFailProvisionalNavigation") { self.host.navigation.provisionalFailures > 0 }
        try await waitClosed("provisional")
        try await host.load(web + "/after-failure")
        let fresh = try await hello()
        XCTAssertNotEqual(fresh, old, "failed document session revoked")
        let response = try await request(session: fresh, id: 1, path: "/fresh", tag: "provisional")
        XCTAssertEqual(response["body"] as? String, "fresh:provisional")
    }

    func testActualMainFrameHTTP503CancelsFailsAndRecovers() async throws {
        try await host.load(web + "/before-http-error")
        let old = try await hello()
        let failureCount = host.navigation.provisionalFailures
        let loadEventCount = host.loadEvents.count

        host.startLoad(web + "/main-http-503")
        try await eventually("actual main-frame HTTP 503 response policy") {
            self.host.navigation.responsePolicies.contains { $0.status == 503 && $0.policy == .cancel }
        }
        try await eventually("correlated HTTP 503 provisional failure") {
            self.host.navigation.provisionalFailures > failureCount
        }

        let denied = await host.bridgeReply("{\"v\":1,\"type\":\"hello\"}")
        XCTAssertEqual(denied["code"] as? String, "ORIGIN_DENIED", "cancelled document never activates")
        try await host.load(web + "/after-http-error")
        let fresh = try await hello()

        XCTAssertNotEqual(fresh, old, "recovering navigation obtains a fresh session")
        XCTAssertEqual(Array(host.loadEvents.dropFirst(loadEventCount)), [
            .started,
            .failed(.contentUnavailable),
            .started,
            .finished,
        ], "real WebKit cancellation emits recoverable failure before replacement finish")
    }

    func testLiveCloseAndAdapterDestructionCancelSocketsAndReleaseOwnership() async throws {
        for kind in ["close", "destruction"] {
            if kind == "destruction" { host.close(); host = LiveHost() }
            try await host.load(web + "/" + kind)
            let session = try await hello()
            try await startDelay(session: session, tag: kind)
            weak var weakAdapter = host.adapter
            if kind == "close" { host.adapter?.close() }
            host.navigation.adapter = nil
            host.adapter = nil
            XCTAssertNil(weakAdapter, "adapter released on \(kind)")
            try await waitClosed(kind)
            try await host.waitJS("results.length === 1")
            let result = try await host.js("return results[0]") as! [String: Any]
            XCTAssertEqual(result["code"] as? String, "CANCELLED", "old document receives original cancellation")
            XCTAssertEqual(result["id"] as? Int, 1)
            let absent = try await host.js("return !window.webkit.messageHandlers.nativeHTTP") as! Bool
            XCTAssertTrue(absent, "handler removed")
        }
    }

    func testSyntheticWebNativeCookiesCacheAndChallengeIsolation() async throws {
        // Fixed known synthetic keys in a newly created Simulator, never enumerate accounts.
        let model = BridgeWebViewModel() // actual production WK data-store configuration
        defer { model.close() }
        let cookie = HTTPCookie(properties: [.domain:"127.0.0.1", .path:"/", .name:"per85_shared", .value:"synthetic"])!
        let webCookie = HTTPCookie(properties: [.domain:"127.0.0.1", .path:"/", .name:"per85_web", .value:"synthetic"])!
        let space = URLProtectionSpace(host: "127.0.0.1", port: 8788, protocol: "http", realm: "PER85Synthetic", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let credential = URLCredential(user: "per85-synthetic", password: "synthetic-only", persistence: .forSession)
        HTTPCookieStorage.shared.setCookie(cookie)
        URLCredentialStorage.shared.setDefaultCredential(credential, for: space)
        let cachedURL = URL(string: api + "/cache?tag=privacy-cache")!
        let cachedRequest = URLRequest(url: cachedURL)
        let cachedResponse = HTTPURLResponse(url: cachedURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json", "Cache-Control":"max-age=3600"])!
        URLCache.shared.storeCachedResponse(CachedURLResponse(response: cachedResponse, data: Data("synthetic-cache".utf8)), for: cachedRequest)
        defer {
            HTTPCookieStorage.shared.deleteCookie(cookie)
            URLCredentialStorage.shared.remove(credential, for: space)
            URLCache.shared.removeCachedResponse(for: cachedRequest)
        }
        XCTAssertNotNil(URLCache.shared.cachedResponse(for: cachedRequest), "synthetic cache seed exists")
        XCTAssertNotNil(URLCredentialStorage.shared.defaultCredential(for: space), "synthetic credential seed exists")
        let controlConfig = URLSessionConfiguration.default
        let control = URLSession(configuration: controlConfig)
        let (_, _) = try await control.data(from: URL(string: api + "/inspect?tag=control-native")!)
        control.invalidateAndCancel()
        let controlHits = try await events(path: "/inspect", tag: "control-native")
        XCTAssertEqual(controlHits.first?["cookie"] as? Bool, true, "ambient native cookie positive control")
        // The positive control accepts its response cookie; remove only that known synthetic key.
        for seeded in HTTPCookieStorage.shared.cookies(for: URL(string: api)!) ?? [] where seeded.name == "per85_response" {
            HTTPCookieStorage.shared.deleteCookie(seeded)
        }
        await model.webView.configuration.websiteDataStore.httpCookieStore.setCookie(webCookie)
        // Reload actual model, proving its web store sends the synthetic cookie.
        model.reload()
        try await eventually("production model web cookie positive control") {
            try await self.events(path: "/").contains { $0["cookie"] as? Bool == true }
        }
        XCTAssertFalse(model.webView.configuration.websiteDataStore.isPersistent, "production WK store is ephemeral")
        // The second actual production model gets a new store, not the first model's cookie.
        let freshModel = BridgeWebViewModel()
        defer { freshModel.close() }
        let freshCookies = await freshModel.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertFalse(freshCookies.contains { $0.name == "per85_web" }, "new WK store does not inherit synthetic cookie")
        try await host.load(web + "/privacy")
        await host.view.configuration.websiteDataStore.httpCookieStore.setCookie(webCookie)
        let session = try await hello()
        for (offset, tag) in ["privacy-first", "privacy-second", "privacy-cache"].enumerated() {
            let path = tag == "privacy-cache" ? "/cache" : "/inspect"
            let result = try await request(session: session, id: offset + 1, path: path, tag: tag)
            XCTAssertEqual(result["type"] as? String, "response", "\(tag) response")
            let body = try JSONSerialization.jsonObject(with: Data((result["body"] as! String).utf8)) as! [String: Any]
            XCTAssertEqual(body["cookie"] as? Bool, false, "\(tag) no ambient cookie")
            XCTAssertEqual(body["authorization"] as? Bool, false, "\(tag) no ambient authorization")
            XCTAssertEqual(body["source"] as? String, "network", "\(tag) bypasses synthetic shared cache")
            let headers = result["headers"] as! [String: String]
            XCTAssertNil(headers["set-cookie"], "Set-Cookie not exposed")
            XCTAssertNil(headers["x-private"], "X-Private not exposed")
        }
        for id in [4,5] {
            let result = try await request(session: session, id: id, path: "/challenge", tag: "privacy-auth-\(id)")
            XCTAssertEqual(result["code"] as? String, "NETWORK_ERROR", "challenge cancelled")
            let hits = try await events(path: "/challenge", tag: "privacy-auth-\(id)")
            XCTAssertEqual(hits.count, 1, "no challenge retry")
            XCTAssertEqual(hits.first?["authorization"] as? Bool, false, "no supplied shared credential")
        }
        // Inspect only owned localhost synthetic cookie names, never retain values.
        let nativeCookies = HTTPCookieStorage.shared.cookies(for: URL(string: api)!) ?? []
        let wkCookies = await host.view.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertFalse(nativeCookies.contains { $0.name == "per85_response" }, "native did not persist response cookie")
        XCTAssertFalse(wkCookies.contains { $0.name == "per85_response" }, "API cookie did not enter WK store")
        XCTAssertFalse(nativeCookies.contains { $0.name == "per85_web" }, "WK cookie did not enter native store")
        XCTAssertFalse(wkCookies.contains { $0.name == "per85_shared" }, "native cookie did not enter WK store")
    }

    func testActualRedirectStatusAndLocationMatrixNeverRequestsDestination() async throws {
        try await host.load(web + "/redirect-vectors")
        let session = try await hello()
        var id = 1
        for status in [301, 302, 303, 307, 308] {
            for location in ["valid", "missing", "malformed"] {
                let tag = "redirect-\(status)-\(location)"
                let result = try await request(session: session, id: id,
                    path: "/vectors/redirect/\(status)/\(location)", tag: tag)
                XCTAssertEqual(result["code"] as? String, "REDIRECT_DENIED", tag)
                let hits = try await events(path: "/vectors/redirect/\(status)/\(location)", tag: tag)
                XCTAssertEqual(hits.count, 1, "one source request: \(tag)")
                id += 1
            }
        }
        let destinations = try await events(path: "/forbidden-redirect-destination")
        XCTAssertTrue(destinations.isEmpty, "no redirect destination regardless of Location parsing")
    }

    func testActualDecodedGzipHeaderBoundsEmptyHTTPAndEscapedLargeReply() async throws {
        try await host.load(web + "/response-vectors")
        let session = try await hello()
        for (offset, vector) in ["empty", "headers-exact", "headers-over", "gzip-exact", "gzip-over", "escaped"].enumerated() {
            let result = try await request(session: session, id: offset + 1, path: "/vectors/" + vector, tag: vector)
            if vector == "headers-over" || vector == "gzip-over" {
                XCTAssertEqual(result["code"] as? String, "RESPONSE_TOO_LARGE", vector)
            } else {
                XCTAssertEqual(result["type"] as? String, "response", vector)
                if vector == "empty" {
                    XCTAssertEqual(result["status"] as? Int, 204, "actual empty HTTP status")
                    XCTAssertEqual(result["body"] as? String, "", "empty response without media type")
                } else if vector == "headers-exact" {
                    let headers = try XCTUnwrap(result["headers"] as? [String: String])
                    XCTAssertEqual(headers, ["x-lab-tag": String(repeating: "a", count: 8183)], "8192 exposed bytes; large private header excluded")
                } else if vector == "gzip-exact" {
                    XCTAssertEqual(result["body"] as? String, String(repeating: "x", count: 1_048_576), "decoded gzip cap inclusive")
                } else {
                    let body = try XCTUnwrap(result["body"] as? String)
                    XCTAssertEqual(body, String(repeating: "\"\\\n", count: 50_000), "structured WebKit reply preserves escaped text")
                    let serialized = try JSONSerialization.data(withJSONObject: result)
                    XCTAssertGreaterThan(serialized.count, 131_072, "outgoing reply not subject to incoming cap")
                }
            }
        }
    }

    func testActualTrickleDeadlineStopsSocketWithoutJavaScriptTimer() async throws {
        try await host.load(web + "/trickle-vector")
        let session = try await hello()
        let result = try await host.js("return await bridge({v:1,type:'request',session,id:1,method:'GET',url,headers:{},body:null,timeoutMs:500})",
            ["session":session, "url":api + "/vectors/trickle?tag=trickle"]) as! [String: Any]
        XCTAssertEqual(result["code"] as? String, "TIMEOUT", "native deadline despite continuing HTTP chunks")
        try await eventually("trickle underlying socket cancelled") {
            try await self.allEvents().contains { $0["tag"] as? String == "trickle" && $0["event"] as? String == "connection-close" }
        }
        let observed = try await allEvents().filter { $0["tag"] as? String == "trickle" }
        XCTAssertGreaterThan(observed.filter { $0["event"] as? String == "chunk" }.count, 1, "actual continuing chunks, not a silent server")
        XCTAssertFalse(observed.contains { $0["event"] as? String == "finished" }, "native stopped unfinished response")
    }

    private func lifetime(kind: String) async throws {
        try await host.load(web + "/lifetime-" + kind)
        let old = try await hello()
        try await startDelay(session: old, tag: kind)
        if kind == "reload" { try await host.reload() }
        else { try await host.load(web + "/fresh-document") }
        try await waitClosed(kind)
        let fresh = try await hello()
        XCTAssertNotEqual(old, fresh, "fresh session after \(kind)")
        let stale = try await request(session: old, id: 1, path: "/forbidden-stale", tag: kind)
        XCTAssertEqual(stale["code"] as? String, "ORIGIN_DENIED")
        let result = try await request(session: fresh, id: 1, path: "/fresh", tag: kind)
        XCTAssertEqual(result["id"] as? Int, 1)
        XCTAssertEqual(result["body"] as? String, "fresh:" + kind)
        // Observe beyond the server's old 1500ms deadline, not just immediately after reload.
        try await Task.sleep(for: .milliseconds(1700))
        let count = try await host.js("return results.length") as? Int
        let forbidden = try await events(path: "/forbidden-stale", tag: kind)
        XCTAssertEqual(count, 0, "no old callback into new document")
        XCTAssertTrue(forbidden.isEmpty)
        let oldEvents = try await allEvents()
        XCTAssertFalse(oldEvents.contains { $0["tag"] as? String == kind && $0["path"] as? String == "/delay" && $0["event"] as? String == "finished" }, "no late server success")
    }

    private func hello() async throws -> String {
        let result = try await host.js("return await bridge({v:1,type:'hello'})") as! [String: Any]
        return try XCTUnwrap(result["session"] as? String, "hello session (value intentionally not logged)")
    }

    private func request(session: String, id: Int, path: String, tag: String) async throws -> [String: Any] {
        try await host.js("return await bridge({v:1,type:'request',session,id,method:'GET',url,headers:{},body:null,timeoutMs:5000})",
                          ["session":session, "id":id, "url":api + path + "?tag=" + tag]) as! [String: Any]
    }

    private func startDelay(session: String, tag: String) async throws {
        _ = try await host.js("bridge({v:1,type:'request',session,id:1,method:'GET',url,headers:{},body:null,timeoutMs:5000}).then(r=>results.push(r)); return true",
                             ["session":session, "url":api + "/delay?tag=" + tag])
        try await eventually("actual delayed socket admitted \(tag)") { try await self.events(path: "/delay", tag: tag).count == 1 }
    }

    private func waitClosed(_ tag: String) async throws {
        try await eventually("actual old connection-close \(tag)") {
            try await self.allEvents().contains { $0["tag"] as? String == tag && $0["path"] as? String == "/delay" && $0["event"] as? String == "connection-close" }
        }
    }

    private func fixture() async throws -> [String: Any] {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (data, _) = try await session.data(from: URL(string: web + "/__state")!)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    private func allEvents() async throws -> [[String: Any]] { try await fixture()["events"] as! [[String: Any]] }
    private func events(path: String, tag: String? = nil) async throws -> [[String: Any]] {
        try await allEvents().filter { $0["path"] as? String == path && $0["event"] as? String == "request" && (tag == nil || $0["tag"] as? String == tag) }
    }
}

@MainActor
private func eventually(_ label: String, _ condition: () async throws -> Bool) async throws {
    let end = Date().addingTimeInterval(8)
    while Date() < end {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(30))
    }
    XCTFail("Timed out: \(label)")
    throw NSError(domain: "LiveWebKitTests", code: 1, userInfo: [NSLocalizedDescriptionKey:label])
}

@MainActor
private final class LiveHost {
    let view: WKWebView
    var adapter: WKBridgeAdapter?
    let navigation = LiveNavigation()
    let observer = FrameObserver()
    var loadEvents: [WKBridgeLoadEvent] = []
    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true // test popup attempts
        view = WKWebView(frame: CGRect(x:0,y:0,width:400,height:600), configuration: configuration)
        let executor = HTTPExecutor(policy: .init(allowedOrigin: URL(string:"http://127.0.0.1:8788")!))
        adapter = WKBridgeAdapter(engine: BridgeEngine(executor:executor), policy:.production)
        navigation.adapter = adapter
        view.navigationDelegate = navigation; view.uiDelegate = navigation
        adapter!.install(on:view) { [weak self] event in self?.loadEvents.append(event) }
        configuration.userContentController.add(observer, name:"observed")
    }
    func startLoad(_ url: String) {
        navigation.finished = false
        view.load(URLRequest(url:URL(string:url)!, cachePolicy:.reloadIgnoringLocalCacheData))
    }
    func load(_ url: String) async throws {
        startLoad(url)
        try await eventually("real didFinish \(url)") { self.navigation.finished }
    }
    func reload() async throws {
        navigation.finished = false; view.reload()
        try await eventually("real reload didFinish") { self.navigation.finished }
    }
    func js(_ body: String, _ arguments: [String:Any] = [:]) async throws -> Any {
        try await view.callAsyncJavaScript(body, arguments:arguments, in:nil, contentWorld:.page) as Any
    }
    func waitJS(_ expression: String) async throws {
        try await eventually("JavaScript \(expression)") { try await self.js("return " + expression) as? Bool == true }
    }
    func bridgeReply(_ body: String) async -> [String: Any] {
        await withCheckedContinuation { continuation in
            adapter?.receive(.trusted(body)) { value, _ in
                continuation.resume(returning: value as? [String: Any] ?? [:])
            }
        }
    }
    func close() {
        adapter?.close(); adapter=nil; navigation.adapter=nil
        view.configuration.userContentController.removeScriptMessageHandler(forName:"observed")
        view.navigationDelegate=nil; view.uiDelegate=nil; view.stopLoading()
    }
}

@MainActor
private final class FrameObserver: NSObject, WKScriptMessageHandler {
    var frames: [BridgeFrameOrigin] = []
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        frames.append(.init(scheme:origin.protocol, host:origin.host, port:origin.port, isMainFrame:message.frameInfo.isMainFrame))
    }
}

@MainActor
private final class LiveNavigation: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var adapter: WKBridgeAdapter?
    var allowFrames = false
    var forwardCommit = true
    var finished = false
    var denials: [String] = []
    var provisionalFailures = 0
    var responsePolicies: [(status: Int?, policy: WKNavigationResponsePolicy)] = []
    private var heldCommit: (() -> Void)?
    func releaseCommit() { heldCommit?(); heldCommit=nil }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if allowFrames && action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        adapter!.webView(webView, decidePolicyFor:action) { policy in
            if policy == .cancel {
                let kind = action.targetFrame == nil ? "window" : action.targetFrame!.isMainFrame ? "main" : "frame"
                self.denials.append(kind)
                print("STAGE4 navigation delegate denied: \(kind)")
            }
            decisionHandler(policy)
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        adapter?.webView(webView, didStartProvisionalNavigation:navigation)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        adapter?.webView(webView, decidePolicyFor:response) { policy in
            self.responsePolicies.append(((response.response as? HTTPURLResponse)?.statusCode, policy))
            decisionHandler(policy)
        }
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if forwardCommit { adapter?.webView(webView, didCommit:navigation) }
        else { heldCommit = { [weak self, weak webView] in if let webView { self?.adapter?.webView(webView, didCommit:navigation) } } }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        adapter?.webView(webView, didFinish:navigation); finished=true
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        provisionalFailures += 1
        adapter?.webView(webView, didFailProvisionalNavigation:navigation, withError:error)
    }
}
#endif
