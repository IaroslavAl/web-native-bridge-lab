import SwiftUI
import WebKit
import TransportPackage

enum BridgeLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class BridgeWebViewModel: ObservableObject {
    @Published private(set) var loadState: BridgeLoadState = .loading
    @Published private(set) var selectedSurface: WebSurface = .demo
    let webView: WKWebView
    private let adapter: WKBridgeAdapter
    private let requestLoader: (WKWebView, URLRequest) -> Void

    init(requestLoader: ((WKWebView, URLRequest) -> Void)? = nil) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let executor = HTTPExecutor(policy: TransportPolicy(allowedOrigin: URL(string: "http://127.0.0.1:8788")!))
        let engine = BridgeEngine(executor: executor)
        adapter = WKBridgeAdapter(engine: engine, policy: .production)
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.requestLoader = requestLoader ?? { webView, request in webView.load(request) }
        webView.navigationDelegate = adapter
        webView.isInspectable = false
        webView.isUserInteractionEnabled = false
        webView.accessibilityIdentifier = "lab.webview"
        adapter.install(on: webView) { [weak self] event in
            self?.handleLoadEvent(event)
        }
        loadCurrentContent()
    }

    func reload() {
        loadCurrentContent()
    }

    func openDiagnostics() {
        selectedSurface = .diagnostics
        loadCurrentContent()
    }

    func openDemo() {
        selectedSurface = .demo
        loadCurrentContent()
    }

    func handleLoadEvent(_ event: WKBridgeLoadEvent) {
        switch event {
        case .started:
            loadState = .loading
            webView.isUserInteractionEnabled = false
        case .finished:
            loadState = .loaded
            webView.isUserInteractionEnabled = true
        case .failed(let failure):
            loadState = .failed(Self.message(for: failure))
            webView.isUserInteractionEnabled = false
        }
    }

    func close() {
        adapter.close()
        webView.stopLoading()
    }

    private func loadCurrentContent() {
        loadState = .loading
        webView.isUserInteractionEnabled = false
        let request = URLRequest(
            url: selectedSurface.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        requestLoader(webView, request)
    }

    private static func message(for failure: WKBridgeLoadFailure) -> String {
        switch failure {
        case .originDenied:
            return "Адрес веб-экрана отклонён приложением."
        case .contentUnavailable:
            return "Не удалось загрузить веб-экран."
        case .navigationFailed:
            return "Веб-экран не загрузился."
        case .processTerminated:
            return "Работа веб-экрана прервана."
        }
    }
}
