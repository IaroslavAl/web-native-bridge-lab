import SwiftUI
import WebKit
import TransportPackage

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

struct NativeVersionIdentity: Equatable {
    let version: String?
    let build: String?

    init(infoDictionary: [String: Any]?) {
        version = Self.nonemptyString(infoDictionary?["CFBundleShortVersionString"])
        build = Self.nonemptyString(infoDictionary?["CFBundleVersion"])
    }

    var displayText: String {
        "Версия приложения \(version ?? "недоступна") · сборка \(build ?? "недоступна")"
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum BridgeLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}

struct BridgeScreen: View {
    @StateObject private var model = BridgeWebViewModel()
    private let nativeVersion = NativeVersionIdentity(infoDictionary: Bundle.main.infoDictionary)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bridge Lab")
                        .font(.headline)
                    Text("Веб-экран через приложение")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Обновить") {
                    model.reload()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("lab.reload")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if case .loading = model.loadState {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Загружаем веб-экран")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityIdentifier("lab.loadStatus")
            } else if case .failed(let message) = model.loadState {
                HStack(alignment: .center, spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("lab.loadError")
                    Spacer(minLength: 4)
                    Button("Повторить") {
                        model.reload()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("lab.retry")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            WebViewContainer(webView: model.webView)
                .accessibilityIdentifier("lab.webview")
                .allowsHitTesting(model.loadState == .loaded)
                .accessibilityHidden(model.loadState != .loaded)
                .opacity(model.loadState == .loaded ? 1 : 0.35)

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text("Веб-экран меняется без замены приложения")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(nativeVersion.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("lab.nativeVersion")
                    .accessibilityLabel(nativeVersion.displayText)
                    .accessibilityHint("Долгое нажатие открывает действия Диагностика и Вернуться к демо")
                    .contextMenu {
                        Button("Диагностика") {
                            model.openDiagnostics()
                        }
                        .accessibilityIdentifier("lab.openDiagnostics")
                        Button("Вернуться к демо") {
                            model.openDemo()
                        }
                        .accessibilityIdentifier("lab.openDemo")
                    }
                    .accessibilityAction(named: Text("Диагностика")) {
                        model.openDiagnostics()
                    }
                    .accessibilityAction(named: Text("Вернуться к демо")) {
                        model.openDemo()
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
        .onDisappear {
            model.close()
        }
    }
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

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
