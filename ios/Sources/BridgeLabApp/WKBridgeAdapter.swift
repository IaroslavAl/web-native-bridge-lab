import Foundation
import WebKit

@MainActor
final class WKBridgeAdapter: NSObject {
    static let handlerName = "nativeHTTP"

    private let engine: BridgeEngine
    private let lifecycle: BridgeLifecycleCoordinator
    private let beforePublication: @MainActor (BridgeReply) async -> Void
    private let policy: TrustedPagePolicy
    private weak var webView: WKWebView?
    private var proxy: WeakReplyMessageHandler?
    private var committedURL: URL?
    private var documentIsActive = false

    private var onLoadFailure: ((String?) -> Void)?
    private var didClose = false

    init(
        engine: BridgeEngine,
        policy: TrustedPagePolicy,
        beforePublication: @escaping @MainActor (BridgeReply) async -> Void = { _ in }
    ) {
        self.engine = engine
        self.policy = policy
        self.beforePublication = beforePublication
        self.lifecycle = BridgeLifecycleCoordinator(
            activate: { _ = await engine.activateDocument() },
            revoke: { await engine.revokeDocument() }
        )
    }

    isolated deinit {
        // Fence before queued ingress can run; only the coordinator survives drain.
        close()
    }

    func install(on webView: WKWebView, onLoadFailure: @escaping (String?) -> Void) {
        precondition(self.webView == nil && !didClose, "WKBridgeAdapter may only be installed once")
        self.webView = webView
        self.onLoadFailure = onLoadFailure
        let proxy = WeakReplyMessageHandler(delegate: self)
        self.proxy = proxy
        webView.configuration.userContentController.addScriptMessageHandler(
            proxy,
            contentWorld: .page,
            name: Self.handlerName
        )
    }

    func close() {
        guard !didClose else { return }
        didClose = true
        documentIsActive = false
        committedURL = nil
        if let webView {
            webView.configuration.userContentController.removeScriptMessageHandler(
                forName: Self.handlerName,
                contentWorld: .page
            )
            if webView.navigationDelegate === self {
                webView.navigationDelegate = nil
            }
        }
        self.webView = nil
        proxy = nil
        onLoadFailure = nil
        lifecycle.revoke()
    }

    private func prepareForAllowedNavigation() {
        guard !didClose else { return }
        documentIsActive = false
        committedURL = nil
        lifecycle.revoke()
    }

    private func activateCommittedDocument(_ url: URL?) {
        guard !didClose else { return }
        guard policy.allowsMainNavigation(to: url, targetIsMainFrame: true) else {
            failDocumentLoad("Bridge origin denied")
            return
        }
        committedURL = url
        documentIsActive = true
        lifecycle.commit()
    }

    private func failDocumentLoad(_ message: String) {
        guard !didClose else { return }
        documentIsActive = false
        committedURL = nil
        lifecycle.revoke()
        onLoadFailure?(message)
    }

    fileprivate func receive(
        body: Any,
        frame: BridgeFrameOrigin,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        let trusted = policy.allows(frame: frame, committedURL: committedURL, isActive: documentIsActive)
        let incoming: BridgeIncoming
        if !trusted {
            incoming = .untrusted
        } else if let raw = body as? String {
            incoming = .trusted(raw)
        } else {
            incoming = .trustedNonString
        }

        receive(incoming, replyHandler: replyHandler)
    }

    func receive(
        _ incoming: BridgeIncoming,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        let engine = engine
        let reply = ReplyOnce(replyHandler)
        let beforePublication = beforePublication
        // Captures generation synchronously, including calls through WebKit's proxy.
        lifecycle.receive(admit: { await engine.admit(incoming) }, publish: { result in
            await beforePublication(result)
            reply.call(result.webObject, nil)
        })
    }

    func navigationPolicy(for url: URL?, targetIsMainFrame: Bool?) -> WKNavigationActionPolicy {
        guard !didClose, policy.allowsMainNavigation(to: url, targetIsMainFrame: targetIsMainFrame) else {
            return .cancel
        }
        prepareForAllowedNavigation()
        return .allow
    }

    func navigationDidCommit(url: URL?) {
        activateCommittedDocument(url)
    }

    func provisionalNavigationFailed() {
        failDocumentLoad("Local web content is unavailable")
    }

    func navigationFailed() {
        failDocumentLoad("Local web content failed to load")
    }

    func webContentProcessTerminated() {
        failDocumentLoad("Web content process terminated")
    }

}

extension WKBridgeAdapter: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let targetIsMainFrame = navigationAction.targetFrame?.isMainFrame
        decisionHandler(navigationPolicy(for: navigationAction.request.url, targetIsMainFrame: targetIsMainFrame))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        navigationDidCommit(url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadFailure?(nil)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        provisionalNavigationFailed()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webContentProcessTerminated()
    }
}

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

@MainActor
final class ReplyOnce {
    private var handler: ((Any?, String?) -> Void)?

    init(_ handler: @escaping (Any?, String?) -> Void) {
        self.handler = handler
    }

    func call(_ value: Any?, _ error: String?) {
        guard let handler else { return }
        self.handler = nil
        handler(value, error)
    }
}
