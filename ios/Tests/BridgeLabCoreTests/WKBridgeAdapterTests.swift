#if !SWIFT_PACKAGE
import WebKit
import XCTest
@testable import TransportPackage
@testable import BridgeLab

@MainActor
final class WKBridgeAdapterTests: XCTestCase {
    private let trustedURL = URL(string: "http://127.0.0.1:8787/")!
    private let foreignURL = URL(string: "https://example.com/")!

    func testAllowedNavigationRevokesOldDocumentAndFreshDocumentReusesIDOne() async {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        let oldSession = await activate(adapter)
        let oldResponse = await reply(from: adapter, incoming: .trusted(requestJSON(session: oldSession, id: 1)))
        XCTAssertEqual(oldResponse["type"] as? String, "response")

        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        adapter.navigationDidCommit(url: trustedURL)
        let freshSession = await hello(adapter)
        let fresh = await reply(from: adapter, incoming: .trusted(requestJSON(session: freshSession, id: 1)))
        let cancelAllCount = await executor.cancelAllCount

        XCTAssertNotEqual(freshSession, oldSession)
        XCTAssertEqual(fresh["type"] as? String, "response")
        XCTAssertEqual(fresh["id"] as? Int, 1)
        XCTAssertEqual(cancelAllCount, 1)
    }

    func testRejectedNavigationPreservesCurrentDocument() async {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        let session = await activate(adapter)

        XCTAssertEqual(adapter.navigationPolicy(for: foreignURL, targetIsMainFrame: true), .cancel)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: false), .cancel)
        let repeatedSession = await hello(adapter)
        let response = await reply(from: adapter, incoming: .trusted(requestJSON(session: session, id: 1)))
        let cancelAllCount = await executor.cancelAllCount

        XCTAssertEqual(repeatedSession, session)
        XCTAssertEqual(response["type"] as? String, "response")
        XCTAssertEqual(cancelAllCount, 0)
    }

    func testProvisionalFailureRevokesDocumentAndShellRecoversSelectedClosedSurface() async throws {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        _ = await activate(adapter)

        adapter.provisionalNavigationFailed()
        let denied = await reply(from: adapter, incoming: .trusted(helloJSON))
        await executor.waitForCancelAllCount(1)
        let cancelAllCount = await executor.cancelAllCount

        XCTAssertEqual(denied["code"] as? String, "ORIGIN_DENIED")
        XCTAssertEqual(cancelAllCount, 1)

        assertClosedSurfaceDestinationsAndNativeIdentity()
        assertTypedLoadEventsDoNotFinishRevokedDocument()
        try await assertSupersededFailureDoesNotRevokeReplacementDocument()
        assertShellSelectionFailureRetryReturnAndInteraction()
        try await assertMainFrameHTTPResponseRequires2xxWhileSubframesRemainAllowed()
    }

    private func assertClosedSurfaceDestinationsAndNativeIdentity() {
        XCTAssertEqual(WebSurface.demo.url.absoluteString, "http://127.0.0.1:8787/")
        XCTAssertEqual(WebSurface.diagnostics.url.absoluteString, "http://127.0.0.1:8787/?mode=diagnostics")
        XCTAssertEqual(WebSurface.allCases, [.demo, .diagnostics])

        let available = NativeVersionIdentity(infoDictionary: [
            "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "34"
        ])
        let unavailable = NativeVersionIdentity(infoDictionary: nil)
        XCTAssertEqual(available.displayText, "Версия приложения 1.2 · сборка 34")
        XCTAssertEqual(unavailable.displayText, "Версия приложения недоступна · сборка недоступна")
    }

    private func assertTypedLoadEventsDoNotFinishRevokedDocument() {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var events: [WKBridgeLoadEvent] = []
        adapter.install(on: webView) { events.append($0) }
        let finishedNavigation = webView.load(URLRequest(url: trustedURL))!
        webView.stopLoading()

        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        adapter.webView(webView, didStartProvisionalNavigation: finishedNavigation)
        adapter.navigationDidCommit(url: trustedURL)
        adapter.webView(webView, didFinish: finishedNavigation)
        XCTAssertEqual(events, [.started, .finished])

        let failedNavigation = webView.load(URLRequest(url: trustedURL))!
        webView.stopLoading()
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        adapter.webView(webView, didStartProvisionalNavigation: failedNavigation)
        adapter.provisionalNavigationFailed()
        XCTAssertEqual(events, [.started, .finished, .started, .failed(.contentUnavailable)])

        adapter.webView(webView, didFinish: failedNavigation)
        XCTAssertEqual(events, [.started, .finished, .started, .failed(.contentUnavailable)],
                       "a revoked failed document cannot later publish finish")
    }

    private func assertSupersededFailureDoesNotRevokeReplacementDocument() async throws {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var events: [WKBridgeLoadEvent] = []
        adapter.install(on: webView) { events.append($0) }
        let superseded = try XCTUnwrap(webView.load(URLRequest(url: trustedURL)))
        let replacement = try XCTUnwrap(webView.load(URLRequest(url: trustedURL)))
        webView.stopLoading()
        let delegate = adapter as WKNavigationDelegate

        XCTAssertFalse(superseded === replacement)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        delegate.webView?(webView, didStartProvisionalNavigation: superseded)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        delegate.webView?(webView, didStartProvisionalNavigation: replacement)
        adapter.navigationDidCommit(url: trustedURL)

        let cancellation = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        adapter.webView(webView, didFailProvisionalNavigation: superseded, withError: cancellation)
        adapter.webView(webView, didFinish: replacement)
        let freshSession = await hello(adapter)

        XCTAssertEqual(events, [.started, .started, .finished],
                       "a superseded failure cannot fail or suppress the replacement document")
        XCTAssertFalse(freshSession.isEmpty, "the replacement document remains bridge-active")
        let cancelAllCount = await executor.cancelAllCount
        XCTAssertEqual(cancelAllCount, 0, "the superseded callback cannot revoke the replacement")
    }

    func testLateSupersededHTTPErrorResponseCannotRevokeReplacementNavigation() async throws {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var events: [WKBridgeLoadEvent] = []
        adapter.install(on: webView) { events.append($0) }
        let superseded = try XCTUnwrap(webView.load(URLRequest(url: trustedURL)))
        let replacement = try XCTUnwrap(webView.load(URLRequest(url: trustedURL)))
        webView.stopLoading()
        let delegate = adapter as WKNavigationDelegate

        XCTAssertFalse(superseded === replacement)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        delegate.webView?(webView, didStartProvisionalNavigation: superseded)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        delegate.webView?(webView, didStartProvisionalNavigation: replacement)
        adapter.navigationDidCommit(url: trustedURL)
        let replacementSession = await hello(adapter)
        let cancelAllBeforeLateResponse = await executor.cancelAllCount
        let response = try XCTUnwrap(HTTPURLResponse(
            url: trustedURL,
            statusCode: 503,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ))

        XCTAssertEqual(adapter.navigationResponsePolicy(for: response, isForMainFrame: true), .cancel)
        let cancellation = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        adapter.webView(webView, didFailProvisionalNavigation: superseded, withError: cancellation)
        adapter.webView(webView, didFinish: replacement)
        let repeatedHello = await reply(from: adapter, incoming: .trusted(helloJSON))
        let request = await reply(
            from: adapter,
            incoming: .trusted(requestJSON(session: replacementSession, id: 1))
        )
        let cancelAllAfterLateResponse = await executor.cancelAllCount

        XCTAssertEqual(events, [.started, .started, .finished],
                       "a tokenless late response cannot fail or suppress the replacement")
        XCTAssertEqual(repeatedHello["session"] as? String, replacementSession)
        XCTAssertEqual(request["type"] as? String, "response")
        XCTAssertEqual(cancelAllAfterLateResponse, cancelAllBeforeLateResponse,
                       "a tokenless late response cannot revoke the replacement")
    }

    func testNilNavigationCallbacksCannotMutateActiveNavigation() async throws {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var events: [WKBridgeLoadEvent] = []
        adapter.install(on: webView) { events.append($0) }
        let navigation = try XCTUnwrap(webView.load(URLRequest(url: trustedURL)))
        webView.stopLoading()

        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        adapter.webView(webView, didStartProvisionalNavigation: navigation)
        adapter.webView(webView, didCommit: nil)
        adapter.webView(webView, didFinish: nil)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        adapter.webView(webView, didFailProvisionalNavigation: nil, withError: error)
        adapter.webView(webView, didFail: nil, withError: error)
        let denied = await reply(from: adapter, incoming: .trusted(helloJSON))
        let cancelAllCount = await executor.cancelAllCount

        XCTAssertEqual(events, [.started])
        XCTAssertEqual(denied["code"] as? String, "ORIGIN_DENIED")
        XCTAssertEqual(cancelAllCount, 0)
    }

    private func assertShellSelectionFailureRetryReturnAndInteraction() {
        var requests: [URLRequest] = []
        let model = BridgeWebViewModel(requestLoader: { _, request in requests.append(request) })
        defer { model.close() }

        XCTAssertEqual(model.selectedSurface, .demo)
        XCTAssertEqual(requests.map(\.url), [WebSurface.demo.url])
        XCTAssertEqual(model.loadState, .loading)
        XCTAssertFalse(model.webView.isUserInteractionEnabled)

        model.handleLoadEvent(.finished)
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.webView.isUserInteractionEnabled)

        model.openDiagnostics()
        XCTAssertEqual(model.selectedSurface, .diagnostics)
        XCTAssertEqual(requests.last?.url, WebSurface.diagnostics.url)
        XCTAssertEqual(model.loadState, .loading)
        XCTAssertFalse(model.webView.isUserInteractionEnabled)

        model.handleLoadEvent(.failed(.contentUnavailable))
        guard case .failed(let message) = model.loadState else {
            return XCTFail("Expected failed load state")
        }
        XCTAssertEqual(message, "Не удалось загрузить веб-экран.")
        XCTAssertFalse(model.webView.isUserInteractionEnabled)

        model.reload()
        XCTAssertEqual(requests.last?.url, WebSurface.diagnostics.url)
        XCTAssertEqual(model.loadState, .loading)

        model.openDemo()
        XCTAssertEqual(model.selectedSurface, .demo)
        XCTAssertEqual(requests.last?.url, WebSurface.demo.url)
        XCTAssertTrue(requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
        XCTAssertTrue(requests.allSatisfy { $0.timeoutInterval == 10 })
    }

    func testCommittedNavigationFailureRevokesDocument() async {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        _ = await activate(adapter)

        adapter.navigationFailed()
        let denied = await reply(from: adapter, incoming: .trusted(helloJSON))
        let cancelAllCount = await executor.cancelAllCount

        XCTAssertEqual(denied["code"] as? String, "ORIGIN_DENIED")
        XCTAssertEqual(cancelAllCount, 1)
    }

    private func assertMainFrameHTTPResponseRequires2xxWhileSubframesRemainAllowed() async throws {
        for status in [404, 503] {
            let executor = AdapterExecutor()
            let adapter = makeAdapter(executor: executor)
            let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            var events: [WKBridgeLoadEvent] = []
            adapter.install(on: webView) { events.append($0) }
            _ = await activate(adapter)
            let navigation = try XCTUnwrap(webView.load(URLRequest(url: trustedURL)))
            webView.stopLoading()
            let response = try XCTUnwrap(HTTPURLResponse(
                url: trustedURL,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            ))

            XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
            adapter.webView(webView, didStartProvisionalNavigation: navigation)
            XCTAssertEqual(adapter.navigationResponsePolicy(for: response, isForMainFrame: true), .cancel)
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
            adapter.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
            let denied = await reply(from: adapter, incoming: .trusted(helloJSON))
            let cancelAllCount = await executor.cancelAllCount

            XCTAssertEqual(events, [.started, .failed(.contentUnavailable)], "HTTP \(status) fails the shell load")
            XCTAssertEqual(denied["code"] as? String, "ORIGIN_DENIED")
            XCTAssertEqual(cancelAllCount, 1)
        }

        for status in [200, 204, 299] {
            let adapter = makeAdapter(executor: AdapterExecutor())
            let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            var events: [WKBridgeLoadEvent] = []
            adapter.install(on: webView) { events.append($0) }
            let navigation = try XCTUnwrap(webView.load(URLRequest(url: trustedURL)))
            webView.stopLoading()
            let response = try XCTUnwrap(HTTPURLResponse(
                url: trustedURL,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            ))

            XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
            adapter.webView(webView, didStartProvisionalNavigation: navigation)
            XCTAssertEqual(adapter.navigationResponsePolicy(for: response, isForMainFrame: true), .allow)
            adapter.navigationDidCommit(url: trustedURL)
            adapter.webView(webView, didFinish: navigation)
            XCTAssertEqual(events, [.started, .finished], "HTTP \(status) remains a successful shell load")
        }

        let adapter = makeAdapter(executor: AdapterExecutor())
        _ = await activate(adapter)
        let subframeError = try XCTUnwrap(HTTPURLResponse(
            url: trustedURL,
            statusCode: 503,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ))
        XCTAssertEqual(adapter.navigationResponsePolicy(for: subframeError, isForMainFrame: false), .allow)
        XCTAssertEqual(adapter.navigationResponsePolicy(for: URLResponse(
            url: trustedURL,
            mimeType: "text/html",
            expectedContentLength: 0,
            textEncodingName: "utf-8"
        ), isForMainFrame: true), .allow)
        let activeSession = await hello(adapter)
        XCTAssertFalse(activeSession.isEmpty, "allowed response controls preserve the active document")
    }

    func testWebContentProcessTerminationRevokesDocument() async {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        _ = await activate(adapter)

        adapter.webContentProcessTerminated()
        let denied = await reply(from: adapter, incoming: .trusted(helloJSON))
        let cancelAllCount = await executor.cancelAllCount

        XCTAssertEqual(denied["code"] as? String, "ORIGIN_DENIED")
        XCTAssertEqual(cancelAllCount, 1)
    }

    func testCloseRevokesDocumentRemovesNavigationDelegateAndReleasesAdapter() async {
        let executor = AdapterExecutor()
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var adapter: WKBridgeAdapter? = makeAdapter(executor: executor)
        let weakAdapter = WeakAdapterBox(adapter)
        webView.navigationDelegate = adapter
        adapter?.install(on: webView) { _ in }
        _ = await activate(adapter!)

        adapter?.close()
        let denied = await reply(from: adapter!, incoming: .trusted(helloJSON))
        adapter = nil
        let cancelAllCount = await executor.cancelAllCount

        XCTAssertEqual(denied["code"] as? String, "ORIGIN_DENIED")
        XCTAssertNil(webView.navigationDelegate)
        XCTAssertNil(weakAdapter.value)
        XCTAssertEqual(cancelAllCount, 1)
    }

    func testAdapterDestructionRevokesDocumentAndDoesNotRetainAdapter() async {
        let executor = AdapterExecutor()
        var adapter: WKBridgeAdapter? = makeAdapter(executor: executor)
        let weakAdapter = WeakAdapterBox(adapter)
        _ = await activate(adapter!)

        adapter = nil
        await executor.waitForCancelAllCount(1)
        let cancelAllCount = await executor.cancelAllCount

        XCTAssertNil(weakAdapter.value)
        XCTAssertEqual(cancelAllCount, 1)
    }

    func testQueuedOldHelloCannotAcquireFreshDocumentSession() async {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        let oldSession = await activate(adapter)
        let oldReply = ReplyCapture()

        adapter.receive(.trusted(helloJSON), replyHandler: oldReply.record)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        adapter.navigationDidCommit(url: trustedURL)

        let retired = await oldReply.value()
        let freshSession = await hello(adapter)
        XCTAssertEqual(retired["code"] as? String, "ORIGIN_DENIED")
        XCTAssertNotEqual(freshSession, oldSession)
    }

    func testQueuedOldRequestDoesNotExecuteAgainstFreshGeneration() async {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        let oldSession = await activate(adapter)
        let oldReply = ReplyCapture()

        adapter.receive(.trusted(requestJSON(session: oldSession, id: 1)), replyHandler: oldReply.record)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        adapter.navigationDidCommit(url: trustedURL)

        let retired = await oldReply.value()
        let requestCount = await executor.requestCount
        XCTAssertEqual(retired["code"] as? String, "ORIGIN_DENIED")
        XCTAssertEqual(requestCount, 0)
    }

    func testReloadSettlesAdmittedOldRequestAsCancelledAndFreshIDOneSucceeds() async {
        let executor = AdapterExecutor(suspendRequests: true, cancelPendingRequests: true)
        let adapter = makeAdapter(executor: executor)
        let oldSession = await activate(adapter)
        let oldReply = ReplyCapture()

        adapter.receive(.trusted(requestJSON(session: oldSession, id: 1)), replyHandler: oldReply.record)
        await executor.waitForRequestCount(1)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        adapter.navigationDidCommit(url: trustedURL)
        await executor.waitForCancelAllCount(1)

        let retired = await oldReply.value()
        let freshSession = await hello(adapter)
        let freshReply = ReplyCapture()
        adapter.receive(.trusted(requestJSON(session: freshSession, id: 1)), replyHandler: freshReply.record)
        await executor.waitForRequestCount(2)
        await executor.resolve(id: 1, with: .response(.init(id: 1, status: 200, headers: [:], body: "fresh")))
        let fresh = await freshReply.value()

        XCTAssertEqual(retired["type"] as? String, "error")
        XCTAssertEqual(retired["id"] as? Int, 1)
        XCTAssertEqual(retired["code"] as? String, "CANCELLED")
        XCTAssertEqual(fresh["type"] as? String, "response")
        XCTAssertEqual(fresh["id"] as? Int, 1)
        XCTAssertEqual(fresh["body"] as? String, "fresh")
    }

    func testCompletedResponseKeepsFirstTerminalResultAcrossImmediateReload() async {
        let executor = AdapterExecutor(suspendRequests: true, cancelPendingRequests: true)
        let held = expectation(description: "selected response awaiting old-handle publication")
        let gate = AdapterGate()
        defer { gate.release() }
        let adapter = makeAdapter(executor: executor, beforePublication: { result in
            if case .response = result { held.fulfill(); await gate.wait() }
        })
        let oldSession = await activate(adapter)
        let oldReply = ReplyCapture()

        adapter.receive(.trusted(requestJSON(session: oldSession, id: 1)), replyHandler: oldReply.record)
        await executor.waitForRequestCount(1)
        await executor.resolve(
            id: 1,
            with: .response(.init(id: 1, status: 200, headers: [:], body: "completed-old"))
        )
        await fulfillment(of: [held], timeout: 3)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        adapter.navigationDidCommit(url: trustedURL)
        await executor.waitForCancelAllCount(1)
        XCTAssertEqual(oldReply.count, 0, "old publication held after terminal selection and revoke")
        gate.release()

        let completed = await oldReply.value()
        await executor.waitForCancelAllCount(1)
        XCTAssertEqual(completed["type"] as? String, "response")
        XCTAssertEqual(completed["id"] as? Int, 1)
        XCTAssertEqual(completed["body"] as? String, "completed-old")
    }

    func testCompletedTransportFailureKeepsFirstTerminalResultAcrossImmediateReload() async {
        let executor = AdapterExecutor(suspendRequests: true, cancelPendingRequests: true)
        let held = expectation(description: "selected failure awaiting old-handle publication")
        let gate = AdapterGate()
        defer { gate.release() }
        let adapter = makeAdapter(executor: executor, beforePublication: { result in
            if case .error(_, "NETWORK_ERROR", _) = result { held.fulfill(); await gate.wait() }
        })
        let oldSession = await activate(adapter)
        let oldReply = ReplyCapture()

        adapter.receive(.trusted(requestJSON(session: oldSession, id: 1)), replyHandler: oldReply.record)
        await executor.waitForRequestCount(1)
        await executor.resolve(
            id: 1,
            with: .failure(.init(id: 1, code: "NETWORK_ERROR", message: "Network request failed"))
        )
        await fulfillment(of: [held], timeout: 3)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        adapter.navigationDidCommit(url: trustedURL)
        await executor.waitForCancelAllCount(1)
        XCTAssertEqual(oldReply.count, 0, "old error publication held after terminal selection and revoke")
        gate.release()

        let completed = await oldReply.value()
        await executor.waitForCancelAllCount(1)
        XCTAssertEqual(completed["type"] as? String, "error")
        XCTAssertEqual(completed["id"] as? Int, 1)
        XCTAssertEqual(completed["code"] as? String, "NETWORK_ERROR")
    }

    func testLateSuccessAfterReloadIsRetiredAsCancelledWithoutAffectingFreshIDOne() async {
        let executor = AdapterExecutor(suspendRequests: true, cancelPendingRequests: true)
        let adapter = makeAdapter(executor: executor)
        let oldSession = await activate(adapter)
        let oldReply = ReplyCapture()

        adapter.receive(.trusted(requestJSON(session: oldSession, id: 1)), replyHandler: oldReply.record)
        await executor.waitForRequestCount(1)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true), .allow)
        adapter.navigationDidCommit(url: trustedURL)
        await executor.waitForCancelAllCount(1)
        await executor.resolve(id: 1, with: .response(.init(id: 1, status: 200, headers: [:], body: "late-old")))

        let retired = await oldReply.value()
        let freshSession = await hello(adapter)
        let freshReply = ReplyCapture()
        adapter.receive(.trusted(requestJSON(session: freshSession, id: 1)), replyHandler: freshReply.record)
        await executor.waitForRequestCount(2)
        await executor.resolve(id: 1, with: .response(.init(id: 1, status: 200, headers: [:], body: "fresh")))
        let fresh = await freshReply.value()

        XCTAssertEqual(retired["type"] as? String, "error")
        XCTAssertEqual(retired["id"] as? Int, 1)
        XCTAssertEqual(retired["code"] as? String, "CANCELLED")
        XCTAssertEqual(fresh["type"] as? String, "response")
        XCTAssertEqual(fresh["id"] as? Int, 1)
        XCTAssertEqual(fresh["body"] as? String, "fresh")
    }

    func testReplyOnceSettlesOnlyFirstResult() {
        var values: [String] = []
        let reply = ReplyOnce { value, _ in
            values.append(value as! String)
        }

        reply.call("first", nil)
        reply.call("second", nil)

        XCTAssertEqual(values, ["first"])
    }

    func testProxyQueuedHelloRequestAndCancelCannotCrossRapidActivationIntents() async {
        let executor = AdapterExecutor(suspendRequests: true)
        let adapter = makeAdapter(executor: executor)
        let oldSession = await activate(adapter)
        let proxy = WeakReplyMessageHandler(delegate: adapter)
        let frame = BridgeFrameOrigin(scheme: "http", host: "127.0.0.1", port: 8787, isMainFrame: true)
        let old = [ReplyCapture(), ReplyCapture(), ReplyCapture()]
        let inputs = [helloJSON, requestJSON(session: oldSession, id: 1), cancelJSON(session: oldSession, id: 1)]
        for (input, capture) in zip(inputs, old) {
            proxy.forward(body: input, frame: frame, replyHandler: capture.record)
        }
        _ = adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true)
        adapter.navigationDidCommit(url: trustedURL)
        let superseded = ReplyCapture()
        proxy.forward(body: helloJSON, frame: frame, replyHandler: superseded.record)
        _ = adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true)
        adapter.navigationDidCommit(url: trustedURL)
        for capture in old + [superseded] {
            let value = await capture.value()
            XCTAssertEqual(value["code"] as? String, "ORIGIN_DENIED", "queued generation code")
            XCTAssertTrue(value["id"] is NSNull, "queued generation id must be null")
        }
        let fresh = await hello(adapter)
        XCTAssertNotEqual(fresh, oldSession, "fresh session identity")
        let admitted = await executor.requestCount
        XCTAssertEqual(admitted, 0, "queued proxy invocations must not admit native work")
        let response = ReplyCapture()
        adapter.receive(.trusted(requestJSON(session: fresh, id: 1)), replyHandler: response.record)
        await executor.waitForRequestCount(1)
        await executor.resolve(id: 1, with: .response(.init(id: 1, status: 200, headers: [:], body: "fresh")))
        let value = await response.value()
        XCTAssertEqual(value["body"] as? String, "fresh", "fresh id 1 unaffected by old cancel")
    }

    func testEveryRevocationEventCancelsAdmittedTaskAndDeadlineExactlyOnce() async {
        for event in ["navigation", "provisional", "committed", "termination", "close", "destruction"] {
            let executor = AdapterExecutor(suspendRequests: true)
            var adapter: WKBridgeAdapter? = makeAdapter(executor: executor)
            let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            adapter!.install(on: webView) { _ in }
            webView.navigationDelegate = adapter
            let session = await activate(adapter!)
            let pending = ReplyCapture()
            adapter!.receive(.trusted(requestJSON(session: session, id: 1)), replyHandler: pending.record)
            await executor.waitForRequestCount(1)
            let queued = ReplyCapture()
            adapter!.receive(.trusted(helloJSON), replyHandler: queued.record)
            let weakAdapter = WeakAdapterBox(adapter)
            switch event {
            case "navigation": _ = adapter!.navigationPolicy(for: trustedURL, targetIsMainFrame: true)
            case "provisional": adapter!.provisionalNavigationFailed()
            case "committed": adapter!.navigationFailed()
            case "termination": adapter!.webContentProcessTerminated()
            case "close": adapter!.close(); adapter!.close(); adapter!.navigationDidCommit(url: trustedURL)
            default: adapter = nil
            }
            let value = await pending.value()
            let denied = await queued.value()
            await executor.waitForCancelAllCount(1)
            XCTAssertEqual(value["id"] as? Int, 1, "\(event): originating id")
            XCTAssertEqual(value["code"] as? String, "CANCELLED", "\(event): terminal code")
            XCTAssertEqual(denied["code"] as? String, "ORIGIN_DENIED", "\(event): queued ingress code")
            XCTAssertEqual(executor.network.tasks[0].cancelCount, 1, "\(event): task cancel count")
            XCTAssertEqual(executor.deadlines.tokens[0].cancelCount, 1, "\(event): deadline cancel count")
            let count = await executor.cancelAllCount
            XCTAssertEqual(count, 1, "\(event): idempotent cancelAll count")
            if event == "close" || event == "destruction" {
                adapter = nil
                XCTAssertNil(weakAdapter.value, "\(event): adapter released with admitted work")
                XCTAssertNil(webView.navigationDelegate, "\(event): navigation delegate removed")
                let replacement = makeAdapter(executor: AdapterExecutor())
                replacement.install(on: webView) { _ in } // Duplicate handler registration would raise.
                replacement.close()
            } else { adapter?.close() }
        }
    }

    func testReplyOnceReleasesCapturedHolderImmediately() {
        final class Holder {}
        var holder: Holder? = Holder()
        weak let weakHolder = holder
        let reply = ReplyOnce { [captured = holder!] _, _ in _ = captured }
        holder = nil
        XCTAssertNotNil(weakHolder, "holder retained until first reply")
        reply.call(nil, nil)
        XCTAssertNil(weakHolder, "holder released while ReplyOnce is still alive")
        reply.call(nil, nil)
    }

    func testEightConcurrentAdmissionsBusyDuplicateAndReverseCorrelation() async {
        let executor = AdapterExecutor(suspendRequests: true)
        let adapter = makeAdapter(executor: executor)
        let session = await activate(adapter)
        let captures = (1...8).map { _ in ReplyCapture() }
        for id in 1...8 {
            adapter.receive(.trusted(requestJSON(session: session, id: id)), replyHandler: captures[id - 1].record)
        }
        await executor.waitForRequestCount(8)
        let busy = await reply(from: adapter, incoming: .trusted(requestJSON(session: session, id: 9)))
        let duplicate = await reply(from: adapter, incoming: .trusted(requestJSON(session: session, id: 8)))
        XCTAssertEqual(busy["code"] as? String, "BUSY", "ninth immediate admission result")
        XCTAssertEqual(duplicate["code"] as? String, "INVALID_REQUEST", "duplicate result")
        XCTAssertEqual(executor.network.tasks.count, 8, "no capacity queue or ninth task")
        for id in (1...8).reversed() {
            executor.network.complete(index: id - 1, with: .response(.init(id: id, status: 200, headers: [:], body: "body-\(id)")))
            let value = await captures[id - 1].value()
            XCTAssertEqual(value["id"] as? Int, id, "reverse completion id")
            XCTAssertEqual(value["body"] as? String, "body-\(id)", "reverse completion body")
        }
    }

    func testExplicitCancelAndDeadlineFollowNativeFirstTerminalOrder() async {
        for first in ["cancel", "deadline", "response"] {
            let executor = AdapterExecutor(suspendRequests: true)
            let adapter = makeAdapter(executor: executor)
            let session = await activate(adapter)
            let capture = ReplyCapture()
            adapter.receive(.trusted(requestJSON(session: session, id: 1)), replyHandler: capture.record)
            await executor.waitForRequestCount(1)
            if first == "cancel" {
                let ack = await reply(from: adapter, incoming: .trusted(cancelJSON(session: session, id: 1)))
                XCTAssertEqual(ack["cancelled"] as? Bool, true, "cancel-before-response acknowledgement")
            } else if first == "deadline" { await executor.deadlines.fire(index: 0) }
            else {
                executor.network.complete(index: 0, with: .response(.init(id: 1, status: 200, headers: [:], body: "winner")))
            }
            let value = await capture.value() // Selected and published before offering losing events.
            let ack = await reply(from: adapter, incoming: .trusted(cancelJSON(session: session, id: 1)))
            XCTAssertEqual(ack["cancelled"] as? Bool, false, "cancel after \(first) terminal")
            await executor.deadlines.fire(index: 0)
            executor.network.complete(index: 0, with: .response(.init(id: 1, status: 200, headers: [:], body: "loser")))
            XCTAssertEqual(capture.count, 1, "\(first): originating callback count")
            if first == "response" { XCTAssertEqual(value["body"] as? String, "winner", "first response body") }
            else {
                XCTAssertEqual(value["code"] as? String, first == "cancel" ? "CANCELLED" : "TIMEOUT", "first terminal code")
                XCTAssertEqual(executor.network.tasks[0].cancelCount, 1, "\(first): stopped underlying work")
            }
        }
    }

    func testOldNetworkAndDeadlineAfterFreshIDOneCannotTouchFreshTask() async {
        let executor = AdapterExecutor(suspendRequests: true)
        let adapter = makeAdapter(executor: executor)
        let old = await activate(adapter)
        let oldReply = ReplyCapture()
        adapter.receive(.trusted(requestJSON(session: old, id: 1)), replyHandler: oldReply.record)
        await executor.waitForRequestCount(1)
        _ = adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true)
        adapter.navigationDidCommit(url: trustedURL)
        let cancelled = await oldReply.value()
        XCTAssertEqual(cancelled["code"] as? String, "CANCELLED", "old originating cancellation")
        let fresh = await hello(adapter)
        let freshReply = ReplyCapture()
        adapter.receive(.trusted(requestJSON(session: fresh, id: 1)), replyHandler: freshReply.record)
        await executor.waitForRequestCount(2)
        executor.network.complete(index: 0, with: .response(.init(id: 1, status: 200, headers: [:], body: "late-old")))
        await executor.deadlines.fire(index: 0)
        XCTAssertEqual(executor.network.tasks[1].cancelCount, 0, "fresh underlying task unaffected by old callbacks")
        executor.network.complete(index: 1, with: .response(.init(id: 1, status: 200, headers: [:], body: "fresh")))
        let value = await freshReply.value()
        XCTAssertEqual(value["body"] as? String, "fresh", "fresh id 1 body")
        XCTAssertEqual(oldReply.count, 1, "old callback not repeated after fresh request")
    }

    private func makeAdapter(
        executor: AdapterExecutor,
        beforePublication: @escaping @MainActor (BridgeReply) async -> Void = { _ in }
    ) -> WKBridgeAdapter {
        let sessions = SessionSequence([
            String(repeating: "1", count: 32),
            String(repeating: "2", count: 32),
            String(repeating: "3", count: 32)
        ])
        let engine = BridgeEngine(executor: executor, sessionGenerator: { sessions.next() })
        return WKBridgeAdapter(engine: engine, policy: .production, beforePublication: beforePublication)
    }

    func testAdmissionOverlapWaitsForReceiptBeforeCancelAllAndFreshHello() async {
        let registered = expectation(description: "real admission registered, receipt held before adapter acknowledgement")
        let gate = AdapterGate()
        defer { gate.release() }
        let executor = AdapterExecutor(suspendRequests: true, admissionGate: {
            registered.fulfill()
            await gate.wait()
        })
        let adapter = makeAdapter(executor: executor)
        let session = await activate(adapter)
        let old = ReplyCapture()
        adapter.receive(.trusted(requestJSON(session: session, id: 1)), replyHandler: old.record)
        await fulfillment(of: [registered], timeout: 3)
        _ = adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true)
        adapter.navigationDidCommit(url: trustedURL)
        let freshHello = ReplyCapture()
        adapter.receive(.trusted(helloJSON), replyHandler: freshHello.record)
        let cancellations = await executor.cancelAllCount
        XCTAssertEqual(cancellations, 0, "cancelAll cannot overtake acknowledged admission")
        XCTAssertEqual(freshHello.count, 0, "fresh hello cannot bypass the admission/drain barrier")
        gate.release()
        let result = await old.value()
        let fresh = await freshHello.value()
        XCTAssertEqual(result["code"] as? String, "CANCELLED", "overlapping request participates in ordered cancelAll")
        XCTAssertNotEqual(fresh["session"] as? String, session, "fresh session after drain")
        XCTAssertEqual(executor.network.tasks[0].cancelCount, 1, "no escaped task")
    }

    func testSelectedTimeoutAndPolicyFailureAreImmutableAcrossHeldPublication() async {
        for code in ["TIMEOUT", "REDIRECT_DENIED"] {
            let executor = AdapterExecutor(suspendRequests: true)
            let gate = AdapterGate()
            defer { gate.release() }
            let held = expectation(description: "\(code) selected before publication")
            let adapter = makeAdapter(executor: executor, beforePublication: { result in
                if case .error(_, code, _) = result { held.fulfill(); await gate.wait() }
            })
            let session = await activate(adapter)
            let capture = ReplyCapture()
            adapter.receive(.trusted(requestJSON(session: session, id: 1)), replyHandler: capture.record)
            await executor.waitForRequestCount(1)
            if code == "TIMEOUT" { await executor.deadlines.fire(index: 0) }
            else { executor.network.complete(index: 0, with: .response(.init(id: 1, status: 302, headers: [:], body: ""))) }
            await fulfillment(of: [held], timeout: 3)
            _ = adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: true)
            adapter.navigationDidCommit(url: trustedURL)
            await executor.waitForCancelAllCount(1)
            XCTAssertEqual(capture.count, 0, "\(code): publication held through revoke")
            gate.release()
            let value = await capture.value()
            XCTAssertEqual(value["code"] as? String, code, "\(code): immutable selected code")
            XCTAssertEqual(value["id"] as? Int, 1, "\(code): recoverable id preserved")
        }
    }

    func testRejectedNavigationPreservesPendingWorkAndHighWaterMark() async {
        let executor = AdapterExecutor(suspendRequests: true)
        let adapter = makeAdapter(executor: executor)
        let session = await activate(adapter)
        let pending = ReplyCapture()
        adapter.receive(.trusted(requestJSON(session: session, id: 1)), replyHandler: pending.record)
        await executor.waitForRequestCount(1)
        XCTAssertEqual(adapter.navigationPolicy(for: foreignURL, targetIsMainFrame: true), .cancel)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: false), .cancel)
        XCTAssertEqual(adapter.navigationPolicy(for: trustedURL, targetIsMainFrame: nil), .cancel)
        let repeated = await hello(adapter)
        let duplicate = await reply(from: adapter, incoming: .trusted(requestJSON(session: session, id: 1)))
        XCTAssertEqual(repeated, session, "rejected navigation session unchanged")
        XCTAssertEqual(duplicate["code"] as? String, "INVALID_REQUEST", "high-water mark unchanged")
        XCTAssertEqual(executor.network.tasks[0].cancelCount, 0, "pending task unchanged")
        executor.network.complete(index: 0, with: .response(.init(id: 1, status: 200, headers: [:], body: "preserved")))
        let value = await pending.value()
        XCTAssertEqual(value["body"] as? String, "preserved", "pending reply preserved")
    }

    private func activate(_ adapter: WKBridgeAdapter) async -> String {
        adapter.navigationDidCommit(url: trustedURL)
        return await hello(adapter)
    }

    private func hello(_ adapter: WKBridgeAdapter) async -> String {
        let object = await reply(from: adapter, incoming: .trusted(helloJSON))
        guard let session = object["session"] as? String else {
            XCTFail("hello reply session missing: \(object)")
            return ""
        }
        return session
    }

    private func reply(from adapter: WKBridgeAdapter, incoming: BridgeIncoming) async -> [String: Any] {
        let capture = ReplyCapture()
        adapter.receive(incoming, replyHandler: capture.record)
        return await capture.value()
    }
}

@MainActor
private final class ReplyCapture {
    private(set) var count = 0
    private var result: [String: Any]?

    private let received = XCTestExpectation(description: "originating reply received")

    func record(_ value: Any?, _ error: String?) {
        count += 1
        XCTAssertEqual(count, 1, "originating reply callback count")
        let object = value as? [String: Any] ?? ["callbackError": error ?? "missing reply"]
        result = object
        if count == 1 { received.fulfill() }

    }

    func value() async -> [String: Any] {
        if let result { return result }
        let status = await XCTWaiter.fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(status, .completed, "originating reply received within diagnostic bound")
        return result ?? [:]
    }
}

private actor AdapterExecutor: HTTPExecuting {
    private(set) var requests: [HTTPRequest] = []
    private(set) var cancelAllCount = 0
    private let suspendRequests: Bool
    private let admissionGate: @MainActor () async -> Void
    nonisolated let network = AdapterNetwork()
    nonisolated let deadlines = AdapterDeadlines()
    private lazy var real = HTTPExecutor(policy: .init(allowedOrigin: URL(string: "http://127.0.0.1:8788")!), networkClient: network, deadlineScheduler: deadlines)
    private var requestSignals: [(Int, XCTestExpectation)] = []
    private var cancelSignals: [(Int, XCTestExpectation)] = []

    init(suspendRequests: Bool = false, cancelPendingRequests: Bool = false, admissionGate: @escaping @MainActor () async -> Void = {}) {
        self.suspendRequests = suspendRequests
        self.admissionGate = admissionGate
    }

    var requestCount: Int { requests.count }

    func submit(_ request: HTTPRequest) async -> HTTPSubmission {
        let submission = await real.submit(request)
        requests.append(request)
        for (count, signal) in requestSignals where requests.count >= count { signal.fulfill() }
        requestSignals.removeAll { requests.count >= $0.0 }
        await admissionGate()
        guard suspendRequests else {
            network.completeLatest(with: .response(.init(id: request.id, status: 200, headers: [:], body: "ok")))
            return submission
        }
        return submission
    }

    func cancel(id: Int) async -> Bool { await real.cancel(id: id) }

    func cancelAll() async {
        await real.cancelAll()
        cancelAllCount += 1
        for (count, signal) in cancelSignals where cancelAllCount >= count { signal.fulfill() }
        cancelSignals.removeAll { cancelAllCount >= $0.0 }
    }

    func resolve(id: Int, with result: HTTPResult) {
        network.completeLatest(with: result)
    }

    func waitForRequestCount(_ expected: Int) async {
        guard requests.count < expected else { return }
        let signal = XCTestExpectation(description: "native admission count \(expected)")
        requestSignals.append((expected, signal))
        let result = await XCTWaiter.fulfillment(of: [signal], timeout: 3)
        XCTAssertEqual(result, .completed, "native admission count \(expected)")
    }

    func waitForCancelAllCount(_ expected: Int) async {
        guard cancelAllCount < expected else { return }
        let signal = XCTestExpectation(description: "ordered cancelAll count \(expected)")
        cancelSignals.append((expected, signal))
        let result = await XCTWaiter.fulfillment(of: [signal], timeout: 3)
        XCTAssertEqual(result, .completed, "ordered cancelAll count \(expected)")
    }
}

@MainActor
private final class AdapterGate {
    private var opened = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { opened = true; waiter?.resume(); waiter = nil }
}

private final class AdapterNetwork: HTTPNetworkClient, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [@Sendable (NetworkEvent) -> Void] = []
    private var createdTasks: [AdapterNetworkTask] = []
    var tasks: [AdapterNetworkTask] { lock.lock(); defer { lock.unlock() }; return createdTasks }
    func makeTask(request: URLRequest, eventHandler: @escaping @Sendable (NetworkEvent) -> Void) -> HTTPNetworkTask {
        let task = AdapterNetworkTask()
        lock.lock(); handlers.append(eventHandler); createdTasks.append(task); lock.unlock()
        return task
    }
    func completeLatest(with result: HTTPResult) {
        complete(index: tasks.count - 1, with: result)
    }
    func complete(index: Int, with result: HTTPResult) {
        lock.lock(); let handler = handlers[index]; lock.unlock()
        switch result {
        case .response(let response):
            handler(.response(status: response.status, headers: [("content-type", "text/plain")], expectedContentLength: -1))
            handler(.data(Data(response.body.utf8)))
            handler(.complete(nil))
        case .failure:
            handler(.complete(.other))
        }
    }
}

private final class AdapterNetworkTask: HTTPNetworkTask, @unchecked Sendable {
    private let lock = NSLock()
    private var cancellations = 0
    var cancelCount: Int { lock.lock(); defer { lock.unlock() }; return cancellations }
    func resume() {}
    func cancel() { lock.lock(); cancellations += 1; lock.unlock() }
}

private final class AdapterDeadlines: DeadlineScheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var registered: [AdapterDeadline] = []
    var tokens: [AdapterDeadline] { lock.lock(); defer { lock.unlock() }; return registered }
    func schedule(afterMilliseconds milliseconds: Int, action: @escaping @Sendable () async -> Void) -> DeadlineToken {
        let token = AdapterDeadline(action: action)
        lock.lock(); registered.append(token); lock.unlock()
        return token
    }
    func fire(index: Int) async { await tokens[index].action() }
}

private final class AdapterDeadline: DeadlineToken, @unchecked Sendable {
    let action: @Sendable () async -> Void
    private let lock = NSLock()
    private var cancellations = 0
    var cancelCount: Int { lock.lock(); defer { lock.unlock() }; return cancellations }
    init(action: @escaping @Sendable () async -> Void) { self.action = action }
    func cancel() { lock.lock(); cancellations += 1; lock.unlock() }
}

private final class SessionSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}

private final class WeakAdapterBox {
    weak var value: WKBridgeAdapter?

    init(_ value: WKBridgeAdapter?) {
        self.value = value
    }
}

private let helloJSON = #"{"v":1,"type":"hello"}"#

private func cancelJSON(session: String, id: Int) -> String {
    #"{"v":1,"type":"cancel","session":"\#(session)","id":\#(id)}"#
}

private func requestJSON(session: String, id: Int) -> String {
    #"{"v":1,"type":"request","session":"\#(session)","id":\#(id),"method":"GET","url":"http://127.0.0.1:8788/test","headers":{},"body":null,"timeoutMs":5000}"#
}
#endif
