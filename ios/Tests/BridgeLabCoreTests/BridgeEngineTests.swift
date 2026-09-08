import XCTest
import TransportPackage
#if SWIFT_PACKAGE
@testable import BridgeLabCore
#else
@testable import BridgeLab
#endif

final class BridgeEngineTests: XCTestCase {
    func testHugeVersionReturnsUnsupportedWithoutTrapping() async {
        let executor = RecordingExecutor()
        let engine = BridgeEngine(executor: executor)
        await engine.activateDocument()
        let reply = await engine.handle(.trusted(#"{"v":9223372036854775808,"type":"hello"}"#))
        XCTAssertEqual(reply, .error(id: nil, code: "UNSUPPORTED_VERSION", message: "Unsupported bridge version"), "v: oversized integer must not trap")
        let count = await executor.requestCount
        XCTAssertEqual(count, 0, "v: invalid version must not submit transport work")
    }

    func testHugeRecoveredIDReturnsInvalidWithoutTrapping() async {
        let executor = RecordingExecutor()
        let engine = BridgeEngine(executor: executor)
        await engine.activateDocument()
        let reply = await engine.handle(.trusted(#"{"v":1,"type":"unknown","id":9223372036854775808}"#))
        XCTAssertEqual(reply, .error(id: nil, code: "INVALID_REQUEST", message: "Invalid bridge request"), "id: oversized integer must not trap or be recovered")
        let count = await executor.requestCount
        XCTAssertEqual(count, 0, "id: invalid envelope must not submit transport work")
    }

    // Raw tokens keep test-side conversion from hiding parser overflow.
    private let numericExtremes = [
        "9223372036854774784", "9223372036854775807", "9223372036854775808",
        "9223372036854777856", "-9223372036854774784", "-9223372036854775808",
        "-9223372036854775809", "-9223372036854777856", "1e100", "-1e100"
    ]

    func testNumericVersionMatrixPreservesPrecedenceAndRecoverableID() async {
        let executor = RecordingExecutor()
        let engine = BridgeEngine(executor: executor)
        await engine.activateDocument()
        for value in numericExtremes + ["0", "2", "true", "false", "1.5", "\"1\"", "null"] {
            let reply = await engine.handle(.trusted(#"{"v":\#(value),"type":"request","id":7,"session":"bad"}"#))
            XCTAssertEqual(reply, .error(id: 7, code: "UNSUPPORTED_VERSION", message: "Unsupported bridge version"), "v=\(value): version precedes shape/session; recover id")
        }
        for value in ["1", "1.0", "1e0"] {
            let reply = await engine.handle(.trusted(#"{"v":\#(value),"type":"hello"}"#))
            guard case .helloAck = reply else {
                XCTFail("v=\(value): numeric one must be supported; got \(reply)")
                continue
            }
        }
        let count = await executor.requestCount
        XCTAssertEqual(count, 0, "v matrix: no transport admission")
    }

    func testInvalidNumericIDsCannotSubmitCancelOrConsumeHighWaterMark() async {
        let session = String(repeating: "a", count: 32)
        let executor = RecordingExecutor()
        let engine = BridgeEngine(executor: executor, sessionGenerator: { session })
        await engine.activateDocument()
        for value in numericExtremes + ["-1", "0", "2147483648", "true", "false", "1.5", "\"1\"", "null"] {
            let request = requestJSON(session: session, id: 1).replacingOccurrences(of: "\"id\":1,", with: "\"id\":\(value),")
            let cancel = #"{"v":1,"type":"cancel","session":"\#(session)","id":\#(value)}"#
            let unknown = #"{"v":1,"type":"unknown","id":\#(value)}"#
            for raw in [request, cancel, unknown] {
                let reply = await engine.handle(.trusted(raw))
                XCTAssertEqual(reply, .error(id: nil, code: "INVALID_REQUEST", message: "Invalid bridge request"), "id=\(value): invalid id must not be recovered; envelope=\(raw)")
            }
        }
        let count = await executor.requestCount
        let cancelled = await executor.cancelled
        XCTAssertEqual(count, 0, "id matrix: no transport admission")
        XCTAssertEqual(cancelled, [], "id matrix: no executor cancellation")
        let fresh = await engine.handle(.trusted(requestJSON(session: session, id: 1)))
        XCTAssertEqual(fresh.errorCode, "NETWORK_ERROR", "id: valid 1 still reaches recording executor after invalid ids")
        let finalCount = await executor.requestCount
        XCTAssertEqual(finalCount, 1, "id: invalid ids did not consume high-water mark")
    }

    func testNonIntegralAndOverflowTimeoutsDoNotConsumeID() async {
        let session = String(repeating: "b", count: 32)
        let executor = RecordingExecutor()
        let engine = BridgeEngine(executor: executor, sessionGenerator: { session })
        await engine.activateDocument()
        for value in ["9223372036854775808", "9223372036854775807", "-9223372036854777856", "1e100", "-1e100", "true", "false", "1.5", "\"1\"", "null"] {
            let raw = requestJSON(session: session, id: 1).replacingOccurrences(of: "\"timeoutMs\":5000", with: "\"timeoutMs\":\(value)")
            let reply = await engine.handle(.trusted(raw))
            XCTAssertEqual(reply, .error(id: 1, code: "INVALID_REQUEST", message: "Invalid bridge request"), "timeoutMs=\(value): malformed numeric value preserves recovered id")
        }
        let count = await executor.requestCount
        XCTAssertEqual(count, 0, "timeoutMs: structural failures must not submit")
        let fresh = await engine.handle(.trusted(requestJSON(session: session, id: 1)))
        XCTAssertEqual(fresh.errorCode, "NETWORK_ERROR", "timeoutMs: valid retry with id 1 must reach executor")
        let finalCount = await executor.requestCount
        XCTAssertEqual(finalCount, 1, "timeoutMs: structural failures must not consume id")
    }

    func testRepresentableTimeoutBoundaryFailuresRemainTransportValidation() async {
        let session = String(repeating: "c", count: 32)
        for value in ["-9223372036854775808", "-9223372036854775809", "-9223372036854774784", "9223372036854774784", "-1", "0", "30001"] {
            let engine = BridgeEngine(executor: HTTPExecutor(policy: .init(allowedOrigin: URL(string: "http://127.0.0.1:8788")!)), sessionGenerator: { session })
            await engine.activateDocument()
            // Denied URL is a safety guard: never start sockets even if an
            // invalid timeout unexpectedly passes transport validation.
            let raw = requestJSON(session: session, id: 1)
                .replacingOccurrences(of: "\"timeoutMs\":5000", with: "\"timeoutMs\":\(value)")
                .replacingOccurrences(of: "127.0.0.1:8788", with: "127.0.0.1:1")
            let reply = await engine.handle(.trusted(raw))
            XCTAssertEqual(reply, .error(id: 1, code: "INVALID_REQUEST", message: "Request timeout is invalid"), "timeoutMs=\(value): real transport timeout validation precedes URL policy")
            let duplicate = await engine.handle(.trusted(raw))
            XCTAssertEqual(duplicate, .error(id: 1, code: "INVALID_REQUEST", message: "Invalid bridge request"), "timeoutMs=\(value): semantic failure consumes id as before")
        }
    }

    func testOrdinaryNumericBoundsAndIntegralNotationRemainExact() async {
        let session = String(repeating: "d", count: 32)
        let executor = RecordingExecutor(result: .response(.init(id: 1, status: 204, headers: [:], body: "")))
        let engine = BridgeEngine(executor: executor, sessionGenerator: { session })
        await engine.activateDocument()
        let values = [(1, "1.0", 1, "1e0"), (2_147_483_646, "2147483646", 29_999, "29999"), (2_147_483_647, "2147483647.0", 30_000, "3e4")]
        for (id, idJSON, timeout, timeoutJSON) in values {
            let raw = requestJSON(session: session, id: 1)
                .replacingOccurrences(of: "\"id\":1,", with: "\"id\":\(idJSON),")
                .replacingOccurrences(of: "\"timeoutMs\":5000", with: "\"timeoutMs\":\(timeoutJSON)")
            let reply = await engine.handle(.trusted(raw))
            XCTAssertEqual(reply.responseID, id, "id=\(idJSON): exact inclusive boundary")
            let recorded = await executor.requests.last
            XCTAssertEqual(recorded?.timeoutMs, timeout, "timeoutMs=\(timeoutJSON): exact inclusive boundary")
        }
        let cancel = await engine.handle(.trusted(cancelJSON(session: session, id: 2_147_483_647)))
        XCTAssertEqual(cancel, .cancelAck(id: 2_147_483_647, cancelled: false), "id: maximum valid cancel remains recoverable")
    }

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
