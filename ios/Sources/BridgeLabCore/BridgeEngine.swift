import Foundation
import TransportPackage

public protocol HTTPExecuting: Sendable {
    func execute(_ request: HTTPRequest) async -> HTTPResult
    func cancel(id: Int) async -> Bool
    func cancelAll() async
}

extension HTTPExecutor: HTTPExecuting {}

public enum BridgeIncoming: Sendable, Equatable {
    case trusted(String)
    case trustedNonString
    case untrusted
}

public enum BridgeReply: Sendable, Equatable {
    case helloAck(session: String)
    case response(HTTPResponse)
    case error(id: Int?, code: String, message: String)
    case cancelAck(id: Int, cancelled: Bool)

    public var webObject: [String: Any] {
        switch self {
        case .helloAck(let session):
            return ["v": 1, "type": "helloAck", "session": session]
        case .response(let response):
            return [
                "v": 1,
                "type": "response",
                "id": response.id,
                "status": response.status,
                "headers": response.headers,
                "body": response.body
            ]
        case .error(let id, let code, let message):
            return [
                "v": 1,
                "type": "error",
                "id": id ?? NSNull(),
                "code": code,
                "message": String(message.prefix(256))
            ]
        case .cancelAck(let id, let cancelled):
            return ["v": 1, "type": "cancelAck", "id": id, "cancelled": cancelled]
        }
    }
}

public actor BridgeEngine {
    public static let maximumMessageBytes = 131_072

    private let executor: any HTTPExecuting
    private let sessionGenerator: @Sendable () -> String
    private var isActive = false
    private var session: String?
    private var highWaterMark = 0

    public init(
        executor: any HTTPExecuting,
        sessionGenerator: @escaping @Sendable () -> String = {
            UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
    ) {
        self.executor = executor
        self.sessionGenerator = sessionGenerator
    }

    @discardableResult
    public func activateDocument() -> String {
        if isActive, let session {
            return session
        }
        let generated = sessionGenerator()
        precondition(Self.isSession(generated), "sessionGenerator must return 32 lowercase hexadecimal characters")
        isActive = true
        session = generated
        highWaterMark = 0
        return generated
    }

    public func revokeDocument() async {
        isActive = false
        session = nil
        highWaterMark = 0
        await executor.cancelAll()
    }

    public func handle(_ incoming: BridgeIncoming) async -> BridgeReply {
        guard isActive else {
            return originDenied(id: nil)
        }
        switch incoming {
        case .untrusted:
            return originDenied(id: nil)
        case .trustedNonString:
            return invalid(id: nil)
        case .trusted(let raw):
            guard raw.utf8.count <= Self.maximumMessageBytes else {
                return .error(id: nil, code: "MESSAGE_TOO_LARGE", message: "Bridge message is too large")
            }
            return await handleTrusted(raw)
        }
    }

    private func handleTrusted(_ raw: String) async -> BridgeReply {
        guard
            let data = raw.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: data),
            let object = value as? [String: Any]
        else {
            return invalid(id: nil)
        }

        guard let version = Self.integer(object["v"]), version == 1 else {
            return .error(id: Self.recoverID(object), code: "UNSUPPORTED_VERSION", message: "Unsupported bridge version")
        }
        guard let type = object["type"] as? String else {
            return invalid(id: Self.recoverID(object))
        }

        switch type {
        case "hello":
            guard Set(object.keys) == ["v", "type"], let session else {
                return invalid(id: nil)
            }
            return .helloAck(session: session)
        case "request":
            return await handleRequest(object)
        case "cancel":
            return await handleCancel(object)
        default:
            return invalid(id: Self.recoverID(object))
        }
    }

    private func handleRequest(_ object: [String: Any]) async -> BridgeReply {
        let expected: Set<String> = ["v", "type", "session", "id", "method", "url", "headers", "body", "timeoutMs"]
        let recoveredID = Self.recoverID(object)
        guard Set(object.keys) == expected else {
            return invalid(id: recoveredID)
        }
        guard
            let suppliedSession = object["session"] as? String,
            Self.isSession(suppliedSession),
            let id = Self.integer(object["id"]),
            (1...2_147_483_647).contains(id),
            let method = object["method"] as? String,
            let url = object["url"] as? String,
            let timeoutMs = Self.integer(object["timeoutMs"]),
            let headers = Self.stringDictionary(object["headers"]),
            let body = Self.optionalString(object["body"])
        else {
            return invalid(id: recoveredID)
        }
        guard suppliedSession == session else {
            return originDenied(id: id)
        }
        guard id > highWaterMark else {
            return invalid(id: id)
        }
        highWaterMark = id

        let request = HTTPRequest(
            id: id,
            method: method,
            url: url,
            headers: headers,
            body: body,
            timeoutMs: timeoutMs
        )
        switch await executor.execute(request) {
        case .response(let response):
            return .response(response)
        case .failure(let failure):
            return .error(id: failure.id, code: failure.code, message: failure.message)
        }
    }

    private func handleCancel(_ object: [String: Any]) async -> BridgeReply {
        let expected: Set<String> = ["v", "type", "session", "id"]
        let recoveredID = Self.recoverID(object)
        guard Set(object.keys) == expected else {
            return invalid(id: recoveredID)
        }
        guard
            let suppliedSession = object["session"] as? String,
            Self.isSession(suppliedSession),
            let id = Self.integer(object["id"]),
            (1...2_147_483_647).contains(id)
        else {
            return invalid(id: recoveredID)
        }
        guard suppliedSession == session else {
            return originDenied(id: id)
        }
        return .cancelAck(id: id, cancelled: await executor.cancel(id: id))
    }

    private func invalid(id: Int?) -> BridgeReply {
        .error(id: id, code: "INVALID_REQUEST", message: "Invalid bridge request")
    }

    private func originDenied(id: Int?) -> BridgeReply {
        .error(id: id, code: "ORIGIN_DENIED", message: "Bridge origin denied")
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, String(cString: number.objCType) != "c" else {
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double, double >= Double(Int.min), double <= Double(Int.max) else {
            return nil
        }
        return Int(double)
    }

    private static func recoverID(_ object: [String: Any]) -> Int? {
        guard let id = integer(object["id"]), (1...2_147_483_647).contains(id) else {
            return nil
        }
        return id
    }

    private static func stringDictionary(_ value: Any?) -> [String: String]? {
        guard let object = value as? [String: Any] else { return nil }
        var result: [String: String] = [:]
        for (key, value) in object {
            guard let string = value as? String else { return nil }
            result[key] = string
        }
        return result
    }

    private static func optionalString(_ value: Any?) -> String?? {
        if value is NSNull { return .some(nil) }
        guard let string = value as? String else { return nil }
        return .some(.some(string))
    }

    private static func isSession(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}
