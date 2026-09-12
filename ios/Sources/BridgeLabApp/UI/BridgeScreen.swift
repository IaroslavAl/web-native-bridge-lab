import SwiftUI

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
