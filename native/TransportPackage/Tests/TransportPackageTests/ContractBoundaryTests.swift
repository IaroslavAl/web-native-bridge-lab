import Foundation
import XCTest
@testable import TransportPackage

final class ContractBoundaryTests: XCTestCase {
    private let origin = URL(string: "http://127.0.0.1:8788")!

    func testSharedSemanticTransportVectors() async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("protocol/v1/examples.json"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let vectors = try XCTUnwrap(document["semanticOnly"] as? [[String: Any]])
        var tested = 0
        for vector in vectors {
            let code = try XCTUnwrap(vector["expectedCode"] as? String)
            if code == "ORIGIN_DENIED" { continue } // Adapter owns document sessions.
            var envelope = try XCTUnwrap((vector["envelope"] ?? vector["baseEnvelope"]) as? [String: Any])
            if let recipe = vector["bodyRecipe"] as? [String: Any] {
                envelope["body"] = String(repeating: try XCTUnwrap(recipe["text"] as? String),
                                          count: try XCTUnwrap(recipe["repeat"] as? Int))
            }
            let network = ImmediateNetwork()
            let executor = HTTPExecutor(policy: TransportPolicy(allowedOrigin: origin), networkClient: network)
            let result = await executor.execute(HTTPRequest(
                id: try XCTUnwrap(envelope["id"] as? Int), method: try XCTUnwrap(envelope["method"] as? String),
                url: try XCTUnwrap(envelope["url"] as? String), headers: try XCTUnwrap(envelope["headers"] as? [String: String]),
                body: envelope["body"] as? String, timeoutMs: try XCTUnwrap(envelope["timeoutMs"] as? Int)
            ))
            XCTAssertEqual(result.failureCode, code, "semantic vector \(vector["name"] ?? "missing")")
            XCTAssertTrue(network.requests.isEmpty, "semantic vector must not start HTTP")
            tested += 1
        }
        XCTAssertEqual(tested, 6, "transport semantic vector count; session vector belongs to adapter")
    }

    func testExactRequestBoundsAndOneByteExcess() async {
        let prefix = "http://127.0.0.1:8788/"
        let exactURL = prefix + String(repeating: "a", count: 8_192 - prefix.utf8.count)
        for (url, body, timeout, expected) in [
            (exactURL, String(repeating: "a", count: 65_536), 30_000, nil),
            (exactURL + "a", "", 30_000, "INVALID_REQUEST"),
            (prefix, String(repeating: "a", count: 65_537), 30_000, "REQUEST_TOO_LARGE"),
            (prefix, "", 1, nil)
        ] as [(String, String, Int, String?)] {
            let network = ImmediateNetwork()
            let executor = HTTPExecutor(policy: TransportPolicy(allowedOrigin: origin), networkClient: network,
                                        deadlineScheduler: InertDeadlineScheduler())
            let result = await executor.execute(HTTPRequest(
                id: 2_147_483_647, method: "POST", url: url,
                headers: ["content-type": "application/json", "x-lab-tag": String(repeating: "a", count: 128)],
                body: body, timeoutMs: timeout
            ))
            XCTAssertEqual(result.failureCode, expected, "request boundary result")
            XCTAssertEqual(network.requests.count, expected == nil ? 1 : 0, "request boundary network starts")
            if expected == nil { XCTAssertEqual(network.requests.first?.httpBody, Data(body.utf8), "opaque JSON body bytes") }
        }
    }

    func testExposedHeaderBoundaryAndRepeatedValues() async {
        for extra in [0, 1] {
            let value = String(repeating: "a", count: 8_192 - "x-lab-tag".utf8.count + extra)
            let network = ImmediateNetwork(events: [
                .response(status: 204, headers: [("X-Lab-Tag", value)], expectedContentLength: 0), .complete(nil)
            ])
            let result = await execute(network)
            XCTAssertEqual(result.failureCode, extra == 0 ? nil : "RESPONSE_TOO_LARGE", "exposed header cap + \(extra)")
        }
        let network = ImmediateNetwork(events: [
            .response(status: 204, headers: [("X-Lab-Tag", "one"), ("x-lab-tag", "two")], expectedContentLength: 0), .complete(nil)
        ])
        let result = await execute(network)
        XCTAssertEqual(result.responseHeaders?["x-lab-tag"], "one, two", "repeated exposed headers arrival order")
    }

    func testNonRedirectHTTPStatusesPreserveOpaqueText() async {
        let body = "<script>\"é\"</script>{invalid-json"
        for status in [200, 304, 422, 503] {
            let network = ImmediateNetwork(events: [
                .response(status: status, headers: [("content-type", "APPLICATION/JSON; charset=other")], expectedContentLength: -1),
                .data(Data(body.utf8)), .complete(nil)
            ])
            let result = await execute(network)
            XCTAssertEqual(result, .response(HTTPResponse(id: 1, status: status,
                headers: ["content-type": "APPLICATION/JSON; charset=other"], body: body)), "HTTP status \(status)")
        }
    }

    private func execute(_ network: ImmediateNetwork) async -> HTTPResult {
        let executor = HTTPExecutor(policy: TransportPolicy(allowedOrigin: origin), networkClient: network)
        return await executor.execute(HTTPRequest(id: 1, method: "GET", url: origin.absoluteString + "/",
                                                 headers: [:], body: nil, timeoutMs: 30_000))
    }
}

private final class ImmediateNetwork: HTTPNetworkClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []
    private let events: [NetworkEvent]
    var requests: [URLRequest] { lock.withLock { storedRequests } }
    init(events: [NetworkEvent] = [.response(status: 204, headers: [], expectedContentLength: 0), .complete(nil)]) {
        self.events = events
    }
    func makeTask(request: URLRequest, eventHandler: @escaping @Sendable (NetworkEvent) -> Void) -> HTTPNetworkTask {
        lock.withLock { storedRequests.append(request) }
        return ImmediateTask(events: events, handler: eventHandler)
    }
}

private final class ImmediateTask: HTTPNetworkTask, @unchecked Sendable {
    let events: [NetworkEvent]
    let handler: @Sendable (NetworkEvent) -> Void
    init(events: [NetworkEvent], handler: @escaping @Sendable (NetworkEvent) -> Void) {
        self.events = events; self.handler = handler
    }
    func resume() { events.forEach(handler) }
    func cancel() {}
}

private struct InertDeadlineScheduler: DeadlineScheduler {
    func schedule(afterMilliseconds milliseconds: Int, action: @escaping @Sendable () async -> Void) -> DeadlineToken {
        InertDeadline()
    }
}
private final class InertDeadline: DeadlineToken, Sendable { func cancel() {} }
