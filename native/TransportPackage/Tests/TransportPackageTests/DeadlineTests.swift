import Foundation
import XCTest
@testable import TransportPackage

final class DeadlineTests: XCTestCase {
    private let origin = URL(string: "http://127.0.0.1:49152")!

    func testInjectedDeadlineWinsAndCancelsUnderlyingTask() async {
        let network = MockNetworkClient()
        let deadlines = MockDeadlineScheduler()
        let executor = HTTPExecutor(
            policy: TransportPolicy(allowedOrigin: origin),
            networkClient: network,
            deadlineScheduler: deadlines
        )
        let execution = Task { await executor.execute(request(timeoutMs: 123)) }
        await network.waitUntilStarted(count: 1)

        XCTAssertEqual(deadlines.delays, [123], "native deadline milliseconds")
        await deadlines.fire(at: 0)
        network.send(.response(status: 200, headers: [], expectedContentLength: 0), at: 0)
        network.send(.complete(nil), at: 0)

        let result = await execution.value
        XCTAssertEqual(result.failureCode, "TIMEOUT", "deadline terminal code")
        XCTAssertTrue(network.tasks[0].isCancelled, "deadline underlying task cancellation")
        XCTAssertTrue(deadlines.tokens[0].isCancelled, "deadline token cleanup")
    }

    func testCompletionCancelsDeadline() async {
        let network = MockNetworkClient()
        let deadlines = MockDeadlineScheduler()
        let executor = HTTPExecutor(
            policy: TransportPolicy(allowedOrigin: origin),
            networkClient: network,
            deadlineScheduler: deadlines
        )
        let execution = Task { await executor.execute(request(timeoutMs: 5_000)) }
        await network.waitUntilStarted(count: 1)
        network.send(.response(status: 204, headers: [], expectedContentLength: 0), at: 0)
        network.send(.complete(nil), at: 0)

        let result = await execution.value
        await deadlines.fire(at: 0)
        XCTAssertEqual(result, .response(HTTPResponse(id: 1, status: 204, headers: [:], body: "")), "response before deadline")
        XCTAssertTrue(deadlines.tokens[0].isCancelled, "response deadline cleanup")
        XCTAssertFalse(network.tasks[0].isCancelled, "response should not cancel network task")
    }

    func testRealDeadlineDoesNotDependOnNetworkInactivityTimeout() async {
        let network = MockNetworkClient()
        let executor = HTTPExecutor(policy: TransportPolicy(allowedOrigin: origin), networkClient: network)
        let execution = Task { await executor.execute(request(timeoutMs: 5)) }
        await network.waitUntilStarted(count: 1)

        let result = await execution.value
        XCTAssertEqual(result.failureCode, "TIMEOUT", "real monotonic deadline terminal code")
        XCTAssertTrue(network.tasks[0].isCancelled, "real deadline underlying task cancellation")
    }

    func testAlreadyFiredOldDeadlineCannotCancelReusedIDAfterCancelAll() async {
        let network = MockNetworkClient()
        let deadlines = MockDeadlineScheduler()
        let executor = HTTPExecutor(policy: TransportPolicy(allowedOrigin: origin),
                                    networkClient: network, deadlineScheduler: deadlines)
        let old = Task { await executor.execute(request(timeoutMs: 5_000)) }
        await network.waitUntilStarted(count: 1)
        await executor.cancelAll()
        let oldResult = await old.value
        XCTAssertEqual(oldResult.failureCode, "CANCELLED", "old document result")

        let current = Task { await executor.execute(request(timeoutMs: 5_000)) }
        await network.waitUntilStarted(count: 2)
        // A timer fired before cancellation can arrive after new admission.
        // Await the actual callback's actor hop, not a scheduling sleep.
        await deadlines.fire(at: 0, evenIfCancelled: true)
        XCTAssertFalse(network.tasks[1].isCancelled, "new execution must survive stale deadline")
        network.send(.response(status: 204, headers: [], expectedContentLength: 0), at: 1)
        network.send(.complete(nil), at: 1)
        let currentResult = await current.value
        XCTAssertEqual(currentResult, .response(HTTPResponse(id: 1, status: 204, headers: [:], body: "")),
                       "reused id result belongs to new execution")
    }

    private func request(timeoutMs: Int) -> HTTPRequest {
        HTTPRequest(
            id: 1,
            method: "GET",
            url: "http://127.0.0.1:49152/deadline",
            headers: [:],
            body: nil,
            timeoutMs: timeoutMs
        )
    }
}

private final class MockDeadlineScheduler: DeadlineScheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var storedDelays: [Int] = []
    private var actions: [@Sendable () async -> Void] = []
    private var storedTokens: [MockDeadlineToken] = []

    var delays: [Int] { lock.withLock { storedDelays } }
    var tokens: [MockDeadlineToken] { lock.withLock { storedTokens } }

    func schedule(
        afterMilliseconds milliseconds: Int,
        action: @escaping @Sendable () async -> Void
    ) -> DeadlineToken {
        lock.withLock {
            let token = MockDeadlineToken()
            storedDelays.append(milliseconds)
            actions.append(action)
            storedTokens.append(token)
            return token
        }
    }

    func fire(at index: Int, evenIfCancelled: Bool = false) async {
        let value = lock.withLock { (actions[index], storedTokens[index]) }
        if evenIfCancelled || !value.1.isCancelled {
            await value.0()
        }
    }
}

private final class MockDeadlineToken: DeadlineToken, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}
