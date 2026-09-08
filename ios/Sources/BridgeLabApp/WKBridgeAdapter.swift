import Foundation
import WebKit

@MainActor
final class WKBridgeAdapter: NSObject {
    static let handlerName = "nativeHTTP"

    private let engine: BridgeEngine
    private let policy: TrustedPagePolicy
    private weak var webView: WKWebView?
    private var proxy: WeakReplyMessageHandler?
    private var committedURL: URL?
    private var documentIsActive = false
    private var lifecycleTask: Task<Void, Never>?
    private var lifecycleID: UInt64 = 0
    private var onLoadFailure: ((String?) -> Void)?

    init(engine: BridgeEngine, policy: TrustedPagePolicy) {
        self.engine = engine
        self.policy = policy
    }

    deinit {
        let engine = engine
        Task {
            await engine.revokeDocument()
        }
    }

    func install(on webView: WKWebView, onLoadFailure: @escaping (String?) -> Void) {
        precondition(self.webView == nil, "WKBridgeAdapter may only be installed once")
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
        guard let webView else { return }
        documentIsActive = false
        committedURL = nil
        lifecycleID &+= 1
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.handlerName,
            contentWorld: .page
        )
        webView.navigationDelegate = nil
        self.webView = nil
        proxy = nil
        chainRevocation()
    }

    private func prepareForAllowedNavigation() {
        documentIsActive = false
        committedURL = nil
        lifecycleID &+= 1
        chainRevocation()
    }

    private func chainRevocation() {
        let prior = lifecycleTask
        let engine = engine
        lifecycleTask = Task {
            await prior?.value
            await engine.revokeDocument()
        }
    }

    private func activateCommittedDocument(_ url: URL?) {
        committedURL = url
        documentIsActive = true
        let currentID = lifecycleID
        let prior = lifecycleTask
        let engine = engine
        lifecycleTask = Task { [weak self] in
            await prior?.value
            guard let self, self.lifecycleID == currentID, self.documentIsActive else { return }
            await engine.activateDocument()
        }
    }

    private func failDocumentLoad(_ message: String) {
        documentIsActive = false
        committedURL = nil
        lifecycleID &+= 1
        chainRevocation()
        onLoadFailure?(message)
    }

    fileprivate func receive(
        _ message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        let securityOrigin = message.frameInfo.securityOrigin
        let frame = BridgeFrameOrigin(
            scheme: securityOrigin.protocol,
            host: securityOrigin.host,
            port: securityOrigin.port,
            isMainFrame: message.frameInfo.isMainFrame
        )
        let trusted = policy.allows(frame: frame, committedURL: committedURL, isActive: documentIsActive)
        let incoming: BridgeIncoming
        if !trusted {
            incoming = .untrusted
        } else if let raw = message.body as? String {
            incoming = .trusted(raw)
        } else {
            incoming = .trustedNonString
        }

        let activation = lifecycleTask
        let engine = engine
        let reply = ReplyOnce(replyHandler)
        Task {
            await activation?.value
            let result = await engine.handle(incoming)
            reply.call(result.webObject, nil)
        }
    }
}

extension WKBridgeAdapter: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let targetIsMainFrame = navigationAction.targetFrame?.isMainFrame
        guard policy.allowsMainNavigation(to: navigationAction.request.url, targetIsMainFrame: targetIsMainFrame) else {
            decisionHandler(.cancel)
            return
        }
        prepareForAllowedNavigation()
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        activateCommittedDocument(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadFailure?(nil)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        failDocumentLoad("Local web content is unavailable")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failDocumentLoad("Local web content failed to load")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failDocumentLoad("Web content process terminated")
    }
}

private final class WeakReplyMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var delegate: WKBridgeAdapter?

    init(delegate: WKBridgeAdapter) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
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
        Task { @MainActor in
            delegate.receive(message, replyHandler: replyHandler)
        }
    }
}

private final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var didReply = false
    private let handler: (Any?, String?) -> Void

    init(_ handler: @escaping (Any?, String?) -> Void) {
        self.handler = handler
    }

    func call(_ value: Any?, _ error: String?) {
        lock.lock()
        guard !didReply else {
            lock.unlock()
            return
        }
        didReply = true
        lock.unlock()
        handler(value, error)
    }
}
