import Foundation

/// Inactive contract: capabilities refer to bounded synthetic lab receipts,
/// not actual NetworkExtension routing or shipping capability. No secrets.
enum TransportProtocol: Equatable {
    case vlessReality, wireGuard
    case amneziaWG1, amneziaWG2, amneziaWG3
}

enum TransportProvider: Equatable {
    // Logical process roles, not registered bundle identifiers.
    case rustXray, standaloneAWG
}

enum TransportProbeCapability: Hashable {
    case tcpIPv4, tcpIPv6, udpIPv4, udpIPv6, rawIPv4, rawIPv6
    case dns, quic, mtu, exactHostDirect, applicationExclusions
}

enum TransportContractError: Error, Equatable {
    case productionNotAccepted, unsupportedProtocol, unsupportedCapability
    case unsupportedRoutePolicy, providerMismatch, invalidTransition
    case staleSession, generationExhausted, profileFormatMismatch
}

struct TransportBackendPlan: Equatable {
    enum Scope { case syntheticLab, production }
    enum RoutePolicy { case tunnelOnly, directFallback, exclusions }
    let profileID: UUID
    // Opaque revision, not a credential or config digest.
    let revision: UUID
    let wireProtocol: TransportProtocol
    let provider: TransportProvider
    let required: Set<TransportProbeCapability>

    private init(profileID: UUID, revision: UUID, wireProtocol: TransportProtocol,
                 provider: TransportProvider, required: Set<TransportProbeCapability>) {
        self.profileID = profileID
        self.revision = revision
        self.wireProtocol = wireProtocol
        self.provider = provider
        self.required = required
    }

    static func prepare(profileID: UUID, revision: UUID, protocol wireProtocol: TransportProtocol,
                        scope: Scope, routes: RoutePolicy,
                        required: Set<TransportProbeCapability>) throws -> Self {
        guard scope == .syntheticLab else { throw TransportContractError.productionNotAccepted }
        guard routes == .tunnelOnly else { throw TransportContractError.unsupportedRoutePolicy }
        let provider: TransportProvider
        let evidence: Set<TransportProbeCapability>
        switch wireProtocol {
        case .vlessReality:
            provider = .rustXray
            evidence = [.tcpIPv4]
        case .wireGuard:
            provider = .rustXray
            evidence = [.tcpIPv4, .tcpIPv6, .udpIPv4, .udpIPv6]
        case .amneziaWG1:
            // Only the fixed matching legacy fixture on the pinned v3 engine.
            // No general AWG1 interoperability or app traffic asserted.
            provider = .standaloneAWG
            evidence = [.rawIPv4, .rawIPv6]
        case .amneziaWG2, .amneziaWG3:
            throw TransportContractError.unsupportedProtocol
        }
        guard !required.isEmpty, required.isSubset(of: evidence) else {
            throw TransportContractError.unsupportedCapability
        }
        return .init(profileID: profileID, revision: revision, wireProtocol: wireProtocol,
                     provider: provider, required: required)
    }

    /// Preflight the parsed format against the explicit selection. A
    /// syntactically valid AWG preview can never satisfy a standard WG plan.
    /// This is still not a validated runtime config or evidence for arbitrary
    /// profiles; the future provider must validate its own exact fixture.
    func validateWGPreview(_ preview: WGQuickConfigurationPreview) throws {
        switch (wireProtocol, preview.format) {
        case (.wireGuard, .wireGuard), (.amneziaWG1, .amneziaWG1): return
        default: throw TransportContractError.profileFormatMismatch
        }
    }

    func validateProvider(_ actual: TransportProvider) throws {
        guard actual == provider else { throw TransportContractError.providerMismatch }
    }
}

/// Serial app-side state machine. The future adapter must execute commands
/// serially and independently verify both native drain and OS disconnect.
/// No actual OS VPN manager or system-wide kill-switch behavior here.
struct TransportBackendCoordinator: Equatable {
    struct Token: Equatable {
        let epoch: UUID
        let generation: UInt64
    }
    struct Session: Equatable {
        let token: Token
        let plan: TransportBackendPlan
    }
    enum Phase: Equatable { case idle, starting, running, stopping, failedClosed }
    enum Command: Equatable {
        case start(Session)
        case stop(Session)
        case cancelTunnel(Session)
    }

    private let epoch = UUID()
    private(set) var phase: Phase = .idle
    private(set) var generation: UInt64 = 0
    private(set) var active: Session?
    private(set) var pending: TransportBackendPlan?
    private(set) var nativeDrained = false
    private(set) var osDisconnected = false

    mutating func begin(_ plan: TransportBackendPlan) throws -> Command {
        guard phase == .idle, active == nil else { throw TransportContractError.invalidTransition }
        return try start(plan)
    }

    private mutating func start(_ plan: TransportBackendPlan) throws -> Command {
        guard generation < UInt64.max else { throw TransportContractError.generationExhausted }
        generation += 1
        let session = Session(token: .init(epoch: epoch, generation: generation), plan: plan)
        active = session
        pending = nil
        nativeDrained = false
        osDisconnected = false
        phase = .starting
        return .start(session)
    }

    private func session(_ token: Token) throws -> Session {
        guard let active, active.token == token else { throw TransportContractError.staleSession }
        return active
    }

    mutating func ready(_ token: Token, provider: TransportProvider) throws -> Command? {
        let current = try session(token)
        guard phase == .starting else { throw TransportContractError.invalidTransition }
        guard provider == current.plan.provider else { return try failClosed(token) }
        phase = .running
        return nil
    }

    mutating func requestSwitch(to plan: TransportBackendPlan, token: Token) throws -> Command {
        let current = try session(token)
        guard phase == .running, current.plan != plan,
              current.plan.profileID != plan.profileID || current.plan.revision != plan.revision else {
            throw TransportContractError.invalidTransition
        }
        guard generation < UInt64.max else { throw TransportContractError.generationExhausted }
        pending = plan
        phase = .stopping
        return .stop(current)
    }

    /// Stop cancels a pending switch, including after the first drain receipt.
    mutating func requestStop(_ token: Token) throws -> Command? {
        let current = try session(token)
        switch phase {
        case .starting, .running:
            pending = nil
            phase = .stopping
            return .stop(current)
        case .stopping:
            pending = nil
            return nil
        default:
            throw TransportContractError.invalidTransition
        }
    }

    mutating func acknowledgeNativeDrain(_ token: Token) throws -> Command? {
        _ = try session(token)
        guard phase == .stopping else { throw TransportContractError.invalidTransition }
        nativeDrained = true
        return try finishStop()
    }

    mutating func acknowledgeOSDisconnected(_ token: Token) throws -> Command? {
        _ = try session(token)
        guard phase == .stopping else { throw TransportContractError.invalidTransition }
        osDisconnected = true
        return try finishStop()
    }

    private mutating func finishStop() throws -> Command? {
        guard nativeDrained && osDisconnected else { return nil }
        let next = pending
        active = nil
        pending = nil
        phase = .idle
        if let next { return try start(next) }
        return nil
    }

    /// On timeout, unexpected exit (even zero), or a wrong provider, cancel
    /// once and poison this coordinator. No fallback or queued replacement.
    /// Reconstruct only after external reconciliation proves all old
    /// providers stopped; a new epoch rejects delayed old callbacks.
    mutating func failClosed(_ token: Token) throws -> Command? {
        let current = try session(token)
        if phase == .failedClosed { return nil }
        guard phase == .starting || phase == .running || phase == .stopping else {
            throw TransportContractError.invalidTransition
        }
        pending = nil
        phase = .failedClosed
        return .cancelTunnel(current)
    }
}
