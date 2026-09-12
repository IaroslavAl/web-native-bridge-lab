import Foundation

enum WebSurface: CaseIterable, Equatable {
    case demo
    case diagnostics

    var url: URL {
        switch self {
        case .demo:
            return URL(string: "http://127.0.0.1:8787/")!
        case .diagnostics:
            return URL(string: "http://127.0.0.1:8787/?mode=diagnostics")!
        }
    }
}
