import XCTest
#if SWIFT_PACKAGE
@testable import BridgeLabCore
#else
@testable import BridgeLab
#endif

final class BridgePolicyTests: XCTestCase {
    func testTrustedPageRequiresExactSecurityOriginCommittedURLAndMainFrame() {
        let policy = TrustedPagePolicy.production
        let trusted = BridgeFrameOrigin(scheme: "http", host: "127.0.0.1", port: 8787, isMainFrame: true)

        XCTAssertTrue(policy.allows(frame: trusted, committedURL: URL(string: "http://127.0.0.1:8787/scenario"), isActive: true))
        XCTAssertFalse(policy.allows(frame: .init(scheme: "http", host: "127.0.0.1", port: 8787, isMainFrame: false), committedURL: URL(string: "http://127.0.0.1:8787/"), isActive: true), "same-origin iframe must be denied")
        XCTAssertFalse(policy.allows(frame: .init(scheme: "http", host: "localhost", port: 8787, isMainFrame: true), committedURL: URL(string: "http://127.0.0.1:8787/"), isActive: true), "alternate host must be denied")
        XCTAssertFalse(policy.allows(frame: trusted, committedURL: URL(string: "http://127.0.0.1:8788/"), isActive: true), "committed URL origin must be checked independently")
        XCTAssertFalse(policy.allows(frame: trusted, committedURL: URL(string: "http://127.0.0.1:8787/"), isActive: false), "precommit/inactive document must be denied")
    }

    func testNavigationAllowsOnlyTrustedMainFrameAndRejectsNewWindows() {
        let policy = TrustedPagePolicy.production

        XCTAssertTrue(policy.allowsMainNavigation(to: URL(string: "http://127.0.0.1:8787/next")!, targetIsMainFrame: true))
        XCTAssertFalse(policy.allowsMainNavigation(to: URL(string: "https://127.0.0.1:8787/")!, targetIsMainFrame: true))
        XCTAssertFalse(policy.allowsMainNavigation(to: URL(string: "http://127.0.0.1:8787/")!, targetIsMainFrame: false))
        XCTAssertFalse(policy.allowsMainNavigation(to: nil, targetIsMainFrame: nil), "new windows must be denied")
    }
}
