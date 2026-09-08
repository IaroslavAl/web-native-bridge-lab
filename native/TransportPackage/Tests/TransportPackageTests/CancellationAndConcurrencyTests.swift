import Foundation
import XCTest
@testable import TransportPackage

final class CancellationAndConcurrencyTests: XCTestCase {
    private let origin = URL(string: "http://127.0.0.1:49152")!

    func testCancelWinsAndLateCompletionHasNoEffect() async {
        let network = MockNetworkClient()
        let executor = makeExecutor(network)
        let execution = Task { await executor.execute(request(id: 1, path: "/slow")) }
        await network.waitUntilStarted(count: 1)

        let cancelled = await executor.cancel(id: 1)
        network.send(.response(status: 200, headers: [("Content-Type", "text/plain")], expectedContentLength: 4), at: 0)
        network.send(.data(Data("late".utf8)), at: 0)
        network.send(.complete(nil), at: 0)

        let executionResult = await execution.value
        let secondCancel = await executor.cancel(id: 1)
        XCTAssertTrue(cancelled, "active cancel acknowledgement")
        XCTAssertEqual(executionResult.failureCode, "CANCELLED", "cancelled execution terminal code")
        XCTAssertTrue(network.tasks[0].isCancelled, "underlying cancelled task")
        XCTAssertFalse(secondCancel, "completed cancel acknowledgement")
    }

    func testResponseWinsBeforeCancel() async {
        let network = MockNetworkClient()
        let executor = makeExecutor(network)
        let execution = Task { await executor.execute(request(id: 1, path: "/fast")) }
        await network.waitUntilStarted(count: 1)
        sendTextResponse("done", to: network, at: 0)

        let executionResult = await execution.value
        let cancelled = await executor.cancel(id: 1)
        XCTAssertEqual(executionResult.responseBody, "done", "response terminal body")
        XCTAssertFalse(cancelled, "post-response cancel acknowledgement")
        XCTAssertFalse(network.tasks[0].isCancelled, "completed task should not be cancelled")
    }

    func testCancelAllSettlesEveryOutstandingExecution() async {
        let network = MockNetworkClient()
        let executor = makeExecutor(network)
        let first = Task { await executor.execute(request(id: 1, path: "/one")) }
        let second = Task { await executor.execute(request(id: 2, path: "/two")) }
        await network.waitUntilStarted(count: 2)

        await executor.cancelAll()
        sendTextResponse("late-one", to: network, at: 0)
        sendTextResponse("late-two", to: network, at: 1)

        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult.failureCode, "CANCELLED", "first cancelAll terminal code")
        XCTAssertEqual(secondResult.failureCode, "CANCELLED", "second cancelAll terminal code")
        XCTAssertTrue(network.tasks.allSatisfy(\.isCancelled), "cancelAll underlying task cancellation")
    }

    func testNinthLiveRequestIsBusyWithoutQueueing() async {
        let network = MockNetworkClient()
        let executor = makeExecutor(network)
        var executions: [Task<HTTPResult, Never>] = []
        for id in 1...8 {
            executions.append(Task { await executor.execute(request(id: id, path: "/\(id)")) })
        }
        await network.waitUntilStarted(count: 8)

        let ninth = Task { await executor.execute(request(id: 9, path: "/9")) }
        try? await Task.sleep(nanoseconds: 5_000_000)
        if network.requests.count == 9 {
            sendTextResponse("unexpected", to: network, at: 8)
        }
        let ninthResult = await ninth.value

        XCTAssertEqual(ninthResult.failureCode, "BUSY", "ninth live request code")
        XCTAssertEqual(network.requests.count, 8, "ninth live request network start")

        for (networkIndex, startedRequest) in network.requests.enumerated() {
            let idText = startedRequest.url?.lastPathComponent ?? "missing"
            sendTextResponse("result-\(idText)", to: network, at: networkIndex)
        }
        for (index, execution) in executions.enumerated() {
            let result = await execution.value
            XCTAssertEqual(result.responseBody, "result-\(index + 1)", "result correlation id \(index + 1)")
        }
    }

    func testOutOfOrderCompletionsRemainCorrelated() async {
        let network = MockNetworkClient()
        let executor = makeExecutor(network)
        let slow = Task { await executor.execute(request(id: 41, path: "/slow")) }
        await network.waitUntilStarted(count: 1)
        let fast = Task { await executor.execute(request(id: 42, path: "/fast")) }
        await network.waitUntilStarted(count: 2)

        sendTextResponse("fast-42", to: network, at: 1)
        sendTextResponse("slow-41", to: network, at: 0)

        let slowResult = await slow.value
        let fastResult = await fast.value
        XCTAssertEqual(slowResult.responseBody, "slow-41", "slow id 41 body")
        XCTAssertEqual(fastResult.responseBody, "fast-42", "fast id 42 body")
    }

    func testDuplicateActiveIDDoesNotReplaceOriginalExecution() async {
        let network = MockNetworkClient()
        let executor = makeExecutor(network)
        let original = Task { await executor.execute(request(id: 5, path: "/original")) }
        await network.waitUntilStarted(count: 1)

        let duplicateResult = await executor.execute(request(id: 5, path: "/duplicate"))
        XCTAssertEqual(duplicateResult.failureCode, "INVALID_REQUEST", "duplicate active id code")
        XCTAssertEqual(network.requests.count, 1, "duplicate active id network start")

        sendTextResponse("original-result", to: network, at: 0)
        let originalResult = await original.value
        XCTAssertEqual(originalResult.responseBody, "original-result", "original execution after duplicate")
    }

    func testLateNetworkEventsDoNotContaminateReusedID() async {
        let network = MockNetworkClient()
        let executor = makeExecutor(network)
        let old = Task { await executor.execute(request(id: 1, path: "/old")) }
        await network.waitUntilStarted(count: 1)
        await executor.cancelAll()
        let oldResult = await old.value
        XCTAssertEqual(oldResult.failureCode, "CANCELLED", "revoked execution result")
        let current = Task { await executor.execute(request(id: 1, path: "/current")) }
        await network.waitUntilStarted(count: 2)
        sendTextResponse("stale", to: network, at: 0)
        network.send(.redirect, at: 0)
        sendTextResponse("current", to: network, at: 1)
        let currentResult = await current.value
        XCTAssertEqual(currentResult.responseBody, "current", "new execution body after old callbacks")
        XCTAssertFalse(network.tasks[1].isCancelled, "new network task after old callbacks")
    }

    private func makeExecutor(_ network: MockNetworkClient) -> HTTPExecutor {
        HTTPExecutor(policy: TransportPolicy(allowedOrigin: origin), networkClient: network)
    }

    private func request(id: Int, path: String) -> HTTPRequest {
        HTTPRequest(
            id: id,
            method: "GET",
            url: "http://127.0.0.1:49152\(path)",
            headers: [:],
            body: nil,
            timeoutMs: 30_000
        )
    }

    private func sendTextResponse(_ body: String, to network: MockNetworkClient, at index: Int) {
        network.send(.response(
            status: 200,
            headers: [("Content-Type", "text/plain")],
            expectedContentLength: Int64(body.utf8.count)
        ), at: index)
        network.send(.data(Data(body.utf8)), at: index)
        network.send(.complete(nil), at: index)
    }
}
