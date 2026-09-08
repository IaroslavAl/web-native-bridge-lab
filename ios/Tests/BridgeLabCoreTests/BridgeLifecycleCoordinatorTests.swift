import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import BridgeLabCore
#else
@testable import BridgeLab
#endif
@testable import TransportPackage

@MainActor
final class BridgeLifecycleCoordinatorTests: XCTestCase {
    func testEngineAdmissionReturnsBeforeHTTPCompletionAndRevocationSettlesReceipt() async {
        let network = LifecycleNetwork()
        let executor = HTTPExecutor(
            policy: .init(allowedOrigin: URL(string: "http://127.0.0.1:8788")!),
            networkClient: network
        )
        let engine = BridgeEngine(executor: executor)
        let session = await engine.activateDocument()
        let admission = await engine.admit(.trusted(
            #"{"v":1,"type":"request","session":"\#(session)","id":1,"method":"GET","url":"http://127.0.0.1:8788/test","headers":{},"body":null,"timeoutMs":30000}"#
        ))
        guard case .running = admission else { return XCTFail("admission must acknowledge a running task") }
        XCTAssertEqual(network.taskCount, 1, "registered task count before completion")
        await engine.revokeDocument()
        let reply = await admission.result()
        XCTAssertEqual(reply, .error(id: 1, code: "CANCELLED", message: "Request was cancelled"))
        XCTAssertTrue(network.task.isCancelled, "underlying task cancelled")
    }

    func testRevocationWaitsForAdmissionReceiptAndPublicationBeforeFreshActivation() async {
        let network = LifecycleNetwork()
        let executor = HTTPExecutor(
            policy: .init(allowedOrigin: URL(string: "http://127.0.0.1:49152")!),
            networkClient: network
        )
        let admissionBegun = expectation(description: "old admission begun, executor hop held")
        let receiptHeld = expectation(description: "old admission registered, receipt held")
        let cancelled = expectation(description: "ordered cancelAll completed")
        let publicationHeld = expectation(description: "old CANCELLED publication held")
        let freshActivated = expectation(description: "fresh activation after old publication")
        let queuedDenied = expectation(description: "queued old invocation denied before admission")
        let executorHopGate = LifecycleGate()
        let admissionGate = LifecycleGate()
        let publicationGate = LifecycleGate()
        defer { executorHopGate.release(); admissionGate.release(); publicationGate.release() }
        var activations = 0
        var replies: [BridgeReply] = []
        let coordinator = BridgeLifecycleCoordinator(
            activate: {
                activations += 1
                if activations == 2 { freshActivated.fulfill() }
            },
            revoke: {
                await executor.cancelAll()
                cancelled.fulfill()
            }
        )
        coordinator.commit()
        coordinator.receive(admit: {
            admissionBegun.fulfill()
            await executorHopGate.wait()
            let submission = await executor.submit(.init(
                id: 1, method: "GET", url: "http://127.0.0.1:49152/test",
                headers: [:], body: nil, timeoutMs: 30_000
            ))
            receiptHeld.fulfill()
            await admissionGate.wait()
            return BridgeAdmission(submission)
        }, publish: { reply in
            replies.append(reply)
            publicationHeld.fulfill()
            await publicationGate.wait()
        })
        await fulfillment(of: [admissionBegun], timeout: 3)
        coordinator.receive(admit: {
            XCTFail("queued old hello must never reach admission")
            return .immediate(.helloAck(session: String(repeating: "a", count: 32)))
        }, publish: { reply in
            XCTAssertEqual(reply, .error(id: nil, code: "ORIGIN_DENIED", message: "Bridge origin denied"))
            queuedDenied.fulfill()
        })
        coordinator.revoke()
        coordinator.commit()
        XCTAssertEqual(network.taskCount, 0, "revocation entered before real executor admission")
        executorHopGate.release()
        await fulfillment(of: [receiptHeld], timeout: 3)
        XCTAssertEqual(network.taskCount, 1, "overlapping admission acknowledged before ordered cancelAll")
        XCTAssertFalse(network.task.isCancelled, "cancel cannot overtake held receipt")
        XCTAssertEqual(activations, 1, "fresh activation fenced before admission acknowledgement")
        admissionGate.release()
        await fulfillment(of: [cancelled, publicationHeld, queuedDenied], timeout: 3)
        XCTAssertTrue(network.task.isCancelled, "real executor cancelled admitted network task")
        XCTAssertEqual(replies, [.error(id: 1, code: "CANCELLED", message: "Request was cancelled")])
        XCTAssertEqual(activations, 1, "drain must include originating reply publication")
        publicationGate.release()
        await fulfillment(of: [freshActivated], timeout: 3)
        XCTAssertEqual(coordinator.pendingPublicationCount, 0, "drained publication records released")
    }
}

@MainActor
private final class LifecycleGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

private final class LifecycleNetwork: HTTPNetworkClient, @unchecked Sendable {
    let task = LifecycleNetworkTask()
    private let lock = NSLock()
    private var count = 0
    var taskCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    func makeTask(request: URLRequest, eventHandler: @escaping @Sendable (NetworkEvent) -> Void) -> HTTPNetworkTask {
        lock.lock(); count += 1; lock.unlock()
        return task
    }
}

private final class LifecycleNetworkTask: HTTPNetworkTask, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func resume() {}
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
