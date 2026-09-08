import SwiftUI
import WebKit
import TransportPackage

struct BridgeScreen: View {
    @StateObject private var model = BridgeWebViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Web–Native Bridge Lab")
                    .font(.headline)
                Spacer()
                Button("Reload") {
                    model.reload()
                }
                .accessibilityIdentifier("lab.reload")
            }
            .padding()

            if let loadError = model.loadError {
                Text(loadError)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("lab.loadError")
                    .padding(.horizontal)
            }

            WebViewContainer(webView: model.webView)
                .accessibilityIdentifier("lab.webview")
        }
        .onDisappear {
            model.close()
        }
    }
}

@MainActor
final class BridgeWebViewModel: ObservableObject {
    static let webURL = URL(string: "http://127.0.0.1:8787/")!

    @Published private(set) var loadError: String?
    let webView: WKWebView
    private let adapter: WKBridgeAdapter

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let executor = HTTPExecutor(policy: TransportPolicy(allowedOrigin: URL(string: "http://127.0.0.1:8788")!))
        let engine = BridgeEngine(executor: executor)
        adapter = WKBridgeAdapter(engine: engine, policy: .production)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = adapter
        webView.isInspectable = false
        webView.accessibilityIdentifier = "lab.webview"
        adapter.install(on: webView) { [weak self] message in
            self?.loadError = message
        }
        loadCurrentContent()
    }

    func reload() {
        loadError = nil
        loadCurrentContent()
    }

    func close() {
        adapter.close()
        webView.stopLoading()
    }

    private func loadCurrentContent() {
        let request = URLRequest(
            url: Self.webURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        webView.load(request)
    }

}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
