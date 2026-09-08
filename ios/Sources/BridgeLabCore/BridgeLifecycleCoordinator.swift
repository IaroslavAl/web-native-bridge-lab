import Foundation
import TransportPackage

/// Validation/hello/cancel replies are immediate; HTTP work carries an admitted
/// receipt. Only the executor selects the latter's terminal value.
public enum BridgeAdmission: Sendable {
    case immediate(BridgeReply)
    case running(HTTPExecution)

    public init(_ submission: HTTPSubmission) {
        switch submission {
        case .immediate(let result): self = .immediate(Self.reply(result))
        case .running(let execution): self = .running(execution)
        }
    }

    public func result() async -> BridgeReply {
        switch self {
        case .immediate(let reply): return reply
        case .running(let execution): return Self.reply(await execution.result())
        }
    }

    private static func reply(_ result: HTTPResult) -> BridgeReply {
        switch result {
        case .response(let response): return .response(response)
        case .failure(let failure):
            return .error(id: failure.id, code: failure.code, message: failure.message)
        }
    }
}

/// Serializes short admission/control operations, never HTTP lifetimes. WebKit
/// integration is deliberately deferred to stage B; callers must capture ingress
/// synchronously on MainActor and return an acknowledged admission, not execute().
@MainActor
public final class BridgeLifecycleCoordinator {
    public typealias Admission = @MainActor () async -> BridgeAdmission
    public typealias Publication = @MainActor (BridgeReply) async -> Void

    private enum Command {
        case activate(UUID)
        case invoke(UUID, Admission, Publication)
        case revoke
    }

    private let activate: @MainActor () async -> Void
    private let cancelAll: @MainActor () async -> Void
    private var generation = UUID()
    private var wantsActive = false
    private var active = false
    private var commands: [Command] = []
    private var consuming = false
    private var publications: [UUID: Task<Void, Never>] = [:]

    var pendingPublicationCount: Int { publications.count }

    public init(
        activate: @escaping @MainActor () async -> Void,
        revoke: @escaping @MainActor () async -> Void
    ) {
        self.activate = activate
        self.cancelAll = revoke
    }

    public func commit() {
        guard !wantsActive else { return }
        wantsActive = true
        append(.activate(generation))
    }

    public func receive(admit: @escaping Admission, publish: @escaping Publication) {
        guard wantsActive else {
            publishLater(.immediate(Self.denied), to: publish)
            return
        }
        append(.invoke(generation, admit, publish))
    }

    public func revoke() {
        guard wantsActive else { return }
        // Synchronous ingress fence, distinct from executor terminal selection.
        generation = UUID()
        wantsActive = false
        active = false
        append(.revoke)
    }

    private func append(_ command: Command) {
        commands.append(command)
        guard !consuming else { return }
        consuming = true
        Task { await consume() }
    }

    private func consume() async {
        while !commands.isEmpty {
            let command = commands.removeFirst()
            switch command {
            case .activate(let captured):
                guard captured == generation, wantsActive else { continue }
                await activate()
                active = captured == generation && wantsActive
            case .invoke(let captured, let admit, let publish):
                guard active, captured == generation else {
                    publishLater(.immediate(Self.denied), to: publish)
                    continue
                }
                // Revoke may fence ingress here, but its cancelAll command cannot
                // overtake registration of this receipt on the executor actor.
                let admission = await admit()
                publishLater(admission, to: publish)
            case .revoke:
                await cancelAll()
                let retiring = Array(publications.values)
                for publication in retiring { await publication.value }
            }
        }
        consuming = false
    }

    private func publishLater(_ admission: BridgeAdmission, to publish: @escaping Publication) {
        let key = UUID()
        publications[key] = Task { [weak self] in
            let reply = await admission.result()
            // No current-generation lookup or result rewriting at publication.
            await publish(reply)
            self?.publications.removeValue(forKey: key)
        }
    }

    private static let denied = BridgeReply.error(
        id: nil, code: "ORIGIN_DENIED", message: "Bridge origin denied"
    )
}
