import Foundation

public struct HTTPRequest: Sendable, Equatable {
    public let id: Int
    public let method: String
    public let url: String
    public let headers: [String: String]
    public let body: String?
    public let timeoutMs: Int

    public init(
        id: Int,
        method: String,
        url: String,
        headers: [String: String],
        body: String?,
        timeoutMs: Int
    ) {
        self.id = id
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeoutMs = timeoutMs
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public let id: Int
    public let status: Int
    public let headers: [String: String]
    public let body: String

    public init(id: Int, status: Int, headers: [String: String], body: String) {
        self.id = id
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public struct TransportFailure: Sendable, Equatable {
    public let id: Int
    public let code: String
    public let message: String

    public init(id: Int, code: String, message: String) {
        self.id = id
        self.code = code
        self.message = message
    }
}

public enum HTTPResult: Sendable, Equatable {
    case response(HTTPResponse)
    case failure(TransportFailure)
}

/// A short admission acknowledgement, not a wait for network completion.
public enum HTTPSubmission: Sendable {
    case immediate(HTTPResult)
    case running(HTTPExecution)
}

/// Owns one immutable terminal value. The executor retains only active receipts;
/// completed values live only as long as their callers retain the receipt.
public final class HTTPExecution: @unchecked Sendable {
    public let id: UUID
    private let lock = NSLock()
    private var selected: HTTPResult?
    private var waiters: [CheckedContinuation<HTTPResult, Never>] = []

    fileprivate init(id: UUID) {
        self.id = id
    }

    public func result() async -> HTTPResult {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let selected {
                lock.unlock()
                continuation.resume(returning: selected)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    // Called synchronously in the executor's terminal-selection actor segment.
    fileprivate func resolve(_ result: HTTPResult) {
        lock.lock()
        precondition(selected == nil, "HTTP execution selected twice")
        selected = result
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in pending { waiter.resume(returning: result) }
    }
}

public struct TransportPolicy: Sendable {
    public let allowedOrigin: URL

    public init(allowedOrigin: URL) {
        self.allowedOrigin = allowedOrigin
    }
}

enum NetworkCompletionError: Sendable {
    case timedOut
    case responseTooLarge
    case other
}

enum NetworkEvent: Sendable {
    case response(status: Int, headers: [(String, String)], expectedContentLength: Int64)
    case data(Data)
    case redirect
    case authenticationChallenge
    case complete(NetworkCompletionError?)
}

protocol HTTPNetworkTask: AnyObject, Sendable {
    func resume()
    func cancel()
}

protocol HTTPNetworkClient: Sendable {
    func makeTask(
        request: URLRequest,
        eventHandler: @escaping @Sendable (NetworkEvent) -> Void
    ) -> HTTPNetworkTask
}

protocol DeadlineToken: AnyObject, Sendable {
    func cancel()
}

protocol DeadlineScheduler: Sendable {
    func schedule(
        afterMilliseconds milliseconds: Int,
        action: @escaping @Sendable () async -> Void
    ) -> DeadlineToken
}

private struct RealDeadlineScheduler: DeadlineScheduler {
    func schedule(
        afterMilliseconds milliseconds: Int,
        action: @escaping @Sendable () async -> Void
    ) -> DeadlineToken {
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await action()
        }
        return TaskDeadlineToken(task: task)
    }
}

private final class TaskDeadlineToken: DeadlineToken, @unchecked Sendable {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}

final class NetworkEventRelay: @unchecked Sendable {
    let stream: AsyncStream<NetworkEvent>
    private let continuation: AsyncStream<NetworkEvent>.Continuation
    private let lock = NSLock()
    private var receivedBytes = 0
    private var closed = false
    private var overflowed = false
    private weak var task: HTTPNetworkTask?

    init() {
        var capturedContinuation: AsyncStream<NetworkEvent>.Continuation?
        stream = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
    }

    func attach(task: HTTPNetworkTask) {
        lock.lock()
        self.task = task
        let mustCancel = overflowed
        lock.unlock()
        if mustCancel { task.cancel() }
    }

    func send(_ event: NetworkEvent) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        if case let .data(data) = event {
            // Account on the producer, BEFORE retaining Data in AsyncStream.
            // This is cumulative, not reset when a consumer drains the queue:
            // queued plus consumed payload can never exceed the response cap.
            guard !data.isEmpty else { lock.unlock(); return }
            guard data.count <= 1_048_576 - receivedBytes else {
                closed = true
                overflowed = true
                continuation.yield(.complete(.responseTooLarge))
                continuation.finish()
                let task = self.task
                lock.unlock()
                task?.cancel()
                return
            }
            receivedBytes += data.count
        }
        continuation.yield(event)
        if case .complete = event {
            closed = true
            continuation.finish()
        }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        closed = true
        continuation.finish()
        lock.unlock()
    }
}

public actor HTTPExecutor {
    private struct ActiveRequest {
        let executionID: UUID
        let task: HTTPNetworkTask
        let execution: HTTPExecution
        var status: Int?
        var headers: [(String, String)] = []
        var data = Data()
        var deadline: DeadlineToken?
        let eventRelay: NetworkEventRelay
        var eventConsumer: Task<Void, Never>?
    }

    private let policy: TransportPolicy
    private let networkClient: HTTPNetworkClient
    private let deadlineScheduler: DeadlineScheduler
    private var active: [Int: ActiveRequest] = [:]

    public init(policy: TransportPolicy) {
        self.policy = policy
        self.networkClient = URLSessionNetworkClient()
        self.deadlineScheduler = RealDeadlineScheduler()
    }

    init(
        policy: TransportPolicy,
        networkClient: HTTPNetworkClient,
        deadlineScheduler: DeadlineScheduler = RealDeadlineScheduler()
    ) {
        self.policy = policy
        self.networkClient = networkClient
        self.deadlineScheduler = deadlineScheduler
    }

    public func execute(_ request: HTTPRequest) async -> HTTPResult {
        switch submit(request) {
        case .immediate(let result): return result
        case .running(let execution): return await execution.result()
        }
    }

    /// Returns only after validation and active task/deadline registration.
    /// This actor segment never awaits capacity or the HTTP lifetime.
    public func submit(_ request: HTTPRequest) -> HTTPSubmission {
        let url: URL
        switch validate(request) {
        case let .accepted(validatedURL):
            url = validatedURL
        case let .rejected(code, message):
            return .immediate(failure(id: request.id, code: code, message: message))
        }
        guard active[request.id] == nil else {
            return .immediate(failure(id: request.id, code: "INVALID_REQUEST", message: "Request id is already active"))
        }
        guard active.count < 8 else {
            return .immediate(failure(id: request.id, code: "BUSY", message: "Native request capacity is full"))
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body.map { Data($0.utf8) }
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let executionID = UUID()
        let execution = HTTPExecution(id: executionID)
        let eventRelay = NetworkEventRelay()
        let task = networkClient.makeTask(request: urlRequest) { event in
            eventRelay.send(event)
        }
        eventRelay.attach(task: task)
        active[request.id] = ActiveRequest(
            executionID: executionID,
            task: task,
            execution: execution,
            eventRelay: eventRelay
        )
        let eventConsumer = Task { [weak self] in
            for await event in eventRelay.stream {
                await self?.receive(event, id: request.id, executionID: executionID)
            }
        }
        active[request.id]?.eventConsumer = eventConsumer
        let deadline = deadlineScheduler.schedule(afterMilliseconds: request.timeoutMs) { [weak self] in
            await self?.deadlineFired(id: request.id, executionID: executionID)
        }
        active[request.id]?.deadline = deadline
        task.resume()
        return .running(execution)
    }

    public func cancel(id: Int) async -> Bool {
        guard active[id] != nil else { return false }
        finishFailure(id: id, code: "CANCELLED", message: "Request was cancelled", cancel: true)
        return true
    }

    public func cancelAll() async {
        for id in Array(active.keys) {
            finishFailure(id: id, code: "CANCELLED", message: "Request was cancelled", cancel: true)
        }
    }

    private func deadlineFired(id: Int, executionID: UUID) {
        guard active[id]?.executionID == executionID else { return }
        finishFailure(id: id, code: "TIMEOUT", message: "Native request deadline exceeded", cancel: true)
    }

    private func receive(_ event: NetworkEvent, id: Int, executionID: UUID) {
        guard var state = active[id], state.executionID == executionID else { return }

        switch event {
        case let .response(status, headers, expectedContentLength):
            if [301, 302, 303, 307, 308].contains(status) {
                finishFailure(id: id, code: "REDIRECT_DENIED", message: "Redirects are not allowed", cancel: true)
                return
            }
            guard (100...599).contains(status) else {
                finishFailure(id: id, code: "NETWORK_ERROR", message: "Network response is invalid", cancel: true)
                return
            }
            switch validateResponseHeaders(headers) {
            case let .success(filtered):
                state.headers = filtered.map { ($0.key, $0.value) }
            case let .failure(responseFailure):
                finishFailure(
                    id: id,
                    code: responseFailure.code,
                    message: responseFailure.message,
                    cancel: true
                )
                return
            }
            if expectedContentLength > 1_048_576 {
                finishFailure(id: id, code: "RESPONSE_TOO_LARGE", message: "Response exceeds byte limit", cancel: true)
                return
            }
            state.status = status
            active[id] = state
        case let .data(data):
            guard data.count <= 1_048_576 - state.data.count else {
                finishFailure(id: id, code: "RESPONSE_TOO_LARGE", message: "Response exceeds byte limit", cancel: true)
                return
            }
            state.data.append(data)
            active[id] = state
        case .redirect:
            finishFailure(id: id, code: "REDIRECT_DENIED", message: "Redirects are not allowed", cancel: true)
        case .authenticationChallenge:
            finishFailure(id: id, code: "NETWORK_ERROR", message: "Authentication is not supported", cancel: true)
        case let .complete(error):
            if case .responseTooLarge? = error {
                finishFailure(id: id, code: "RESPONSE_TOO_LARGE", message: "Response exceeds byte limit", cancel: true)
                return
            }
            if case .timedOut? = error {
                finishFailure(id: id, code: "TIMEOUT", message: "Native request deadline exceeded", cancel: false)
                return
            }
            guard error == nil, let status = state.status else {
                finishFailure(id: id, code: "NETWORK_ERROR", message: "Network request failed", cancel: false)
                return
            }
            let headers = filteredHeaders(state.headers)
            if !state.data.isEmpty, !hasAllowedMediaType(headers["content-type"]) {
                finishFailure(id: id, code: "UNSUPPORTED_RESPONSE", message: "Response media type is unsupported", cancel: false)
                return
            }
            guard let body = String(data: state.data, encoding: .utf8) else {
                finishFailure(id: id, code: "RESPONSE_ENCODING", message: "Response is not valid UTF-8", cancel: false)
                return
            }
            active.removeValue(forKey: id)
            state.eventRelay.finish()
            state.eventConsumer?.cancel()
            state.deadline?.cancel()
            state.execution.resolve(.response(HTTPResponse(
                id: id,
                status: status,
                headers: headers,
                body: body
            )))
        }
    }

    private func finishFailure(id: Int, code: String, message: String, cancel: Bool) {
        guard let state = active.removeValue(forKey: id) else { return }
        state.eventRelay.finish()
        state.eventConsumer?.cancel()
        state.deadline?.cancel()
        if cancel { state.task.cancel() }
        state.execution.resolve(failure(id: id, code: code, message: message))
    }

    private func failure(id: Int, code: String, message: String) -> HTTPResult {
        .failure(TransportFailure(id: id, code: code, message: message))
    }

    private func filteredHeaders(_ headers: [(String, String)]) -> [String: String] {
        headers.reduce(into: [:]) { result, item in
            let name = item.0.lowercased()
            if name == "content-type" || name == "x-lab-tag" {
                result[name] = item.1
            }
        }
    }

    private struct ResponseFailure: Error {
        let code: String
        let message: String
    }

    private func validateResponseHeaders(
        _ headers: [(String, String)]
    ) -> Result<[String: String], ResponseFailure> {
        var exposed: [String: String] = [:]
        for (rawName, value) in headers {
            let name = rawName.lowercased()
            guard name == "content-type" || name == "x-lab-tag" else { continue }
            let bytes = Array(value.utf8)
            guard bytes.allSatisfy({ (0x20...0x7e).contains($0) }) else {
                return .failure(ResponseFailure(
                    code: "UNSUPPORTED_RESPONSE",
                    message: "Response headers are invalid"
                ))
            }
            if let existing = exposed[name] {
                exposed[name] = existing + ", " + value
            } else {
                exposed[name] = value
            }
        }

        let byteCount = exposed.reduce(into: 0) { count, item in
            count += item.key.utf8.count + item.value.utf8.count
        }
        guard byteCount <= 8_192 else {
            return .failure(ResponseFailure(
                code: "RESPONSE_TOO_LARGE",
                message: "Response headers exceed byte limit"
            ))
        }
        return .success(exposed)
    }

    private func hasAllowedMediaType(_ contentType: String?) -> Bool {
        guard let contentType else { return false }
        let mediaType = contentType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return mediaType == "application/json" || mediaType == "text/plain"
    }

    private enum RequestValidation {
        case accepted(URL)
        case rejected(code: String, message: String)
    }

    private func validate(_ request: HTTPRequest) -> RequestValidation {
        guard (1...2_147_483_647).contains(request.id) else {
            return .rejected(code: "INVALID_REQUEST", message: "Request id is invalid")
        }
        guard request.method == "GET" || request.method == "POST" else {
            return .rejected(code: "INVALID_REQUEST", message: "Request method is invalid")
        }
        guard (1...30_000).contains(request.timeoutMs) else {
            return .rejected(code: "INVALID_REQUEST", message: "Request timeout is invalid")
        }

        switch validateURL(request.url) {
        case let .accepted(url):
            guard validateHeaders(request.headers, method: request.method) else {
                return .rejected(code: "INVALID_REQUEST", message: "Request headers are invalid")
            }
            if request.method == "GET" {
                guard request.body == nil else {
                    return .rejected(code: "INVALID_REQUEST", message: "GET body is invalid")
                }
            } else {
                guard request.body != nil, request.headers["content-type"] != nil else {
                    return .rejected(code: "INVALID_REQUEST", message: "POST body is invalid")
                }
            }
            if let body = request.body, body.utf8.count > 65_536 {
                return .rejected(code: "REQUEST_TOO_LARGE", message: "Request body exceeds byte limit")
            }
            return .accepted(url)
        case let .rejected(code, message):
            return .rejected(code: code, message: message)
        }
    }

    private func validateURL(_ value: String) -> RequestValidation {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 8_192, bytes.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            return .rejected(code: "INVALID_REQUEST", message: "Request URL is invalid")
        }
        guard !value.contains("\\"), !value.contains("#"), validPercentEscapes(bytes) else {
            return .rejected(code: "INVALID_REQUEST", message: "Request URL is invalid")
        }
        guard
            let components = URLComponents(string: value),
            let scheme = components.scheme,
            let host = components.host,
            components.user == nil,
            components.password == nil,
            components.path.hasPrefix("/"),
            !components.path.isEmpty,
            let url = components.url
        else {
            return .rejected(code: "INVALID_REQUEST", message: "Request URL is invalid")
        }

        let allowed = URLComponents(url: policy.allowedOrigin, resolvingAgainstBaseURL: false)
        guard
            let allowedScheme = allowed?.scheme,
            let allowedHost = allowed?.host,
            let allowedPort = allowed?.port,
            scheme == allowedScheme,
            host == allowedHost,
            components.port == allowedPort,
            literalAuthority(in: value) == "\(allowedHost):\(allowedPort)",
            value.hasPrefix("\(allowedScheme)://")
        else {
            return .rejected(code: "URL_DENIED", message: "Request URL origin is not allowed")
        }
        return .accepted(url)
    }

    private func validateHeaders(_ headers: [String: String], method: String) -> Bool {
        let allowedNames: Set<String> = ["accept", "content-type", "x-lab-tag"]
        guard headers.count <= allowedNames.count else { return false }

        for (name, value) in headers {
            guard name == name.lowercased(), allowedNames.contains(name) else { return false }
            let bytes = Array(value.utf8)
            guard (1...128).contains(bytes.count), bytes.allSatisfy({ (0x20...0x7e).contains($0) }) else {
                return false
            }
        }
        if let accept = headers["accept"], !["application/json", "text/plain", "*/*"].contains(accept) {
            return false
        }
        if let contentType = headers["content-type"], !["application/json", "text/plain"].contains(contentType) {
            return false
        }
        return method != "GET" || headers["content-type"] == nil
    }

    private func validPercentEscapes(_ bytes: [UInt8]) -> Bool {
        var index = 0
        while index < bytes.count {
            guard bytes[index] == 0x25 else {
                index += 1
                continue
            }
            guard index + 2 < bytes.count,
                  let high = hexValue(bytes[index + 1]),
                  let low = hexValue(bytes[index + 2]) else {
                return false
            }
            let decoded = high * 16 + low
            guard decoded >= 0x20, decoded != 0x7f else { return false }
            index += 3
        }
        return true
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }

    private func literalAuthority(in value: String) -> String? {
        guard let schemeRange = value.range(of: "://") else { return nil }
        let start = schemeRange.upperBound
        let end = value[start...].firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? value.endIndex
        return String(value[start..<end])
    }
}
