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
    func testWebOnlyUpdateOnSameInstalledApplication() async throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "lab.webnative.BridgeLab")
        app.launch()
        try await waitForHost("ready") // existence request signals host to hash installed app
        try await waitForHost("a-release")
        try requireText("Сначала запросим настоящий каталог", in: app)
        let catalog = app.webViews.buttons["Получить каталог"]
        XCTAssertTrue(catalog.waitForExistence(timeout: 10))
        catalog.tap()
        try requireText("Ответ каталога", in: app)
        try requireText("Notebook", in: app)
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "Actual React catalog A"; a.lifetime = .keepAlways; add(a)
        try await waitForHost("a-observed")
        try await waitForHost("b-release")
        // No launch, native build, install or application configuration change between A and B.
        let update = app.webViews.buttons["Загрузить обновлённый экран"]
        XCTAssertTrue(update.waitForExistence(timeout: 10))
        update.tap()
        try requireText("Раньше вы получили каталог", in: app)
        let quote = app.webViews.buttons["Рассчитать заказ"]
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
        quote.tap()
        try requireText("Расчёт получен", in: app)
        try requireText("Блокнот", in: app)
        let b = XCTAttachment(screenshot: app.screenshot())
        b.name = "Actual React quote B"; b.lifetime = .keepAlways; add(b)
        try await waitForHost("b-observed")
        try await waitForHost("finish") // host hashes B before test runner terminates the app
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
