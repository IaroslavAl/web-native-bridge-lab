import Foundation
import WebKit

@MainActor
final class WeakReplyMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var delegate: WKBridgeAdapter?

    init(delegate: WKBridgeAdapter) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        let origin = message.frameInfo.securityOrigin
        forward(body: message.body, frame: BridgeFrameOrigin(
            scheme: origin.protocol, host: origin.host, port: origin.port,
            isMainFrame: message.frameInfo.isMainFrame
        ), replyHandler: replyHandler)
    }

    // Shared synchronous ingress; tests supply provenance tuples, WebKit supplies
    // actual securityOrigin/frameInfo above. Neither path inserts a Task hop.
    func forward(body: Any, frame: BridgeFrameOrigin, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let delegate else {
            replyHandler([
                "v": 1,
                "type": "error",
                "id": NSNull(),
                "code": "ORIGIN_DENIED",
                "message": "Bridge origin denied"
            ], nil)
            return
        }
        delegate.receive(body: body, frame: frame, replyHandler: replyHandler)
    }
}
