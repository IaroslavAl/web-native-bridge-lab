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
    private var activeNavigation: WKNavigation?
    private var committedURL: URL?
    private var documentIsActive = false

    private var onLoadEvent: ((WKBridgeLoadEvent) -> Void)?
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

    func install(on webView: WKWebView, onLoadEvent: @escaping (WKBridgeLoadEvent) -> Void) {
        precondition(self.webView == nil && !didClose, "WKBridgeAdapter may only be installed once")
        self.webView = webView
        self.onLoadEvent = onLoadEvent
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
        activeNavigation = nil
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
        onLoadEvent = nil
        lifecycle.revoke()
    }

    private func prepareForAllowedNavigation() {
        guard !didClose else { return }
        activeNavigation = nil
        documentIsActive = false
        committedURL = nil
        lifecycle.revoke()
        onLoadEvent?(.started)
    }

    private func activateCommittedDocument(_ url: URL?) {
        guard !didClose else { return }
        guard policy.allowsMainNavigation(to: url, targetIsMainFrame: true) else {
            failDocumentLoad(.originDenied)
            return
        }
        committedURL = url
        documentIsActive = true
        lifecycle.commit()
    }

    private func failDocumentLoad(_ failure: WKBridgeLoadFailure) {
        guard !didClose else { return }
        activeNavigation = nil
        documentIsActive = false
        committedURL = nil
        lifecycle.revoke()
        onLoadEvent?(.failed(failure))
    }

    private func isCurrentNavigation(_ navigation: WKNavigation?) -> Bool {
        guard let navigation, let activeNavigation else { return false }
        return navigation === activeNavigation
    }

    func receive(
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

    func navigationResponsePolicy(
        for response: URLResponse,
        isForMainFrame: Bool
    ) -> WKNavigationResponsePolicy {
        guard isForMainFrame, let httpResponse = response as? HTTPURLResponse else {
            return .allow
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            return .cancel
        }
        return .allow
    }

    func navigationDidCommit(url: URL?) {
        activateCommittedDocument(url)
    }

    func provisionalNavigationFailed() {
        failDocumentLoad(.contentUnavailable)
    }

    func navigationFailed() {
        failDocumentLoad(.navigationFailed)
    }

    func webContentProcessTerminated() {
        failDocumentLoad(.processTerminated)
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

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponsePolicy(
            for: navigationResponse.response,
            isForMainFrame: navigationResponse.isForMainFrame
        ))
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !didClose, let navigation else { return }
        activeNavigation = navigation
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard isCurrentNavigation(navigation) else { return }
        navigationDidCommit(url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isCurrentNavigation(navigation), documentIsActive else { return }
        activeNavigation = nil
        onLoadEvent?(.finished)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard isCurrentNavigation(navigation) else { return }
        provisionalNavigationFailed()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isCurrentNavigation(navigation) else { return }
        navigationFailed()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webContentProcessTerminated()
    }
}
