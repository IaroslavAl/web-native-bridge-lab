import Foundation
import XCTest
@testable import TransportPackage

final class URLSessionNetworkClientTests: XCTestCase {
    func testURLSessionTaskStreamsResponseAndBody() throws {
        let configuration = URLSessionNetworkClient.makeConfiguration()
        configuration.protocolClasses = [SuccessfulURLProtocol.self]
        let recorder = NetworkEventRecorder()
        let completed = expectation(description: "URLSession completion")
        let operation = URLSessionNetworkTask(
            request: URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:49152/adapter"))),
            eventHandler: { event in
                recorder.record(event)
                if case .complete = event {
                    completed.fulfill()
                }
            },
            configuration: configuration
        )

        operation.resume()
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(recorder.eventKinds, ["response", "data", "complete"])
        XCTAssertEqual(recorder.responseStatus, 503)
        XCTAssertEqual(recorder.receivedData, Data("unavailable".utf8))
        XCTAssertEqual(recorder.completionCount, 1)
    }

    func testEphemeralConfigurationHasNoAmbientCredentialStores() {
        let configuration = URLSessionNetworkClient.makeConfiguration()

        XCTAssertNil(configuration.httpCookieStorage, "httpCookieStorage")
        XCTAssertFalse(configuration.httpShouldSetCookies, "httpShouldSetCookies")
        XCTAssertNil(configuration.urlCredentialStorage, "urlCredentialStorage")
        XCTAssertNil(configuration.urlCache, "urlCache")
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData, "requestCachePolicy")
    }

    func testRedirectDelegateReturnsNoDestinationRequest() {
        let recorder = NetworkEventRecorder()
        let operation = URLSessionNetworkTask(
            request: URLRequest(url: URL(string: "http://127.0.0.1:49152/start")!),
            eventHandler: { event in recorder.record(event) }
        )
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "http://127.0.0.1:49152/start")!)
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:49152/start")!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "/next"]
        )!
        let destination = URLRequest(url: URL(string: "http://127.0.0.1:49152/next")!)
        var followedRequest: URLRequest? = destination

        operation.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: destination
        ) { request in
            followedRequest = request
        }

        XCTAssertNil(followedRequest, "redirect destination request")
        XCTAssertEqual(recorder.eventKinds, ["redirect"], "redirect delegate event")
        session.invalidateAndCancel()
    }

    func testAuthenticationChallengeIsCancelledWithoutCredential() {
        let recorder = NetworkEventRecorder()
        let operation = URLSessionNetworkTask(
            request: URLRequest(url: URL(string: "http://127.0.0.1:49152/auth")!),
            eventHandler: { event in recorder.record(event) }
        )
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "http://127.0.0.1:49152/auth")!)
        let sender = ChallengeSender()
        let challenge = URLAuthenticationChallenge(
            protectionSpace: URLProtectionSpace(
                host: "127.0.0.1",
                port: 49152,
                protocol: "http",
                realm: "synthetic",
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic
            ),
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: sender
        )
        var disposition: URLSession.AuthChallengeDisposition?
        var credential: URLCredential? = URLCredential(user: "unexpected", password: "unexpected", persistence: .none)

        operation.urlSession(session, task: task, didReceive: challenge) { value, suppliedCredential in
            disposition = value
            credential = suppliedCredential
        }

        XCTAssertEqual(disposition, .cancelAuthenticationChallenge, "authentication disposition")
        XCTAssertNil(credential, "authentication credential")
        XCTAssertEqual(recorder.eventKinds, ["authenticationChallenge"], "authentication delegate event")
        session.invalidateAndCancel()
    }

    func testPublicExecutorInitializerUsesFoundationNetworkClient() async {
        let executor = HTTPExecutor(
            policy: TransportPolicy(allowedOrigin: URL(string: "http://127.0.0.1:8788")!)
        )
        let cancelled = await executor.cancel(id: 1)
        XCTAssertFalse(cancelled, "new public executor active request")
    }
}

private final class NetworkEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NetworkEvent] = []

    var eventKinds: [String] {
        lock.withLock {
            events.map {
                switch $0 {
                case .redirect: "redirect"
                case .authenticationChallenge: "authenticationChallenge"
                case .response: "response"
                case .data: "data"
                case .complete: "complete"
                }
            }
        }
    }

    var responseStatus: Int? {
        lock.withLock {
            events.compactMap { event in
                guard case let .response(status, _, _) = event else { return nil }
                return status
            }.first
        }
    }

    var receivedData: Data {
        lock.withLock {
            events.reduce(into: Data()) { data, event in
                if case let .data(chunk) = event {
                    data.append(chunk)
                }
            }
        }
    }

    var completionCount: Int {
        lock.withLock {
            events.filter {
                if case .complete = $0 { return true }
                return false
            }.count
        }
    }

    func record(_ event: NetworkEvent) {
        lock.withLock { events.append(event) }
    }
}

private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}

private final class SuccessfulURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 503,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("unavailable".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
