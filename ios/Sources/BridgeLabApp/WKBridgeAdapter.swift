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
    private var didClose = false

    init(engine: BridgeEngine, policy: TrustedPagePolicy) {
        self.engine = engine
        self.policy = policy
    }

    deinit {
        let retainedWebView = webView
        if retainedWebView != nil {
            Task { @MainActor in
                retainedWebView?.configuration.userContentController.removeScriptMessageHandler(
                    forName: "nativeHTTP",
                    contentWorld: .page
                )
            }
        }
        guard !didClose else { return }
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
        guard !didClose else { return }
        didClose = true
        documentIsActive = false
        committedURL = nil
        lifecycleID &+= 1
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
        chainRevocation()
    }

    private func prepareForAllowedNavigation() {
        guard !didClose else { return }
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
        guard !didClose else { return }
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
        guard !didClose else { return }
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

        receive(incoming, replyHandler: replyHandler)
    }

    func receive(
        _ incoming: BridgeIncoming,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        let invocationLifecycleID = lifecycleID
        let activation = lifecycleTask
        let engine = engine
        let reply = ReplyOnce(replyHandler)
        Task { [weak self] in
            await activation?.value
            guard self?.isCurrentInvocation(invocationLifecycleID) == true else {
                reply.call(Self.originDeniedReply, nil)
                return
            }
            let result = await engine.handle(incoming)
            guard self?.isCurrentInvocation(invocationLifecycleID) == true else {
                reply.call(Self.replyForRetiredInvocation(result), nil)
                return
            }
            reply.call(result.webObject, nil)
        }
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

    private func isCurrentInvocation(_ invocationLifecycleID: UInt64) -> Bool {
        !didClose && documentIsActive && lifecycleID == invocationLifecycleID
    }

    private static func replyForRetiredInvocation(_ result: BridgeReply) -> [String: Any] {
        if case let .error(id, code, _) = result, id != nil, code == "CANCELLED" {
            return result.webObject
        }
        if case let .response(response) = result {
            return BridgeReply.error(
                id: response.id,
                code: "CANCELLED",
                message: "Request was cancelled"
            ).webObject
        }
        return originDeniedReply
    }

    private static let originDeniedReply = BridgeReply.error(
        id: nil,
        code: "ORIGIN_DENIED",
        message: "Bridge origin denied"
    ).webObject
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

final class ReplyOnce: @unchecked Sendable {
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
