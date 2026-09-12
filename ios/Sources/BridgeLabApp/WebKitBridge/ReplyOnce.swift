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
