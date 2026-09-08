import Foundation
import XCTest
@testable import TransportPackage

final class AdmissionTests: XCTestCase {
    func testAcknowledgedAdmissionIsCancelledBeforeAnyResultWaiterAndCannotEscapeIntoReusedID() async {
        let network = MockNetworkClient()
        let executor = HTTPExecutor(
            policy: .init(allowedOrigin: URL(string: "http://127.0.0.1:49152")!),
            networkClient: network
        )
        // submit must return without a network terminal event or a result waiter.
        guard case let .running(old) = await executor.submit(request(id: 1)) else {
            return XCTFail("old admission receipt missing")
        }
        XCTAssertEqual(network.tasks.count, 1, "admission acknowledged network registration")
        XCTAssertTrue(network.tasks[0].isResumed, "admission acknowledged task resume")
        await executor.cancelAll()
        XCTAssertTrue(network.tasks[0].isCancelled, "cancelAll sees acknowledged admission")
        let oldResult = await old.result()
        XCTAssertEqual(oldResult.failureCode, "CANCELLED", "terminal retained before waiter registration")

        guard case let .running(fresh) = await executor.submit(request(id: 1)) else {
            return XCTFail("fresh admission receipt missing")
        }
        XCTAssertNotEqual(old.id, fresh.id, "receipt identity is not wire id")
        network.send(.complete(.other), at: 0)
        network.send(.response(status: 204, headers: [], expectedContentLength: 0), at: 1)
        network.send(.complete(nil), at: 1)
        let freshResult = await fresh.result()
        XCTAssertEqual(freshResult, .response(.init(id: 1, status: 204, headers: [:], body: "")))
        let repeatedOldResult = await old.result()
        XCTAssertEqual(repeatedOldResult, oldResult, "old terminal remains immutable")
        XCTAssertFalse(network.tasks[1].isCancelled, "old callback cannot cancel fresh task")
    }

    func testReceiptsDoNotSerializeEightRequestsAndNinthIsImmediateBusy() async {
        let network = MockNetworkClient()
        let executor = HTTPExecutor(
            policy: .init(allowedOrigin: URL(string: "http://127.0.0.1:49152")!),
            networkClient: network
        )
        var receipts: [HTTPExecution] = []
        for id in 1...8 {
            guard case let .running(receipt) = await executor.submit(request(id: id)) else {
                await executor.cancelAll()
                return XCTFail("missing concurrent receipt \(id)")
            }
            receipts.append(receipt)
        }
        guard case let .immediate(busy) = await executor.submit(request(id: 9)),
              case let .immediate(duplicate) = await executor.submit(request(id: 1)) else {
            await executor.cancelAll()
            return XCTFail("capacity/duplicate rejection must not wait for capacity")
        }
        XCTAssertEqual(busy.failureCode, "BUSY")
        XCTAssertEqual(duplicate.failureCode, "INVALID_REQUEST")
        XCTAssertEqual(network.tasks.count, 8, "no ninth or duplicate network task")
        for index in (0..<8).reversed() {
            network.send(.response(status: 204, headers: [], expectedContentLength: 0), at: index)
            network.send(.complete(nil), at: index)
            let result = await receipts[index].result()
            XCTAssertEqual(result, .response(.init(id: index + 1, status: 204, headers: [:], body: "")))
        }
        await executor.cancelAll()
        XCTAssertFalse(network.tasks.contains(where: \.isCancelled), "completed winners survive cancelAll")
    }

    func testSelectedFailureIsImmutableAndExecutorDoesNotRetainCompletedReceipt() async {
        let network = MockNetworkClient()
        let executor = HTTPExecutor(
            policy: .init(allowedOrigin: URL(string: "http://127.0.0.1:49152")!),
            networkClient: network
        )
        weak var released: HTTPExecution?
        do {
            guard case let .running(receipt) = await executor.submit(request(id: 1)) else {
                return XCTFail("missing receipt")
            }
            released = receipt
            network.send(.complete(.other), at: 0)
            let selected = await receipt.result()
            await executor.cancelAll()
            let afterRevoke = await receipt.result()
            XCTAssertEqual(selected.failureCode, "NETWORK_ERROR")
            XCTAssertEqual(afterRevoke, selected, "cancelAll cannot rewrite selected failure")
        }
        XCTAssertNil(released, "no executor completed-receipt history")
        let invalid = await executor.submit(request(id: 0))
        guard case let .immediate(result) = invalid else { return XCTFail("invalid admission must be immediate") }
        XCTAssertEqual(result.failureCode, "INVALID_REQUEST")
        XCTAssertEqual(network.tasks.count, 1, "invalid request does not start network work")
    }

    private func request(id: Int) -> HTTPRequest {
        .init(id: id, method: "GET", url: "http://127.0.0.1:49152/test", headers: [:], body: nil, timeoutMs: 30_000)
    }
}
