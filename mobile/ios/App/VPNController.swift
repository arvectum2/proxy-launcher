import Foundation
import NetworkExtension

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var detail = "Отключено"

    // Shared across controller instances in this app process, including Shortcuts.
    private static let operationGate = NativeOperationGate()
    #if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION
    private static var nativeValidationDispatch:NativeValidationDispatch?
    private static var nativeValidationTarget:(manager:NETunnelProviderManager,connection:NETunnelProviderSession,owner:UUID)?
    private static var nativeReconcileInFlight=false
    private static let nativeValidationName="APL Native Credential Validation"
    #endif
    private static let configurationName = "Arvectum Proxy Launcher"

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var isConnectedOrConnecting: Bool {
        status == .connected || status == .connecting || status == .reasserting
    }

    var canToggle: Bool {
        status != .disconnecting
    }

    func prepare() async {
        do {
            try await Self.operationGate.perform(.start) {
                manager = try await loadOrCreateManager()
                refreshStatus()
            }
        } catch {
            detail = ProxyFailureReason.safeDisplay(
                for: userFacingError(error), translate: { AppL10n.tr($0) })
        }
    }

    func connect() async throws {
        try await Self.operationGate.perform(.start) {
            try await connectWithLease()
        }
    }

    /// Inactive native restore adapter. Only read preferences, never create,
    /// reconcile or save managers. This checks visible APL managers, not a
    /// global OS lock; external starts and separate processes remain gated.
    func confirmNativeRestoreForValidation(_ review: NativeRestoreReview,
                                           summary: NativeRestoreReview.Summary) async throws -> [NativeCredentialRecord.Reference] {
        try await Self.operationGate.perform(.restore) {
            defer { review.cancel() }
            let managers = try await loadAllManagers(requireResult:true).filter(isArvectumManager)
            try Task.checkCancellation()
            return try review.confirm(summary,vpnInactive:{
                guard !Task.isCancelled else {return false}
                let known = managers + (self.manager.map { [$0] } ?? [])
                return known.allSatisfy { !$0.isOnDemandEnabled && $0.connection.status == .disconnected }
            })
        }
    }

    #if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION
    /// Deliberately has no UI caller. Requires an externally provisioned,
    /// uniquely owned validation manager; never creates/saves one here.
    /// Successful API submission is NOT connection or drain acceptance.
    func submitNativeCredentialValidation(reference:NativeCredentialRecord.Reference,owner:UUID) async throws {
        guard Self.nativeValidationDispatch==nil,Self.operationGate.active==nil else{throw NativeOperationGate.Failure.busy}
        let store=try ProfileStore(),boundary=store.makeNativeValidationLaunchBoundary()
        guard try store.nativeValidationPolicyIsEmpty() else{throw NativeValidationDispatch.Failure.unownedManager}
        let intent=try boundary.prepare(reference:reference,scope:.syntheticLab,routes:.tunnelOnly,required:[.tcpIPv4],siteExclusions:[],applicationExclusions:[])
        let dispatch=try NativeValidationDispatch(gate:Self.operationGate,boundary:boundary,intent:intent,owner:owner)
        Self.nativeValidationDispatch=dispatch
        do {
            let all=try await loadAllManagers(requireResult:true)
            try Task.checkCancellation()
            let named=all.filter{ item in
                let c=(item.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
                return NativeProviderStartRequest.hasReservedKey(Array(c.keys))
            }
            guard named.count==1,let target=named.first,let connection=target.connection as? NETunnelProviderSession else{throw NativeValidationDispatch.Failure.unownedManager}
            func check()->Bool {
                guard !Task.isCancelled,let proto=target.protocolConfiguration as? NETunnelProviderProtocol,
                    proto.providerBundleIdentifier==AppShared.providerBundleIdentifier,
                    target.localizedDescription==Self.nativeValidationName,proto.serverAddress==Self.nativeValidationName,
                    NativeProviderStartRequest.ownsConfiguration(proto.providerConfiguration,owner:owner),
                    target.isEnabled,target.connection === connection,
                    (try? store.nativeValidationPolicyIsEmpty())==true else{return false}
                let visible=all+(self.manager.map{[$0]} ?? [])
                return visible.allSatisfy{!$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty && $0.connection.status == .disconnected}
            }
            Self.nativeValidationTarget=(target,connection,owner)
            try dispatch.submit(checkOwnedAndQuiescent:check,start:{try connection.startTunnel(options:$0)})
        } catch {
            if !dispatch.attempted {
                try dispatch.abortBeforeSubmission()
                Self.nativeValidationDispatch=nil;Self.nativeValidationTarget=nil
            }
            // On ambiguous start, retain exact ownership. A later real drain
            // receipt/reconciliation implementation is required before reuse.
            throw error
        }
    }
    /// Retry only a failed pre-submit cleanup. Never unlock a submitted start.
    func abortNativeCredentialValidationBeforeSubmission() throws {
        guard let dispatch=Self.nativeValidationDispatch else{return}
        try dispatch.abortBeforeSubmission()
        Self.nativeValidationDispatch=nil;Self.nativeValidationTarget=nil
    }
    /// Future concrete terminal path. No caller until runtime acceptance.
    /// Never infer native drain from OS status or from a missing reply.
    func reconcileNativeCredentialValidation() async throws {
        guard !Self.nativeReconcileInFlight,let dispatch=Self.nativeValidationDispatch,dispatch.attempted,
              let target=Self.nativeValidationTarget else{throw NativeValidationDispatch.Failure.invalidState}
        Self.nativeReconcileInFlight=true;defer{Self.nativeReconcileInFlight=false}
        func owned()->Bool {
            guard let proto=target.manager.protocolConfiguration as? NETunnelProviderProtocol else{return false}
            return target.manager.connection === target.connection && proto.providerBundleIdentifier==AppShared.providerBundleIdentifier && target.manager.localizedDescription==Self.nativeValidationName && proto.serverAddress==Self.nativeValidationName && NativeProviderStartRequest.ownsConfiguration(proto.providerConfiguration,owner:target.owner) && target.manager.isEnabled && !target.manager.isOnDemandEnabled && (target.manager.onDemandRules ?? []).isEmpty
        }
        try Task.checkCancellation();guard owned() else{throw NativeValidationDispatch.Failure.unownedManager}
        if !dispatch.terminalEvidence {
            guard target.connection.status == .connected else{throw NativeValidationDispatch.Failure.invalidState}
            let request=try dispatch.requestTerminalDrain(),bytes=try TransportNativeCodec.encode(request)
            let reply:Data=try await withCheckedThrowingContinuation { continuation in
                let completion=NativeReconcileCompletion(continuation)
                do {try target.connection.sendProviderMessage(bytes){data in
                    if let data {completion.finish(.success(data))} else {completion.finish(.failure(NativeValidationDispatch.Failure.invalidState))}
                }}catch{completion.finish(.failure(error))}
                DispatchQueue.global().asyncAfter(deadline:.now()+6){completion.finish(.failure(NativeValidationDispatch.Failure.invalidState))}
            }
            try Task.checkCancellation();guard owned() else{throw NativeValidationDispatch.Failure.unownedManager}
            try dispatch.acceptTerminalDrain(TransportNativeCodec.decode(TransportNativeResponse.self,reply))
        }
        guard owned() else{throw NativeValidationDispatch.Failure.unownedManager}
        if target.connection.status == .connected {target.connection.stopVPNTunnel()}
        let deadline=ProcessInfo.processInfo.systemUptime+10
        while owned() && target.connection.status == .disconnecting && ProcessInfo.processInfo.systemUptime<deadline {
            try await Task.sleep(nanoseconds:100_000_000)
        }
        try Task.checkCancellation()
        let all=try await loadAllManagers(requireResult:true)
        let marked=all.filter{NativeProviderStartRequest.hasReservedKey(Array((($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]).keys))}
        try dispatch.finishAfterTerminalDrain(osOffAndOwned:{
            guard !Task.isCancelled,owned(),target.connection.status == .disconnected,marked.count==1,let item=marked.first,let proto=item.protocolConfiguration as? NETunnelProviderProtocol,proto.providerBundleIdentifier==AppShared.providerBundleIdentifier,NativeProviderStartRequest.ownsConfiguration(proto.providerConfiguration,owner:target.owner) else{return false}
            return all.allSatisfy{!$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty && $0.connection.status == .disconnected}
        })
        Self.nativeValidationDispatch=nil;Self.nativeValidationTarget=nil
    }
    #endif

    private func connectWithLease() async throws {
        var manager = try await loadOrCreateManager()
        self.manager = manager

        do {
            try startTunnel(using: manager)
        } catch {
            guard isRepairableConfigurationError(error) else {
                throw userFacingError(error)
            }

            // iOS can keep an existing Network Extension configuration around
            // in a disabled/stale state (for example after reinstalling a
            // development build). Reload, reconcile and persist our complete
            // configuration, then retry once.
            manager = try await loadOrCreateManager(forceSave: true)
            self.manager = manager

            do {
                try startTunnel(using: manager)
            } catch {
                throw userFacingError(error)
            }
        }

        detail = "Подключение…"
        refreshStatus()
    }

    func disconnect() {
        guard Self.operationGate.active != .nativeValidation else{return}
        manager?.connection.stopVPNTunnel()
        detail = "Отключение…"
        refreshStatus()
    }

    /// Explicit Shortcuts disconnection must not report completion before
    /// NetworkExtension has actually left the connected/connecting states.
    func disconnectAndWait() async throws {
        guard isConnectedOrConnecting else { return }
        disconnect()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            try Task.checkCancellation()
            refreshStatus()
            if status == .disconnected || status == .invalid { return }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw NSError(domain: "ArvectumVPN", code: 13,
                      userInfo: [NSLocalizedDescriptionKey: "VPN не успел отключиться. Проверьте состояние подключения."])
    }

    func reconnectIfActive() async throws {
        guard isConnectedOrConnecting else { return }
        disconnect()
        // NetworkExtension shutdown is asynchronous. A fixed sleep can race
        // the previous tunnel and make startVPNTunnel fail intermittently.
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            try Task.checkCancellation()
            let current = manager?.connection.status ?? .invalid
            if current == .disconnected || current == .invalid { break }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        let current = manager?.connection.status ?? .invalid
        guard current == .disconnected || current == .invalid else {
            throw NSError(domain: "ArvectumVPN", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Не удалось дождаться отключения VPN"])
        }
        try await connect()
    }

    /// Restore the previously active tunnel after reverting an exclusion
    /// update. The preceding stop may still be asynchronously disconnecting.
    func restoreAfterFailedExclusionsUpdate() async throws {
        let deadline = Date().addingTimeInterval(8)
        while manager?.connection.status == .disconnecting && Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        guard manager?.connection.status != .disconnecting else {
            throw NSError(domain: "ArvectumVPN", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "VPN ещё отключается; повторите подключение вручную"])
        }
        refreshStatus()
        if isConnectedOrConnecting { try await reconnectIfActive() }
        else { try await connect() }
    }

    private func refreshStatus() {
        status = manager?.connection.status ?? .invalid
        detail = switch status {
        case .invalid, .disconnected: "Отключено"
        case .connecting: "Подключение…"
        case .connected: "Подключено"
        case .reasserting: "Переподключение…"
        case .disconnecting: "Отключение…"
        @unknown default: "Неизвестное состояние"
        }
    }

    private func startTunnel(using manager: NETunnelProviderManager) throws {
        try requireLegacyManager(manager)
        guard let session = manager.connection as? NETunnelProviderSession else {
            throw NSError(
                domain: "ArvectumVPN",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Не удалось открыть VPN-сессию"]
            )
        }
        var tunnelOptions: [String: NSObject] = ["requestedByUser": NSNumber(value: true)]
#if DEBUG
        // An explicit real-device QA run is bounded by two independent kill
        // switches: one in the app, one in the Packet Tunnel extension.
        // This option is never used in App Store distribution binaries.
        if ProcessInfo.processInfo.arguments.contains("-aplEphemeralTunnelQA") {
            let scopedLab = ProcessInfo.processInfo.arguments.contains("-aplSmart3LocalProxyQA") &&
                ProcessInfo.processInfo.arguments.contains("-aplSmart3ScopedDirectLabQA")
            let radioHandoffQA = scopedLab &&
                ProcessInfo.processInfo.arguments.contains("-aplSmart3RadioHandoffQA")
            let qaLimit = radioHandoffQA ? 95 : scopedLab ? 30 : 25
            tunnelOptions["qaStopAfterSeconds"] = NSNumber(value: qaLimit)
            if radioHandoffQA { tunnelOptions["qaRadioHandoff"] = NSNumber(value: true) }
            UserDefaults(suiteName: AppShared.defaultsSuite)?
                .set(qaLimit, forKey: "qaSmart3RadioRequestedDuration.v1")
            if ProcessInfo.processInfo.arguments.contains("-aplSmart3LocalProxyQA") {
                // Disposable physical QA only; no saved credentials/profiles.
                tunnelOptions["qaSmart3ProxyHost"] = "192.168.1.80" as NSString
                tunnelOptions["qaSmart3ProxyPort"] = NSNumber(value: 18081)
                if ProcessInfo.processInfo.arguments.contains("-aplSmart3ScopedDirectLabQA") {
                    tunnelOptions["qaScopedDirect"] = NSNumber(value: true)
                    if ProcessInfo.processInfo.arguments.contains("-aplSmart3PathResetLabQA") {
                        tunnelOptions["qaResetDirectAfterSeconds"] = NSNumber(value: 17)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-aplSmart3TTLResetLabQA") {
                        tunnelOptions["qaDirectTTLSeconds"] = NSNumber(value: 4)
                    }
                }
            }
        }
#endif
        try session.startTunnel(options: tunnelOptions)
    }

    private func loadOrCreateManager(forceSave: Bool = false) async throws -> NETunnelProviderManager {
        let managers = try await loadAllManagers()

        let matching = managers.filter(isArvectumManager)
        for item in matching {try requireLegacyManager(item)}
        let manager = matching.first(where: { $0.isEnabled }) ?? matching.first ?? NETunnelProviderManager()

        if !matching.isEmpty {
            try await reload(manager)
        }

        try requireLegacyManager(manager)
        let changed = reconcile(manager)
        if forceSave || changed || matching.isEmpty {
            try await save(manager)
            try await reload(manager)
        }

        return manager
    }

    private func loadAllManagers(requireResult: Bool = false) async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if requireResult && managers == nil {
                    continuation.resume(throwing: ProxyDiagnosticError(.tunnel))
                } else {
                    continuation.resume(returning: managers ?? [])
                }
            }
        }
    }

    private func isArvectumManager(_ manager: NETunnelProviderManager) -> Bool {
        if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
           proto.providerBundleIdentifier == AppShared.providerBundleIdentifier {
            return true
        }
        return manager.localizedDescription == Self.configurationName
    }

    /// Do not silently repair or adopt a manager reserved for future native use.
    private func requireLegacyManager(_ manager: NETunnelProviderManager) throws {
        let config=(manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        guard !NativeProviderStartRequest.hasReservedKey(Array(config.keys)) else {
            throw NSError(domain:"APLNativeStart",code:1)
        }
    }

    @discardableResult
    private func reconcile(_ manager: NETunnelProviderManager) -> Bool {
        var changed = false
        let proto: NETunnelProviderProtocol

        if let existing = manager.protocolConfiguration as? NETunnelProviderProtocol {
            proto = existing
        } else {
            proto = NETunnelProviderProtocol()
            changed = true
        }

        if proto.providerBundleIdentifier != AppShared.providerBundleIdentifier {
            proto.providerBundleIdentifier = AppShared.providerBundleIdentifier
            changed = true
        }

        if proto.serverAddress != Self.configurationName {
            proto.serverAddress = Self.configurationName
            changed = true
        }

        var providerConfiguration = proto.providerConfiguration ?? [:]
        if providerConfiguration["version"] as? String != AppShared.version {
            providerConfiguration["version"] = AppShared.version
            proto.providerConfiguration = providerConfiguration
            changed = true
        }

        if changed {
            // Reassign after creating or mutating the protocol object so
            // NetworkExtension persists the refreshed provider configuration.
            manager.protocolConfiguration = proto
        }

        if manager.localizedDescription != Self.configurationName {
            manager.localizedDescription = Self.configurationName
            changed = true
        }

        if !manager.isEnabled {
            manager.isEnabled = true
            changed = true
        }

        return changed
    }

    private func isRepairableConfigurationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NEVPNErrorDomain else { return false }

        return nsError.code == NEVPNError.Code.configurationDisabled.rawValue
            || nsError.code == NEVPNError.Code.configurationInvalid.rawValue
            || nsError.code == NEVPNError.Code.configurationStale.rawValue
    }

    private func userFacingError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == NEVPNErrorDomain else {
            return ProxyDiagnosticError(ProxyFailureReason.classify(error))
        }
        // Preserve precise, translated guidance while never forwarding a
        // system error description (which could contain private endpoints).
        switch nsError.code {
        case NEVPNError.Code.configurationDisabled.rawValue:
            return ProxyDiagnosticError(.tunnel, recoveryHint: .vpnDisabled)
        case NEVPNError.Code.configurationStale.rawValue:
            return ProxyDiagnosticError(.tunnel, recoveryHint: .vpnStale)
        case NEVPNError.Code.configurationInvalid.rawValue:
            return ProxyDiagnosticError(.tunnel, recoveryHint: .vpnInvalid)
        default:
            return ProxyDiagnosticError(.tunnel)
        }
    }

    private func save(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func reload(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}

#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION
private final class NativeReconcileCompletion: @unchecked Sendable {
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Data,Error>?
    init(_ continuation:CheckedContinuation<Data,Error>){self.continuation=continuation}
    func finish(_ result:Result<Data,Error>){lock.lock();let c=continuation;continuation=nil;lock.unlock();c?.resume(with:result)}
}
#endif
