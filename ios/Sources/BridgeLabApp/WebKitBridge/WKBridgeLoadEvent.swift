enum WKBridgeLoadFailure: Equatable {
    case originDenied
    case contentUnavailable
    case navigationFailed
    case processTerminated
}

enum WKBridgeLoadEvent: Equatable {
    case started
    case finished
    case failed(WKBridgeLoadFailure)
}
