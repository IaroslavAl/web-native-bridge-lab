#if !SWIFT_PACKAGE
import WebKit
import XCTest
import TransportPackage
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

    func testProvisionalFailureRevokesDocument() async {
        let executor = AdapterExecutor()
        let adapter = makeAdapter(executor: executor)
        _ = await activate(adapter)

        adapter.provisionalNavigationFailed()
        let denied = await reply(from: adapter, incoming: .trusted(helloJSON))
        let cancelAllCount = await executor.cancelAllCount

        XCTAssertEqual(denied["code"] as? String, "ORIGIN_DENIED")
        XCTAssertEqual(cancelAllCount, 1)
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

    func testLateSuccessAfterReloadIsRetiredAsCancelledWithoutAffectingFreshIDOne() async {
        let executor = AdapterExecutor(suspendRequests: true)
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

    private func makeAdapter(executor: AdapterExecutor) -> WKBridgeAdapter {
        let sessions = SessionSequence([
            String(repeating: "1", count: 32),
            String(repeating: "2", count: 32),
            String(repeating: "3", count: 32)
        ])
        let engine = BridgeEngine(executor: executor, sessionGenerator: { sessions.next() })
        return WKBridgeAdapter(engine: engine, policy: .production)
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
    private var result: [String: Any]?
    private var waiters: [CheckedContinuation<[String: Any], Never>] = []

    func record(_ value: Any?, _ error: String?) {
        let object = value as? [String: Any] ?? ["callbackError": error ?? "missing reply"]
        result = object
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: object)
        }
    }

    func value() async -> [String: Any] {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor AdapterExecutor: HTTPExecuting {
    private(set) var requests: [HTTPRequest] = []
    private(set) var cancelAllCount = 0
    private let suspendRequests: Bool
    private let cancelPendingRequests: Bool
    private var pending: [Int: [CheckedContinuation<HTTPResult, Never>]] = [:]

    init(suspendRequests: Bool = false, cancelPendingRequests: Bool = false) {
        self.suspendRequests = suspendRequests
        self.cancelPendingRequests = cancelPendingRequests
    }

    var requestCount: Int { requests.count }

    func execute(_ request: HTTPRequest) async -> HTTPResult {
        requests.append(request)
        guard suspendRequests else {
            return .response(.init(id: request.id, status: 200, headers: [:], body: "ok"))
        }
        return await withCheckedContinuation { continuation in
            pending[request.id, default: []].append(continuation)
        }
    }

    func cancel(id: Int) async -> Bool { false }

    func cancelAll() async {
        cancelAllCount += 1
        guard cancelPendingRequests else { return }
        let cancelled = pending
        pending.removeAll()
        for (id, continuations) in cancelled {
            for continuation in continuations {
                continuation.resume(returning: .failure(.init(
                    id: id,
                    code: "CANCELLED",
                    message: "Request was cancelled"
                )))
            }
        }
    }

    func resolve(id: Int, with result: HTTPResult) {
        let continuation = pending[id]?.removeFirst()
        if pending[id]?.isEmpty == true {
            pending[id] = nil
        }
        continuation?.resume(returning: result)
    }

    func waitForRequestCount(_ expected: Int) async {
        while requests.count < expected {
            await Task.yield()
        }
    }

    func waitForCancelAllCount(_ expected: Int) async {
        while cancelAllCount < expected {
            await Task.yield()
        }
    }
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

private func requestJSON(session: String, id: Int) -> String {
    #"{"v":1,"type":"request","session":"\#(session)","id":\#(id),"method":"GET","url":"http://127.0.0.1:8788/test","headers":{},"body":null,"timeoutMs":5000}"#
}
#endif
