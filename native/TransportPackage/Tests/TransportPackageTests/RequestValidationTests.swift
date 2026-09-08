import Foundation
import XCTest
@testable import TransportPackage

final class RequestValidationTests: XCTestCase {
    private let origin = URL(string: "http://127.0.0.1:49152")!

    func testPOSTTransportsOpaqueUTF8Body() async {
        let network = MockNetworkClient()
        let executor = HTTPExecutor(policy: TransportPolicy(allowedOrigin: origin), networkClient: network)
        let request = HTTPRequest(
            id: 8,
            method: "POST",
            url: "http://127.0.0.1:49152/echo",
            headers: ["content-type": "text/plain", "accept": "text/plain"],
            body: "opaque é text",
            timeoutMs: 5_000
        )

        let resultTask = Task { await executor.execute(request) }
        await network.waitUntilStarted(count: 1)
        network.send(.response(status: 503, headers: [("Content-Type", "text/plain")], expectedContentLength: 11), at: 0)
        network.send(.data(Data("still opaque".utf8)), at: 0)
        network.send(.complete(nil), at: 0)

        let result = await resultTask.value
        XCTAssertEqual(
            result,
            .response(HTTPResponse(id: 8, status: 503, headers: ["content-type": "text/plain"], body: "still opaque")),
            "HTTP 503 should remain a response"
        )
        XCTAssertEqual(network.requests[0].httpBody, Data("opaque é text".utf8), "httpBody UTF-8 bytes")
        XCTAssertEqual(network.requests[0].value(forHTTPHeaderField: "content-type"), "text/plain", "content-type")
    }

    func testInvalidRequestFieldsPreventNetworkStart() async {
        let valid = HTTPRequest(
            id: 1,
            method: "GET",
            url: "http://127.0.0.1:49152/path",
            headers: ["accept": "application/json"],
            body: nil,
            timeoutMs: 5_000
        )
        let cases: [(String, HTTPRequest)] = [
            ("id minimum", mutate(valid, id: 0)),
            ("id maximum", mutate(valid, id: 2_147_483_648)),
            ("method", mutate(valid, method: "PUT")),
            ("relative url", mutate(valid, url: "/path")),
            ("missing slash path", mutate(valid, url: "http://127.0.0.1:49152")),
            ("userinfo", mutate(valid, url: "http://user@127.0.0.1:49152/path")),
            ("fragment", mutate(valid, url: "http://127.0.0.1:49152/path#")),
            ("backslash", mutate(valid, url: "http://127.0.0.1:49152/path\\bad")),
            ("literal whitespace", mutate(valid, url: "http://127.0.0.1:49152/path bad")),
            ("invalid percent escape", mutate(valid, url: "http://127.0.0.1:49152/path%ZZ")),
            ("encoded control", mutate(valid, url: "http://127.0.0.1:49152/path%0a")),
            ("non ASCII url", mutate(valid, url: "http://127.0.0.1:49152/café")),
            ("url character cap", mutate(valid, url: "http://127.0.0.1:49152/" + String(repeating: "a", count: 8_193))),
            ("mixed case header", mutate(valid, headers: ["Accept": "application/json"])),
            ("forbidden header", mutate(valid, headers: ["authorization": "synthetic"])),
            ("empty header value", mutate(valid, headers: ["x-lab-tag": ""])),
            ("header value cap", mutate(valid, headers: ["x-lab-tag": String(repeating: "a", count: 129)])),
            ("header control", mutate(valid, headers: ["x-lab-tag": "a\rb"])),
            ("accept value", mutate(valid, headers: ["accept": "text/html"])),
            ("GET body", mutate(valid, body: "")),
            ("GET content type", mutate(valid, headers: ["content-type": "text/plain"])),
            ("POST missing body", mutate(valid, method: "POST", headers: ["content-type": "text/plain"])),
            ("POST missing content type", mutate(valid, method: "POST", headers: [:], body: "text")),
            ("POST content type value", mutate(valid, method: "POST", headers: ["content-type": "application/octet-stream"], body: "text")),
            ("timeout minimum", mutate(valid, timeoutMs: 0)),
            ("timeout maximum", mutate(valid, timeoutMs: 30_001))
        ]

        for (name, request) in cases {
            let (result, networkCount) = await executeSettled(request)
            XCTAssertEqual(result.failureCode, "INVALID_REQUEST", "field/case: \(name)")
            XCTAssertEqual(networkCount, 0, "network start for invalid field/case: \(name)")
        }
    }

    func testDeniedOriginsPreventNetworkStart() async {
        let urls = [
            "http://localhost:49152/path",
            "http://127.0.0.1:49153/path",
            "https://127.0.0.1:49152/path",
            "http://127.0.0.1/path",
            "http://2130706433:49152/path",
            "http://127.0.0.1.:49152/path",
            "http://[::1]:49152/path"
        ]

        for url in urls {
            let request = HTTPRequest(id: 1, method: "GET", url: url, headers: [:], body: nil, timeoutMs: 100)
            let (result, networkCount) = await executeSettled(request)
            XCTAssertEqual(result.failureCode, "URL_DENIED", "url: \(url)")
            XCTAssertEqual(networkCount, 0, "network start for denied url: \(url)")
        }
    }

    func testRequestBodyUsesUTF8ByteLimit() async {
        let exactBody = String(repeating: "é", count: 32_768)
        let oversizedBody = exactBody + "é"
        let exact = HTTPRequest(
            id: 1,
            method: "POST",
            url: "http://127.0.0.1:49152/path",
            headers: ["content-type": "text/plain"],
            body: exactBody,
            timeoutMs: 100
        )
        let oversized = mutate(exact, id: 2, body: oversizedBody)

        let exactExecution = await executeSettled(exact)
        XCTAssertEqual(exactExecution.1, 1, "65536-byte body network start")
        XCTAssertNotEqual(exactExecution.0.failureCode, "REQUEST_TOO_LARGE", "65536-byte body")

        let oversizedExecution = await executeSettled(oversized)
        XCTAssertEqual(oversizedExecution.0.failureCode, "REQUEST_TOO_LARGE", "65538-byte body code")
        XCTAssertEqual(oversizedExecution.1, 0, "65538-byte body network start")
    }

    private func executeSettled(_ request: HTTPRequest) async -> (HTTPResult, Int) {
        let network = MockNetworkClient()
        let executor = HTTPExecutor(policy: TransportPolicy(allowedOrigin: origin), networkClient: network)
        let task = Task { await executor.execute(request) }
        try? await Task.sleep(nanoseconds: 5_000_000)
        if !network.requests.isEmpty {
            network.send(.response(status: 204, headers: [], expectedContentLength: 0), at: 0)
            network.send(.complete(nil), at: 0)
        }
        return (await task.value, network.requests.count)
    }

    private func mutate(
        _ request: HTTPRequest,
        id: Int? = nil,
        method: String? = nil,
        url: String? = nil,
        headers: [String: String]? = nil,
        body: String?? = nil,
        timeoutMs: Int? = nil
    ) -> HTTPRequest {
        HTTPRequest(
            id: id ?? request.id,
            method: method ?? request.method,
            url: url ?? request.url,
            headers: headers ?? request.headers,
            body: body ?? request.body,
            timeoutMs: timeoutMs ?? request.timeoutMs
        )
    }
}
