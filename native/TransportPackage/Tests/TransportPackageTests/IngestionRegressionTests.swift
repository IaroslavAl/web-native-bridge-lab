import Foundation
import XCTest
@testable import TransportPackage

final class IngestionRegressionTests: XCTestCase {
    func testRelayRetainsAtMostCapBytesAndOneOverflowDespiteLateBurst() async {
        let relay = NetworkEventRelay()
        let task = MockNetworkTask()
        relay.attach(task: task)
        // No consumer exists until all input has been synchronously submitted.
        for _ in 0..<32 { relay.send(.data(Data(repeating: 65, count: 65_536))) }
        relay.send(.complete(nil))
        var bytes = 0
        var overflowCount = 0
        for await event in relay.stream {
            if case let .data(data) = event { bytes += data.count }
            if case .complete(.responseTooLarge) = event { overflowCount += 1 }
        }
        XCTAssertEqual(bytes, 1_048_576, "retained queue bytes, no excess or truncated chunk")
        XCTAssertEqual(overflowCount, 1, "explicit overflow instead of silent chunk loss")
        XCTAssertTrue(task.isCancelled, "synchronous producer cancellation")
    }

    func testProducerAheadOfActorCancelsAtFirstExcessByte() async {
        let network = BurstNetworkClient()
        let executor = HTTPExecutor(
            policy: TransportPolicy(allowedOrigin: URL(string: "http://127.0.0.1:49152")!),
            networkClient: network
        )
        let result = await executor.execute(HTTPRequest(
            id: 1, method: "GET", url: "http://127.0.0.1:49152/burst",
            headers: [:], body: nil, timeoutMs: 30_000
        ))
        XCTAssertEqual(result.failureCode, "RESPONSE_TOO_LARGE", "overflow terminal code")
        XCTAssertEqual(network.task?.cancellationAtByte, 1_048_577,
                       "producer must see cancellation before the actor can consume queued data")
    }
}

private final class BurstNetworkClient: HTTPNetworkClient, @unchecked Sendable {
    var task: BurstNetworkTask?

    func makeTask(request: URLRequest, eventHandler: @escaping @Sendable (NetworkEvent) -> Void) -> HTTPNetworkTask {
        let task = BurstNetworkTask(handler: eventHandler)
        self.task = task
        return task
    }
}

// resume executes synchronously on the executor actor: the consumer cannot run
// until the whole producer burst returns. No sleeps or scheduling guesses.
private final class BurstNetworkTask: HTTPNetworkTask, @unchecked Sendable {
    private let handler: @Sendable (NetworkEvent) -> Void
    private let lock = NSLock()
    private var cancelled = false
    private(set) var cancellationAtByte: Int?

    init(handler: @escaping @Sendable (NetworkEvent) -> Void) { self.handler = handler }

    func resume() {
        handler(.response(status: 200, headers: [("content-type", "text/plain")], expectedContentLength: -1))
        handler(.data(Data(repeating: 65, count: 1_048_576)))
        handler(.data(Data([66])))
        if lock.withLock({ cancelled }) { cancellationAtByte = 1_048_577 }
        // A misbehaving/late producer must not enqueue more bytes after rejection.
        for _ in 0..<16 { handler(.data(Data(repeating: 67, count: 65_536))) }
        handler(.complete(nil))
    }

    func cancel() { lock.withLock { cancelled = true } }
}
