import Foundation
import XCTest
@testable import TransportPackage

final class HTTPExecutorTests: XCTestCase {
    func testGETSuccessPreservesOpaqueResponse() async {
        let network = MockNetworkClient()
        let executor = HTTPExecutor(
            policy: TransportPolicy(allowedOrigin: URL(string: "http://127.0.0.1:49152")!),
            networkClient: network
        )
        let request = HTTPRequest(
            id: 7,
            method: "GET",
            url: "http://127.0.0.1:49152/opaque?value=a%20b",
            headers: ["accept": "application/json", "x-lab-tag": "request-7"],
            body: nil,
            timeoutMs: 5_000
        )

        let resultTask = Task { await executor.execute(request) }
        await network.waitUntilStarted(count: 1)
        network.send(.response(
            status: 200,
            headers: [("Content-Type", "application/json; charset=utf-8"), ("X-Lab-Tag", "request-7")],
            expectedContentLength: 18
        ), at: 0)
        network.send(.data(Data("{\"broken\": not-json".utf8)), at: 0)
        network.send(.complete(nil), at: 0)

        let result = await resultTask.value
        XCTAssertEqual(
            result,
            .response(HTTPResponse(
                id: 7,
                status: 200,
                headers: ["content-type": "application/json; charset=utf-8", "x-lab-tag": "request-7"],
                body: "{\"broken\": not-json"
            )),
            "HTTPResult should preserve id, status, allowed headers, and opaque body"
        )
        XCTAssertEqual(network.requests.first?.httpMethod, "GET", "httpMethod")
        XCTAssertEqual(network.requests.first?.url?.absoluteString, request.url, "url")
        XCTAssertEqual(network.requests.first?.value(forHTTPHeaderField: "x-lab-tag"), "request-7", "x-lab-tag")
    }
}
