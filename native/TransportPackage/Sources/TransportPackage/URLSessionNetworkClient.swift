import Foundation

final class URLSessionNetworkClient: HTTPNetworkClient, @unchecked Sendable {
    func makeTask(
        request: URLRequest,
        eventHandler: @escaping @Sendable (NetworkEvent) -> Void
    ) -> HTTPNetworkTask {
        URLSessionNetworkTask(request: request, eventHandler: eventHandler)
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 31
        configuration.timeoutIntervalForResource = 31
        configuration.waitsForConnectivity = false
        return configuration
    }
}

final class URLSessionNetworkTask: NSObject, HTTPNetworkTask, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let request: URLRequest
    private let eventHandler: @Sendable (NetworkEvent) -> Void
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var started = false
    private var cancelled = false

    init(
        request: URLRequest,
        eventHandler: @escaping @Sendable (NetworkEvent) -> Void,
        configuration: URLSessionConfiguration = URLSessionNetworkClient.makeConfiguration()
    ) {
        self.request = request
        self.eventHandler = eventHandler
        self.configuration = configuration
    }

    func resume() {
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        guard !cancelled else {
            lock.unlock()
            return
        }

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
        let dataTask = session.dataTask(with: request)
        self.session = session
        self.dataTask = dataTask
        lock.unlock()

        dataTask.resume()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let dataTask = self.dataTask
        let session = self.session
        lock.unlock()

        dataTask?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            eventHandler(.complete(.other))
            completionHandler(.cancel)
            return
        }
        let headers = response.allHeaderFields.compactMap { item -> (String, String)? in
            guard let name = item.key as? String else { return nil }
            if let value = item.value as? String {
                return (name, value)
            }
            return (name, String(describing: item.value))
        }
        eventHandler(.response(
            status: response.statusCode,
            headers: headers,
            expectedContentLength: response.expectedContentLength
        ))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        eventHandler(.data(data))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let completionError: NetworkCompletionError?
        if let urlError = error as? URLError, urlError.code == .timedOut {
            completionError = .timedOut
        } else if error != nil {
            completionError = .other
        } else {
            completionError = nil
        }
        eventHandler(.complete(completionError))
        session.finishTasksAndInvalidate()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        eventHandler(.redirect)
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        eventHandler(.authenticationChallenge)
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        eventHandler(.authenticationChallenge)
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
