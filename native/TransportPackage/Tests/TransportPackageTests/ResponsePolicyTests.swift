import Foundation
import XCTest
@testable import TransportPackage

final class ResponsePolicyTests: XCTestCase {
    private let origin = URL(string: "http://127.0.0.1:49152")!

    func testRedirectStatusesBecomeTransportFailures() async {
        for status in [301, 302, 303, 307, 308] {
            let (result, network) = await execute(events: [
                .response(status: status, headers: [("Location", "/elsewhere")], expectedContentLength: 0),
                .complete(nil)
            ])
            XCTAssertEqual(result.failureCode, "REDIRECT_DENIED", "redirect status: \(status)")
            XCTAssertTrue(network.tasks[0].isCancelled, "underlying task cancelled for redirect status: \(status)")
        }
    }

    func testRedirectDelegateDenialCancelsUnderlyingTask() async {
        let (result, network) = await execute(events: [.redirect, .complete(.other)])
        XCTAssertEqual(result.failureCode, "REDIRECT_DENIED", "redirect delegate code")
        XCTAssertTrue(network.tasks[0].isCancelled, "redirect delegate task cancellation")
    }

    func testResponseDataCapIsInclusiveAndStreaming() async {
        let exactData = Data(repeating: 0x78, count: 1_048_576)
        let exact = await execute(events: [
            .response(status: 200, headers: [("Content-Type", "text/plain")], expectedContentLength: -1),
            .data(exactData),
            .complete(nil)
        ])
        XCTAssertEqual(exact.0.responseBody?.utf8.count, 1_048_576, "exact response byte cap")
        XCTAssertFalse(exact.1.tasks[0].isCancelled, "exact response byte cap cancellation")

        let over = await execute(events: [
            .response(status: 200, headers: [("Content-Type", "text/plain")], expectedContentLength: -1),
            .data(exactData),
            .data(Data([0x78])),
            .complete(nil)
        ])
        XCTAssertEqual(over.0.failureCode, "RESPONSE_TOO_LARGE", "streamed response cap + 1 code")
        XCTAssertTrue(over.1.tasks[0].isCancelled, "streamed response cap + 1 cancellation")
    }

    func testDeclaredOversizeResponseIsRejectedBeforeBody() async {
        let (result, network) = await execute(events: [
            .response(status: 200, headers: [("Content-Type", "text/plain")], expectedContentLength: 1_048_577)
        ])
        XCTAssertEqual(result.failureCode, "RESPONSE_TOO_LARGE", "declared response length code")
        XCTAssertTrue(network.tasks[0].isCancelled, "declared response length cancellation")
    }

    func testResponseHeadersAreFilteredAndBounded() async {
        let filtered = await execute(events: [
            .response(
                status: 200,
                headers: [
                    ("Content-Type", "text/plain"),
                    ("X-Lab-Tag", "safe"),
                    ("Set-Cookie", "synthetic=1"),
                    ("Authorization", "synthetic"),
                    ("X-Private", "synthetic")
                ],
                expectedContentLength: 2
            ),
            .data(Data("ok".utf8)),
            .complete(nil)
        ])
        XCTAssertEqual(
            filtered.0.responseHeaders,
            ["content-type": "text/plain", "x-lab-tag": "safe"],
            "exposed response header allowlist"
        )

        let overValue = String(repeating: "a", count: 8_192)
        let oversized = await execute(events: [
            .response(status: 200, headers: [("Content-Type", "text/plain"), ("X-Lab-Tag", overValue)], expectedContentLength: 0)
        ])
        XCTAssertEqual(oversized.0.failureCode, "RESPONSE_TOO_LARGE", "combined exposed header byte cap")
        XCTAssertTrue(oversized.1.tasks[0].isCancelled, "oversized exposed headers cancellation")

        let invalid = await execute(events: [
            .response(status: 200, headers: [("Content-Type", "text/plain"), ("X-Lab-Tag", "bad\rvalue")], expectedContentLength: 0)
        ])
        XCTAssertEqual(invalid.0.failureCode, "UNSUPPORTED_RESPONSE", "response header printable ASCII")
        XCTAssertTrue(invalid.1.tasks[0].isCancelled, "invalid exposed response header cancellation")
    }

    func testNonemptyResponseRequiresAllowedTextualMediaType() async {
        for contentType in [nil, "application/octet-stream", "image/png"] as [String?] {
            let headers = contentType.map { [("Content-Type", $0)] } ?? []
            let result = await execute(events: [
                .response(status: 200, headers: headers, expectedContentLength: 1),
                .data(Data([0x78])),
                .complete(nil)
            ])
            XCTAssertEqual(result.0.failureCode, "UNSUPPORTED_RESPONSE", "content-type: \(contentType ?? "missing")")
        }

        let empty = await execute(events: [
            .response(status: 204, headers: [], expectedContentLength: 0),
            .complete(nil)
        ])
        XCTAssertEqual(empty.0, .response(HTTPResponse(id: 1, status: 204, headers: [:], body: "")), "empty response without content-type")
    }

    func testInvalidUTF8IsRejectedWithoutLossyReplacement() async {
        let (result, _) = await execute(events: [
            .response(status: 200, headers: [("Content-Type", "text/plain")], expectedContentLength: 2),
            .data(Data([0xc3, 0x28])),
            .complete(nil)
        ])
        XCTAssertEqual(result.failureCode, "RESPONSE_ENCODING", "strict UTF-8 response decoding")
    }

    func testNetworkAndAuthenticationFailuresStayTransportFailures() async {
        let networkError = await execute(events: [.complete(.other)])
        XCTAssertEqual(networkError.0.failureCode, "NETWORK_ERROR", "generic network completion")

        let systemTimeout = await execute(events: [.complete(.timedOut)])
        XCTAssertEqual(systemTimeout.0.failureCode, "TIMEOUT", "URLSession timeout completion")

        let auth = await execute(events: [.authenticationChallenge, .complete(.other)])
        XCTAssertEqual(auth.0.failureCode, "NETWORK_ERROR", "authentication challenge code")
        XCTAssertTrue(auth.1.tasks[0].isCancelled, "authentication challenge task cancellation")
    }

    private func execute(events: [NetworkEvent]) async -> (HTTPResult, MockNetworkClient) {
        let network = MockNetworkClient()
        let executor = HTTPExecutor(policy: TransportPolicy(allowedOrigin: origin), networkClient: network)
        let request = HTTPRequest(
            id: 1,
            method: "GET",
            url: "http://127.0.0.1:49152/response",
            headers: [:],
            body: nil,
            timeoutMs: 30_000
        )
        let task = Task { await executor.execute(request) }
        await network.waitUntilStarted(count: 1)
        for event in events {
            network.send(event, at: 0)
            await Task.yield()
        }
        return (await task.value, network)
    }
}
