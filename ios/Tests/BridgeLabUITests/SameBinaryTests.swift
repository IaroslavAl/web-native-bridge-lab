import XCTest

/// Real application UI automation. Control HTTP is test-runner synchronization only:
/// it never calls the API port, injects JavaScript, or supplies application results.
final class SameBinaryTests: XCTestCase {
    private let controlBase = "http://127.0.0.1:8787/stage1/"

    private func control(_ name: String) async throws -> Bool {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: controlBase + name + ".txt")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func waitForHost(_ name: String) async throws {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if (try? await control(name)) == true { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTFail("Host coordination timed out: \(name)")
        throw NSError(domain: "SameBinaryTests", code: 1)
    }

    @MainActor
    private func requireText(_ text: String, in app: XCUIApplication) throws {
        let element = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        guard element.waitForExistence(timeout: 20) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Missing text: \(text)"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("Actual React accessibility text missing: \(text)")
            throw NSError(domain: "SameBinaryTests", code: 2)
        }
    }

    @MainActor
    private func retain(_ name: String, in app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
    }

    @MainActor
    private func assertInstalledLayout(action label: String, name: String, in app: XCUIApplication) {
        let bounds = app.windows.firstMatch.frame
        let webView = app.webViews.firstMatch
        let action = app.webViews.buttons[label]
        let footer = app.staticTexts["lab.nativeVersion"]
        XCTAssertTrue(webView.exists, "Installed WKWebView missing")
        XCTAssertTrue(action.waitForExistence(timeout: 10), "Current action missing: \(label)")
        XCTAssertTrue(action.isHittable, "Current action must be visible and usable from scroll top: \(label)")
        XCTAssertTrue(footer.waitForExistence(timeout: 10), "Native identity missing")
        XCTAssertGreaterThanOrEqual(webView.frame.minY, bounds.minY + 20, "native top safe area/chrome")
        XCTAssertLessThanOrEqual(webView.frame.maxY, footer.frame.minY + 1, "web content must not overlap footer")
        XCTAssertLessThanOrEqual(footer.frame.maxY, bounds.maxY - 10, "native footer respects bottom safe area")
        XCTAssertTrue(webView.frame.contains(action.frame), "current action lies inside visible WKWebView")
        retain(name, in: app)
    }

    @MainActor
    func testWebOnlyUpdateOnSameInstalledApplication() async throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "lab.webnative.BridgeLab")
        app.launch()
        try await waitForHost("ready") // existence request signals host to hash installed app
        try await waitForHost("a-release")
        let explain = (try? await control("explain-enabled")) == true
        try requireText("Сначала запросим настоящий каталог", in: app)
        if explain {
            XCTAssertFalse(app.webViews.buttons["Рассчитать заказ"].exists, "A must not expose quote")
            assertInstalledLayout(action: "Получить каталог", name: "Installed default A layout", in: app)
        }
        let catalog = app.webViews.buttons["Получить каталог"]
        XCTAssertTrue(catalog.waitForExistence(timeout: 10))
        catalog.tap()
        try requireText("Ответ каталога", in: app)
        try requireText("Notebook", in: app)
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "Actual React catalog A"; a.lifetime = .keepAlways; add(a)
        if explain {
            let unchanged = app.webViews.buttons["Загрузить обновлённый экран"]
            XCTAssertTrue(unchanged.waitForExistence(timeout: 10))
            unchanged.tap()
            try requireText("Загружен прежний веб-экран", in: app)
            XCTAssertFalse(app.webViews.buttons["Рассчитать заказ"].exists, "unchanged A must not expose quote")
            assertInstalledLayout(action: "Проверить обновление ещё раз", name: "Installed unchanged A layout", in: app)
        }
        try await waitForHost("a-observed")
        try await waitForHost("b-release")
        // No launch, native build, install or application configuration change between A and B.
        let update = app.webViews.buttons[explain ? "Проверить обновление ещё раз" : "Загрузить обновлённый экран"]
        XCTAssertTrue(update.waitForExistence(timeout: 10))
        update.tap()
        try requireText("Раньше вы получили каталог", in: app)
        let quote = app.webViews.buttons["Рассчитать заказ"]
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
        quote.tap()
        try requireText("Расчёт получен", in: app)
        try requireText("Блокнот", in: app)
        if explain {
            try requireText("12,00", in: app)
            assertInstalledLayout(action: "Рассчитать снова", name: "Installed default B result layout", in: app)
        }
        let b = XCTAttachment(screenshot: app.screenshot())
        b.name = "Actual React quote B"; b.lifetime = .keepAlways; add(b)
        try await waitForHost("b-observed")
        try await waitForHost("finish") // host hashes B before test runner terminates the app
        if explain {
            let defaultFooterHeight = app.staticTexts["lab.nativeVersion"].frame.height
            try await explainRuntimeEvidence(in: app, defaultFooterHeight: defaultFooterHeight)
            try await waitForHost("matrix-observed")
            return
        }
        if try await control("production-ux-enabled") {
            try productionDiagnostics(in: app)
            try await waitForHost("matrix-observed")
            return
        }
        if try await control("diagnostics-enabled") {
            app.buttons["lab.reload"].tap()
            try requireText("Stage2 test-only outcomes", in: app)
            if try await control("trust-enabled") {
                app.webViews.buttons["Run trust probes"].tap()
                for result in ["Closed wire, numeric/session validation and high-water PASS",
                               "Raw 131072/+1 and Unicode body 65536/+1 PASS",
                               "API origin, URL/header denial and redirects PASS",
                               "Hostile response rendered as inert text PASS",
                               "Chunked response 1048576/+1, binary and UTF-8 PASS",
                               "Eight admitted, ninth BUSY, active duplicate isolated PASS",
                               "Same/foreign frames blocked by production CSP before bridge PASS",
                               "Trust and limits matrix PASS"] {
                    try requireText(result, in: app)
                }
                let trust = XCTAttachment(string: app.debugDescription)
                trust.name = "Actual installed-shell Stage3 trust and limits"
                trust.lifetime = .keepAlways
                add(trust)
                try await waitForHost("matrix-observed")
                return
            }
            app.webViews.buttons["Run outcome probes"].tap()
            for result in ["HTTP 503 preserved", "HTTP 422 preserved", "Business error interpreted",
                           "Malformed JSON preserved", "Native TIMEOUT", "Explicit CANCELLED",
                           "Concurrent fast then slow", "Outcome matrix PASS"] {
                try requireText(result, in: app)
            }
            try await waitForHost("matrix-observed")
            // The host stops its owned services after observing the complete matrix.
            // This control request is web-port-only, never an API replacement.
            let deadline = Date().addingTimeInterval(30)
            var stopped = false
            while Date() < deadline {
                do { _ = try await control("matrix-observed") }
                catch { stopped = true; break }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            XCTAssertTrue(stopped, "Owned web service still reachable before network-error probe")
            app.webViews.buttons["Probe stopped backend"].tap()
            try requireText("NETWORK_ERROR after backend stop", in: app)
            let outcomes = XCTAttachment(string: app.debugDescription)
            outcomes.name = "Actual installed-shell Stage2 outcomes"
            outcomes.lifetime = .keepAlways
            add(outcomes)
        }
    }

    @MainActor
    private func explainRuntimeEvidence(in app: XCUIApplication, defaultFooterHeight: CGFloat) async throws {
        try await waitForHost("api-failure-ready")
        try await waitForHost("api-failure-release")
        app.webViews.buttons["Рассчитать снова"].tap()
        try requireText("Не удалось связаться с сервером", in: app)
        XCTAssertTrue(app.webViews.buttons["Повторить расчёт"].isHittable)
        retain("Installed unavailable API error", in: app)
        try await waitForHost("api-failure-observed")
        try await waitForHost("api-recovery-release")
        app.webViews.buttons["Повторить расчёт"].tap()
        try requireText("Расчёт получен", in: app)
        try await waitForHost("api-recovery-observed")

        try await waitForHost("asset-failure-ready")
        try await waitForHost("asset-failure-release")
        app.buttons["lab.reload"].tap()
        try requireText("Веб-экран не запустился", in: app)
        XCTAssertFalse(app.webViews.buttons["Рассчитать заказ"].exists, "missing entry cannot retain a business action")
        retain("Installed missing entry fallback", in: app)
        try await waitForHost("asset-failure-observed")
        try await waitForHost("asset-recovery-release")
        app.buttons["lab.reload"].tap()
        try requireText("Этот экран умеет рассчитать заказ", in: app)

        let footer = app.staticTexts["lab.nativeVersion"]
        footer.press(forDuration: 1)
        let diagnostics = app.buttons["lab.openDiagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        try requireText("Diagnostics", in: app)
        footer.press(forDuration: 1)
        let demo = app.buttons["lab.openDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        demo.tap()
        try requireText("Этот экран умеет рассчитать заказ", in: app)
        XCTAssertFalse(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Раньше вы получили каталог")).firstMatch.exists,
                       "cold B must not invent catalog history")

        app.webViews.buttons["Рассчитать заказ"].tap()
        try requireText("Расчёт получен", in: app)
        app.webViews.buttons["Рассчитать снова"].tap()
        try requireText("Расчёт получен", in: app)

        try await waitForHost("large-text-ready")
        try await waitForHost("large-text-release")
        app.terminate()
        app.launch()
        try requireText("Этот экран умеет рассчитать заказ", in: app)
        let heading = app.webViews.staticTexts["Как это работает"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "enlarged Explain heading remains readable")
        let currentAction = app.webViews.buttons["Рассчитать заказ"]
        for _ in 0..<6 where !currentAction.isHittable {
            app.webViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(currentAction.isHittable, "enlarged-text current action remains reachable")
        XCTAssertTrue(footer.exists, "native identity remains available at enlarged text")
        XCTAssertGreaterThan(footer.frame.height, defaultFooterHeight,
                             "owned Simulator content-size setting enlarges installed native identity")
        retain("Installed enlarged text scrolling", in: app)
    }

    @MainActor
    private func productionDiagnostics(in app: XCUIApplication) throws {
        func tap(_ label: String) {
            let button = app.webViews.buttons[label]
            for _ in 0..<6 {
                if button.isHittable { break }
                app.webViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(button.isHittable, "Production button not hittable: \(label)")
            button.tap()
        }
        let footer = app.staticTexts["lab.nativeVersion"]
        XCTAssertTrue(footer.waitForExistence(timeout: 10), "Native version footer missing")
        XCTAssertTrue(footer.label.contains("Версия приложения 1.0"), "Actual Bundle version missing: \(footer.label)")
        footer.press(forDuration: 1)
        let openDiagnostics = app.buttons["lab.openDiagnostics"]
        XCTAssertTrue(openDiagnostics.waitForExistence(timeout: 5), "Diagnostics context action missing")
        XCTAssertEqual(openDiagnostics.label, "Диагностика")
        openDiagnostics.tap()
        try requireText("Diagnostics", in: app)
        app.buttons["lab.reload"].tap()
        try requireText("Diagnostics", in: app)
        XCTAssertFalse(app.webViews.buttons["Cancel active request"].isEnabled)
        tap("HTTP error")
        try requireText("HTTP: HTTP 503: {\"error\":{\"code\":\"UNAVAILABLE\",\"message\":\"Try later\"}}", in: app)
        tap("Business error")
        try requireText("business: OUT_OF_STOCK: Not available", in: app)
        tap("Malformed JSON")
        try requireText("JSON parse: Response body is not valid JSON.", in: app)
        tap("Native timeout")
        try requireText("transport TIMEOUT:", in: app)
        tap("Run concurrent requests")
        let loading = XCTAttachment(string: app.debugDescription)
        loading.name = "Production loading accessibility tree"
        loading.lifetime = .keepAlways
        add(loading)
        try requireText("loading", in: app)
        XCTAssertTrue(app.webViews.buttons["Cancel active request"].isEnabled)
        tap("Cancel active request")
        try requireText("transport CANCELLED:", in: app)
        try requireText("fast — 10 ms", in: app)
        XCTAssertFalse(app.webViews.buttons["Cancel active request"].isEnabled)
        XCTAssertFalse(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "slow — 10000 ms")).firstMatch.exists)
        XCTAssertFalse(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "loading")).firstMatch.exists)
        let evidence = XCTAttachment(string: app.debugDescription)
        evidence.name = "Actual production Diagnostics UI"
        evidence.lifetime = .keepAlways
        add(evidence)

        footer.press(forDuration: 1)
        let openDemo = app.buttons["lab.openDemo"]
        XCTAssertTrue(openDemo.waitForExistence(timeout: 5), "Return-to-demo context action missing")
        XCTAssertEqual(openDemo.label, "Вернуться к демо")
        openDemo.tap()
        try requireText("Этот экран умеет рассчитать заказ", in: app)
        XCTAssertTrue(app.webViews.buttons["Рассчитать заказ"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.buttons["HTTP error"].exists, "Diagnostics controls remained in demo")
    }
}
