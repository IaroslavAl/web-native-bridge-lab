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
        try requireText("Catalog default", in: app)
        let submit = app.webViews.buttons["Send through native HTTP"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        submit.tap()
        try requireText("Notebook (notebook) — total 1", in: app)
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "Actual React catalog A"; a.lifetime = .keepAlways; add(a)
        try await waitForHost("a-observed")
        try await waitForHost("b-release")
        // No launch, native build, install or application configuration change between A and B.
        app.buttons["lab.reload"].tap()
        try requireText("Quote default", in: app)
        submit.tap()
        try requireText("notebook × 2 — USD 1200 minor units", in: app)
        let b = XCTAttachment(screenshot: app.screenshot())
        b.name = "Actual React quote B"; b.lifetime = .keepAlways; add(b)
        try await waitForHost("b-observed")
        try await waitForHost("finish") // host hashes B before test runner terminates the app
    }
}
