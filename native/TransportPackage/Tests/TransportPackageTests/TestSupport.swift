import Foundation
@testable import TransportPackage

final class MockNetworkClient: HTTPNetworkClient, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [@Sendable (NetworkEvent) -> Void] = []
    private var storedRequests: [URLRequest] = []
    private var storedTasks: [MockNetworkTask] = []

    var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    var tasks: [MockNetworkTask] {
        lock.withLock { storedTasks }
    }

    func makeTask(
        request: URLRequest,
        eventHandler: @escaping @Sendable (NetworkEvent) -> Void
    ) -> HTTPNetworkTask {
        lock.withLock {
            let task = MockNetworkTask()
            storedRequests.append(request)
            handlers.append(eventHandler)
            storedTasks.append(task)
            return task
        }
    }

    func waitUntilStarted(count: Int) async {
        while lock.withLock({ handlers.count < count || storedTasks.filter(\.isResumed).count < count }) {
            await Task.yield()
        }
    }

    func send(_ event: NetworkEvent, at index: Int) {
        let handler = lock.withLock { handlers[index] }
        handler(event)
    }
}

final class MockNetworkTask: HTTPNetworkTask, @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var cancelled = false

    var isResumed: Bool { lock.withLock { resumed } }
    var isCancelled: Bool { lock.withLock { cancelled } }

    func resume() {
        lock.withLock { resumed = true }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}

extension HTTPResult {
    var failureCode: String? {
        guard case let .failure(failure) = self else { return nil }
        return failure.code
    }

    var responseBody: String? {
        guard case let .response(response) = self else { return nil }
        return response.body
    }

    var responseHeaders: [String: String]? {
        guard case let .response(response) = self else { return nil }
        return response.headers
    }
}
