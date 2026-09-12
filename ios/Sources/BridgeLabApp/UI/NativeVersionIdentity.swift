import Foundation

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
