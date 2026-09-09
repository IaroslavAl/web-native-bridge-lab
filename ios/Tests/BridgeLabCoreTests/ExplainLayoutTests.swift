#if !SWIFT_PACKAGE
import WebKit
import XCTest
@testable import TransportPackage
@testable import BridgeLab

/// Real built Explain assets in an explicit WKWebView content frame.
/// DOM reads and clicks are test-local observations; the production bridge remains installed.
@MainActor
final class ExplainLayoutTests: XCTestCase {
    private let sizes = [
        CGSize(width: 320, height: 740),
        CGSize(width: 390, height: 844),
        CGSize(width: 430, height: 932),
        CGSize(width: 768, height: 1024),
        CGSize(width: 1100, height: 900),
    ]
    private var host: ExplainLayoutHost!

    override func setUp() async throws {
        host = ExplainLayoutHost()
        try await host.load()
        try await host.wait("production Explain action") {
            try await self.host.boolean("document.querySelector('.outcome button')?.disabled === false")
        }
    }

    override func tearDown() async throws {
        host?.close()
        host = nil
    }

    func testVariantARequiredViewportsAndRealStates() async throws {
        let initialIdentity = try await host.text("[data-testid='lab.variant']")
        let initialQuote = try await host.exists("button", containing: "Рассчитать заказ")
        XCTAssertTrue(initialIdentity.hasPrefix("Веб A ·"))
        XCTAssertFalse(initialQuote, "A must not expose quote")
        try await observeEverySize(state: "a-introduction")

        try await observePendingEverySize(action: "Получить каталог", result: "[data-testid='demo.catalog-result']",
                                          state: "a-catalog-pending")
        try await observeEverySize(state: "a-catalog-result")

        try await host.click("Загрузить обновлённый экран")
        try await host.wait("actual unchanged A reload") {
            try await self.host.bodyContains("Загружен прежний веб-экран")
        }
        let unchangedQuote = try await host.exists("button", containing: "Рассчитать заказ")
        XCTAssertFalse(unchangedQuote, "unchanged A must not unlock quote")
        try await observeEverySize(state: "a-unchanged")

        try await host.signalHost("layout-b-ready")
        try await host.waitForHost("layout-b-release")
        try await host.click("Проверить обновление ещё раз")
        try await host.wait("actual B with valid A history") {
            let identity = try await self.host.bodyContains("Веб B ·")
            let history = try await self.host.bodyContains("Раньше вы получили каталог")
            return identity && history
        }
        try await host.click("Рассчитать заказ")
        try await host.wait("real final comparison result") {
            let result = try await self.host.exists("[data-testid='demo.quote-total']")
            let comparison = try await self.host.exists(".comparison")
            return result && comparison
        }
        try await observeEverySize(state: "b-final-comparison")
    }

    func testReducedMotionAndEnlargedTextRemainUsable() async throws {
        let reducedMotion = try await host.boolean("matchMedia('(prefers-reduced-motion: reduce)').matches")
        XCTAssertTrue(reducedMotion, "owned Simulator must enable reduced motion before this test")
        try await host.installPendingRecorder()
        try await host.click("Получить каталог")
        try await host.wait("real catalog result under reduced motion") {
            try await self.host.exists("[data-testid='demo.catalog-result']")
        }
        let pending = try await host.pendingObservation()
        try assertPendingObservation(pending)
        XCTAssertEqual(pending["animation"] as? String, "none", "reduced motion disables route animation")
        host.view.frame = CGRect(origin: .zero, size: sizes[0])
        try await host.setRootTextScale(1.6)
        try await host.wait("enlarged layout") {
            let width = try await self.host.number("innerWidth")
            let height = try await self.host.number("innerHeight")
            let scrollHeight = try await self.host.number("document.body.scrollHeight")
            return abs(width - 320) <= 1 && scrollHeight > height
        }
        let observation = try await host.observation()
        try assertNoHorizontalOverflow(observation, state: "a-enlarged")
        let routeNote = try await host.text(".journey[data-direction] .route-note")
        XCTAssertEqual(routeNote, "Схема обмена; точный этап сервера не виден.")
        try await host.scrollToAction()
        let enlargedActionVisible = try await host.boolean("document.querySelector('.outcome button').getBoundingClientRect().bottom <= innerHeight")
        XCTAssertTrue(enlargedActionVisible, "enlarged action can be reached by vertical scrolling")
        try await retain(state: "a-reduced-motion-enlarged")
    }

    func testVariantBRequiredViewportsColdResultAndRepeat() async throws {
        let initialIdentity = try await host.text("[data-testid='lab.variant']")
        let initialHistory = try await host.bodyContains("Раньше вы получили каталог")
        XCTAssertTrue(initialIdentity.hasPrefix("Веб B ·"))
        XCTAssertFalse(initialHistory, "cold B must not invent A history")
        try await observeEverySize(state: "b-cold")

        try await host.click("Рассчитать заказ")
        try await host.wait("real quote result") { try await self.host.exists("[data-testid='demo.quote-total']") }
        let total = try await host.attribute("[data-testid='demo.quote-total']", "data-total-minor")
        let currency = try await host.attribute("[data-testid='demo.quote-total']", "data-currency")
        let resultHistory = try await host.bodyContains("Раньше вы получили каталог")
        XCTAssertEqual(total, "1200")
        XCTAssertEqual(currency, "USD")
        XCTAssertFalse(resultHistory, "cold B result must not invent A history")
        try await observeEverySize(state: "b-quote-result")

        try await host.click("Рассчитать снова")
        try await host.wait("real repeated quote result") {
            try await self.host.exists("button", containing: "Рассчитать снова")
        }
        let repeatedIdentity = try await host.text("[data-testid='lab.variant']")
        XCTAssertTrue(repeatedIdentity.hasPrefix("Веб B ·"), "repeat stays on actual B")
    }

    func testVariantBRetryRequiredViewports() async throws {
        let initialIdentity = try await host.text("[data-testid='lab.variant']")
        XCTAssertTrue(initialIdentity.hasPrefix("Веб B ·"))
        try await host.click("Рассчитать заказ")
        try await host.wait("real unavailable-API retry") {
            let error = try await self.host.exists(".error-card")
            let retry = try await self.host.exists("button", containing: "Повторить расчёт")
            return error && retry
        }
        let unavailableCopy = try await host.bodyContains("Не удалось связаться с сервером")
        XCTAssertTrue(unavailableCopy)
        try await observeEverySize(state: "b-api-retry")
    }

    private func observePendingEverySize(action: String, result: String, state: String) async throws {
        for size in sizes {
            host.close()
            host = ExplainLayoutHost(holdCompletions: true)
            try await host.load()
            try await host.wait("production Explain action") {
                try await self.host.boolean("document.querySelector('.outcome button')?.disabled === false")
            }
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()
            try await host.wait("pending WK viewport \(Int(size.width))x\(Int(size.height))") {
                let width = try await self.host.number("innerWidth")
                let height = try await self.host.number("innerHeight")
                return abs(width - Double(size.width)) <= 1 && abs(height - Double(size.height)) <= 1
            }
            try await host.scrollTop()
            host.holdNextCompletion()
            try await host.click(action)
            try await host.wait("real response held while pending") {
                let pending = try await self.host.exists("button", containing: "Ждём ответ…")
                let disabled = try await self.host.boolean("document.querySelector('.outcome button')?.disabled === true")
                return self.host.hasHeldCompletion && pending && disabled
            }
            let observation = try await host.observation()
            try assertDefaultLayout(observation, expected: size, state: state)
            try await retain(state: "\(state)-\(Int(size.width))x\(Int(size.height))", observation: observation)
            host.releaseCompletion()
            try await host.wait("real response result after pending observation") {
                try await self.host.exists(result)
            }
        }
    }

    private func observeEverySize(state: String) async throws {
        for size in sizes {
            host.view.pageZoom = 1
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()
            try await host.wait("WK viewport \(Int(size.width))x\(Int(size.height))") {
                let width = try await self.host.number("innerWidth")
                let height = try await self.host.number("innerHeight")
                return abs(width - Double(size.width)) <= 1 && abs(height - Double(size.height)) <= 1
            }
            try await host.scrollTop()
            let observation = try await host.observation()
            try assertDefaultLayout(observation, expected: size, state: state)
            try await retain(state: "\(state)-\(Int(size.width))x\(Int(size.height))", observation: observation)
        }
    }

    private func assertDefaultLayout(_ value: [String: Any], expected: CGSize, state: String) throws {
        XCTAssertEqual(try number(value, "width"), Double(expected.width), accuracy: 1, state)
        XCTAssertEqual(try number(value, "height"), Double(expected.height), accuracy: 1, state)
        try assertNoHorizontalOverflow(value, state: state)
        XCTAssertEqual(try number(value, "scrollY"), 0, accuracy: 0.5, "\(state) must start at scroll top")
        let route = try frame(value, "route")
        let current = try frame(value, "current")
        let action = try frame(value, "action")
        XCTAssertGreaterThanOrEqual(route.minY, 0, state)
        XCTAssertGreaterThanOrEqual(current.minY, route.maxY, state)
        XCTAssertGreaterThanOrEqual(action.minY, current.maxY, state)
        XCTAssertLessThanOrEqual(action.maxY, expected.height + 1, "\(state) action visible from scroll top")
        XCTAssertGreaterThanOrEqual(action.height, 44, "\(state) touch target")
    }

    private func assertNoHorizontalOverflow(_ value: [String: Any], state: String) throws {
        XCTAssertLessThanOrEqual(try number(value, "scrollWidth"), try number(value, "clientWidth") + 1,
                                 "\(state) horizontal overflow")
        for name in ["route", "current", "action"] {
            let bounds = try frame(value, name)
            XCTAssertGreaterThanOrEqual(bounds.minX, -1, "\(state) \(name) left clipping")
            XCTAssertLessThanOrEqual(bounds.maxX, try number(value, "width") + 1, "\(state) \(name) right clipping")
        }
    }

    private func assertPendingObservation(_ value: [String: Any]) throws {
        XCTAssertEqual(value["label"] as? String, "Ждём ответ…")
        XCTAssertEqual(value["direction"] as? String, "forward")
        XCTAssertGreaterThanOrEqual(try frame(value, "action").height, 44)

    }

    private func retain(state: String, observation: [String: Any]? = nil) async throws {
        let snapshot = try await host.view.takeSnapshot(configuration: nil)
        let image = XCTAttachment(image: snapshot)
        image.name = "Explain WK \(state)"
        image.lifetime = .keepAlways
        add(image)
        if let observation {
            let tree = XCTAttachment(string: "\(observation)")
            tree.name = "Explain geometry \(state)"
            tree.lifetime = .keepAlways
            add(tree)
        }
    }

    private func frame(_ value: [String: Any], _ key: String) throws -> CGRect {
        let raw = try XCTUnwrap(value[key] as? [String: Any], "missing \(key) frame")
        return CGRect(x: CGFloat(try number(raw, "x")), y: CGFloat(try number(raw, "y")),
                      width: CGFloat(try number(raw, "width")), height: CGFloat(try number(raw, "height")))
    }

    private func number(_ value: [String: Any], _ key: String) throws -> Double {
        try XCTUnwrap(value[key] as? NSNumber, "missing numeric \(key)").doubleValue
    }
}

@MainActor
private final class ExplainLayoutHost: NSObject, WKNavigationDelegate {
    let view: WKWebView
    private var adapter: WKBridgeAdapter?
    private let completionHolder: CompletionHoldingNetworkClient?
    private var finished = false

    init(holdCompletions: Bool = false) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let holder = holdCompletions ? CompletionHoldingNetworkClient() : nil
        completionHolder = holder
        let policy = TransportPolicy(allowedOrigin: URL(string: "http://127.0.0.1:8788")!)
        let executor = holder.map { HTTPExecutor(policy: policy, networkClient: $0) }
            ?? HTTPExecutor(policy: policy)
        adapter = WKBridgeAdapter(engine: BridgeEngine(executor: executor), policy: .production)
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        super.init()
        view.navigationDelegate = self
        adapter?.install(on: view) { _ in }
    }

    func load() async throws {
        finished = false
        view.load(URLRequest(url: URL(string: "http://127.0.0.1:8787/")!, cachePolicy: .reloadIgnoringLocalCacheData))
        try await wait("actual built page didFinish") { self.finished }
    }

    func close() {
        adapter?.close()
        adapter = nil
        view.navigationDelegate = nil
        view.stopLoading()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        adapter?.webView(webView, decidePolicyFor: action, decisionHandler: decisionHandler)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        adapter?.webView(webView, didCommit: navigation)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        adapter?.webView(webView, didFinish: navigation)
        finished = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        adapter?.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        adapter?.webView(webView, didFail: navigation, withError: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        adapter?.webViewWebContentProcessDidTerminate(webView)
    }

    func wait(_ label: String, condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Timed out: \(label)")
        throw NSError(domain: "ExplainLayoutTests", code: 1, userInfo: [NSLocalizedDescriptionKey: label])
    }

    func observation() async throws -> [String: Any] {
        try await script("""
            const rect = selector => {
              const value = document.querySelector(selector).getBoundingClientRect();
              return {x:value.x,y:value.y,width:value.width,height:value.height};
            };
            return {
              width:innerWidth,height:innerHeight,scrollY,
              scrollWidth:document.documentElement.scrollWidth,
              clientWidth:document.documentElement.clientWidth,
              route:rect('.journey'),current:rect('.current'),action:rect('.outcome button')
            };
            """) as! [String: Any]
    }

    func installPendingRecorder() async throws {
        _ = try await script("""
            window.__per85Pending = null;
            const capture = () => {
              const button = document.querySelector('.outcome button');
              if (button?.textContent.trim() !== 'Ждём ответ…') return;
              const frame = button.getBoundingClientRect();
              const arrow = document.querySelector('.route-arrow');
              window.__per85Pending = {
                label:button.textContent.trim(),
                direction:document.querySelector('.journey').dataset.direction,
                animation:getComputedStyle(arrow).animationName,
                action:{x:frame.x,y:frame.y,width:frame.width,height:frame.height}
              };
            };
            new MutationObserver(capture).observe(document.getElementById('root'), {subtree:true,childList:true,attributes:true});
            return true;
            """)
    }

    func pendingObservation() async throws -> [String: Any] {
        let value = try await script("return window.__per85Pending") as? [String: Any]
        return try XCTUnwrap(value, "pending state was not observed")
    }

    var hasHeldCompletion: Bool { completionHolder?.hasHeldCompletion == true }
    func holdNextCompletion() { completionHolder?.holdNextCompletion() }
    func releaseCompletion() { completionHolder?.releaseCompletion() }

    func signalHost(_ name: String) async throws {
        let available = try await control(name)
        XCTAssertTrue(available, "host did not expose \(name)")
    }

    func waitForHost(_ name: String) async throws {
        try await wait("host control \(name)") { try await self.control(name) }
    }

    private func control(_ name: String) async throws -> Bool {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "http://127.0.0.1:8787/stage1/\(name).txt")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func click(_ label: String) async throws {
        let clicked = try await script("""
            const button = [...document.querySelectorAll('button')].find(value => value.textContent.trim() === label);
            if (!button || button.disabled) return false;
            button.click(); return true;
            """, ["label": label]) as? Bool
        XCTAssertEqual(clicked, true, "real enabled button missing: \(label)")
    }

    func scrollTop() async throws { _ = try await script("scrollTo(0,0); return true") }
    func scrollToAction() async throws { _ = try await script("document.querySelector('.outcome button').scrollIntoView({block:'end'}); return true") }
    func setRootTextScale(_ scale: Double) async throws {
        _ = try await script("document.documentElement.style.fontSize = `${scale * 100}%`; return true", ["scale": scale])
    }
    func boolean(_ expression: String) async throws -> Bool { try await script("return Boolean(\(expression))") as? Bool == true }
    func number(_ expression: String) async throws -> Double { (try await script("return \(expression)") as? NSNumber)?.doubleValue ?? .nan }
    func bodyContains(_ value: String) async throws -> Bool { try await boolean("document.body.innerText.includes(value)", ["value": value]) }
    func exists(_ selector: String) async throws -> Bool { try await boolean("document.querySelector(selector) !== null", ["selector": selector]) }
    func exists(_ selector: String, containing value: String) async throws -> Bool {
        try await boolean("[...document.querySelectorAll(selector)].some(node => node.textContent.includes(value))", ["selector": selector, "value": value])
    }
    func text(_ selector: String) async throws -> String {
        let value = try await script("return document.querySelector(selector)?.textContent?.trim()", ["selector": selector]) as? String
        return try XCTUnwrap(value)
    }
    func attribute(_ selector: String, _ name: String) async throws -> String {
        let value = try await script("return document.querySelector(selector)?.getAttribute(name)", ["selector": selector, "name": name]) as? String
        return try XCTUnwrap(value)
    }

    private func boolean(_ expression: String, _ arguments: [String: Any]) async throws -> Bool {
        try await script("return Boolean(\(expression))", arguments) as? Bool == true
    }

    private func script(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Any {
        try await view.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page) as Any
    }
}

private final class CompletionHoldingNetworkClient: HTTPNetworkClient, @unchecked Sendable {
    private let underlying = URLSessionNetworkClient()
    private let lock = NSLock()
    private var shouldHold = false
    private var heldCompletion: (@Sendable () -> Void)?

    var hasHeldCompletion: Bool {
        lock.lock()
        defer { lock.unlock() }
        return heldCompletion != nil
    }

    func holdNextCompletion() {
        lock.lock()
        precondition(!shouldHold && heldCompletion == nil)
        shouldHold = true
        lock.unlock()
    }

    func releaseCompletion() {
        lock.lock()
        let completion = heldCompletion
        heldCompletion = nil
        lock.unlock()
        precondition(completion != nil)
        completion?()
    }

    func makeTask(
        request: URLRequest,
        eventHandler: @escaping @Sendable (NetworkEvent) -> Void
    ) -> HTTPNetworkTask {
        underlying.makeTask(request: request) { [weak self] event in
            guard let self else {
                eventHandler(event)
                return
            }
            if case .complete = event {
                self.lock.lock()
                if self.shouldHold {
                    self.shouldHold = false
                    self.heldCompletion = { eventHandler(event) }
                    self.lock.unlock()
                    return
                }
                self.lock.unlock()
            }
            eventHandler(event)
        }
    }
}
#endif
