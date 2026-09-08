import Foundation

public struct BridgeFrameOrigin: Sendable, Equatable {
    public let scheme: String
    public let host: String
    public let port: Int
    public let isMainFrame: Bool

    public init(scheme: String, host: String, port: Int, isMainFrame: Bool) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.isMainFrame = isMainFrame
    }
}

public struct TrustedPagePolicy: Sendable, Equatable {
    public static let production = TrustedPagePolicy(scheme: "http", host: "127.0.0.1", port: 8787)

    public let scheme: String
    public let host: String
    public let port: Int

    public init(scheme: String, host: String, port: Int) {
        self.scheme = scheme
        self.host = host
        self.port = port
    }

    public func allows(frame: BridgeFrameOrigin, committedURL: URL?, isActive: Bool) -> Bool {
        guard isActive, frame.isMainFrame else { return false }
        guard frame.scheme == scheme, frame.host == host, frame.port == port else { return false }
        return allowsOrigin(of: committedURL)
    }

    public func allowsMainNavigation(to url: URL?, targetIsMainFrame: Bool?) -> Bool {
        guard targetIsMainFrame == true else { return false }
        return allowsOrigin(of: url)
    }

    private func allowsOrigin(of url: URL?) -> Bool {
        guard
            let url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == scheme,
            components.host == host,
            components.port == port,
            components.user == nil,
            components.password == nil
        else {
            return false
        }
        return true
    }
}
