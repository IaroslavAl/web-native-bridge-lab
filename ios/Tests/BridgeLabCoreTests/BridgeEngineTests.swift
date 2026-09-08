import XCTest
import TransportPackage
#if SWIFT_PACKAGE
@testable import BridgeLabCore
#else
@testable import BridgeLab
#endif

final class BridgeEngineTests: XCTestCase {
    func testHelloReturnsStableSessionWithoutResettingRequestIDs() async {
        let executor = RecordingExecutor(result: .response(.init(id: 1, status: 204, headers: [:], body: "")))
        let engine = BridgeEngine(executor: executor, sessionGenerator: { String(repeating: "a", count: 32) })
        await engine.activateDocument()

        let firstHello = await engine.handle(.trusted(#"{"v":1,"type":"hello"}"#))
        let request = await engine.handle(.trusted(requestJSON(session: String(repeating: "a", count: 32), id: 1)))
        let secondHello = await engine.handle(.trusted(#"{"v":1,"type":"hello"}"#))
        let duplicate = await engine.handle(.trusted(requestJSON(session: String(repeating: "a", count: 32), id: 1)))

        XCTAssertEqual(firstHello, .helloAck(session: String(repeating: "a", count: 32)))
        XCTAssertEqual(request, .response(.init(id: 1, status: 204, headers: [:], body: "")))
        XCTAssertEqual(secondHello, firstHello)
        XCTAssertEqual(duplicate.errorCode, "INVALID_REQUEST")
        let requestCount = await executor.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testUntrustedAndInactiveMessagesAreDeniedBeforeParsing() async {
        let executor = RecordingExecutor()
        let engine = BridgeEngine(executor: executor)

        let inactive = await engine.handle(.trusted("not-json"))
        await engine.activateDocument()
        let untrusted = await engine.handle(.untrusted)

        XCTAssertEqual(inactive, .error(id: nil, code: "ORIGIN_DENIED", message: "Bridge origin denied"))
        XCTAssertEqual(untrusted, inactive)
        let requestCount = await executor.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testRawInputValidationAndUnsupportedVersionPrecedence() async {
        let engine = BridgeEngine(executor: RecordingExecutor())
        await engine.activateDocument()

        let nonString = await engine.handle(.trustedNonString)
        let invalidJSON = await engine.handle(.trusted("{"))
        let missingVersion = await engine.handle(.trusted(#"{"type":"hello"}"#))
        let stringVersion = await engine.handle(.trusted(#"{"v":"1","type":"hello"}"#))
        let futureVersion = await engine.handle(.trusted(#"{"v":2,"type":"hello","extra":true}"#))
        let oversize = await engine.handle(.trusted(String(repeating: "x", count: 131_073)))

        XCTAssertEqual(nonString.errorCode, "INVALID_REQUEST")
        XCTAssertEqual(invalidJSON.errorCode, "INVALID_REQUEST")
        XCTAssertEqual(missingVersion.errorCode, "UNSUPPORTED_VERSION")
        XCTAssertEqual(stringVersion.errorCode, "UNSUPPORTED_VERSION")
        XCTAssertEqual(futureVersion.errorCode, "UNSUPPORTED_VERSION")
        XCTAssertEqual(oversize.errorCode, "MESSAGE_TOO_LARGE")
    }

    func testClosedRequestShapeAndSessionValidationPrecedeIDConsumption() async {
        let executor = RecordingExecutor(result: .response(.init(id: 1, status: 200, headers: [:], body: "ok")))
        let session = String(repeating: "b", count: 32)
        let engine = BridgeEngine(executor: executor, sessionGenerator: { session })
        await engine.activateDocument()

        let unknownField = requestJSON(session: session, id: 1).dropLast() + ",\"extra\":true}"
        let malformed = await engine.handle(.trusted(String(unknownField)))
        let stale = await engine.handle(.trusted(requestJSON(session: String(repeating: "c", count: 32), id: 1)))
        let valid = await engine.handle(.trusted(requestJSON(session: session, id: 1)))

        XCTAssertEqual(malformed.errorCode, "INVALID_REQUEST")
        XCTAssertEqual(stale.errorCode, "ORIGIN_DENIED")
        XCTAssertEqual(valid, .response(.init(id: 1, status: 200, headers: [:], body: "ok")))
        let requestCount = await executor.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testSemanticFailureConsumesIDAndBodyRemainsOpaque() async {
        let session = String(repeating: "d", count: 32)
        let executor = RecordingExecutor(result: .failure(.init(id: 1, code: "URL_DENIED", message: "URL origin denied")))
        let engine = BridgeEngine(executor: executor, sessionGenerator: { session })
        await engine.activateDocument()

        let denied = await engine.handle(.trusted(requestJSON(session: session, id: 1, body: #"{"broken":"</script>\\\"☃"}"#)))
        let duplicate = await engine.handle(.trusted(requestJSON(session: session, id: 1)))

        XCTAssertEqual(denied.errorCode, "URL_DENIED")
        XCTAssertEqual(duplicate.errorCode, "INVALID_REQUEST")
        let requestCount = await executor.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testResponsePreservesSafeTextAsStructuredData() async {
        let text = #"quotes " </script> \ ☃"#
        let session = String(repeating: "e", count: 32)
        let executor = RecordingExecutor(result: .response(.init(id: 1, status: 200, headers: ["content-type": "text/plain"], body: text)))
        let engine = BridgeEngine(executor: executor, sessionGenerator: { session })
        await engine.activateDocument()

        let reply = await engine.handle(.trusted(requestJSON(session: session, id: 1)))

        XCTAssertEqual(reply, .response(.init(id: 1, status: 200, headers: ["content-type": "text/plain"], body: text)))
        let object = reply.webObject
        XCTAssertEqual(object["body"] as? String, text)
    }

    func testCancelAcknowledgesOnlyExecutorWinner() async {
        let session = String(repeating: "f", count: 32)
        let executor = RecordingExecutor(cancelledIDs: [3])
        let engine = BridgeEngine(executor: executor, sessionGenerator: { session })
        await engine.activateDocument()

        let active = await engine.handle(.trusted(cancelJSON(session: session, id: 3)))
        let unknown = await engine.handle(.trusted(cancelJSON(session: session, id: 4)))

        XCTAssertEqual(active, .cancelAck(id: 3, cancelled: true))
        XCTAssertEqual(unknown, .cancelAck(id: 4, cancelled: false))
        let cancelled = await executor.cancelled
        XCTAssertEqual(cancelled, [3, 4])
    }

    func testRevocationCancelsAllAndAllowsFreshIDOneOnlyAfterActivation() async {
        let executor = RecordingExecutor(result: .response(.init(id: 1, status: 200, headers: [:], body: "ok")))
        let sessions = SessionSequence([String(repeating: "1", count: 32), String(repeating: "2", count: 32)])
        let engine = BridgeEngine(executor: executor, sessionGenerator: { sessions.next() })
        await engine.activateDocument()
        let oldSession = String(repeating: "1", count: 32)
        _ = await engine.handle(.trusted(requestJSON(session: oldSession, id: 1)))

        await engine.revokeDocument()
        let inactive = await engine.handle(.trusted(requestJSON(session: oldSession, id: 2)))
        XCTAssertEqual(inactive.errorCode, "ORIGIN_DENIED")
        await engine.activateDocument()
        let stale = await engine.handle(.trusted(requestJSON(session: oldSession, id: 2)))
        let fresh = await engine.handle(.trusted(requestJSON(session: String(repeating: "2", count: 32), id: 1)))

        XCTAssertEqual(stale.errorCode, "ORIGIN_DENIED")
        XCTAssertEqual(fresh.responseID, 1)
        let cancelAllCount = await executor.cancelAllCount
        XCTAssertEqual(cancelAllCount, 1)
    }
}

private actor RecordingExecutor: HTTPExecuting {
    private(set) var requests: [HTTPRequest] = []
    private(set) var cancelled: [Int] = []
    private(set) var cancelAllCount = 0
    private let result: HTTPResult
    private let cancelledIDs: Set<Int>

    init(
        result: HTTPResult = .failure(.init(id: 1, code: "NETWORK_ERROR", message: "Network failed")),
        cancelledIDs: Set<Int> = []
    ) {
        self.result = result
        self.cancelledIDs = cancelledIDs
    }

    var requestCount: Int { requests.count }

    func submit(_ request: HTTPRequest) async -> HTTPSubmission {
        .immediate(await execute(request))
    }

    func execute(_ request: HTTPRequest) async -> HTTPResult {
        requests.append(request)
        switch result {
        case .response(let response):
            return .response(.init(id: request.id, status: response.status, headers: response.headers, body: response.body))
        case .failure(let failure):
            return .failure(.init(id: request.id, code: failure.code, message: failure.message))
        }
    }

    func cancel(id: Int) async -> Bool {
        cancelled.append(id)
        return cancelledIDs.contains(id)
    }

    func cancelAll() async {
        cancelAllCount += 1
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

private func requestJSON(session: String, id: Int, body: String? = nil) -> String {
    let bodyJSON = body.map { value in
        let data = try! JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        return String(decoding: data, as: UTF8.self)
    } ?? "null"
    return #"{"v":1,"type":"request","session":"\#(session)","id":\#(id),"method":"GET","url":"http://127.0.0.1:8788/test","headers":{},"body":\#(bodyJSON),"timeoutMs":5000}"#
}

private func cancelJSON(session: String, id: Int) -> String {
    #"{"v":1,"type":"cancel","session":"\#(session)","id":\#(id)}"#
}

private extension BridgeReply {
    var errorCode: String? {
        guard case .error(_, let code, _) = self else { return nil }
        return code
    }

    var responseID: Int? {
        guard case .response(let response) = self else { return nil }
        return response.id
    }
}
