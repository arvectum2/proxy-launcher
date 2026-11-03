import Foundation
import NetworkExtension

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var detail = "Отключено"

    private static let configurationName = "Arvectum Proxy Launcher"

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var userRequestedDisconnect = false
    private var hasObservedConnection = false
    private var recoveryTask: Task<Void, Never>?
    private var reconnectPolicy = TunnelAutoReconnectPolicy()
    private var lastHandledFailureID: UUID?

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
            // Passive app launch must not create, enable, or persist a VPN
            // configuration. Only an explicit Connect action may mutate
            // Network Extension preferences and trigger the macOS consent UI.
            manager = try await loadExistingManager()
            refreshStatus()
        } catch {
            detail = userFacingError(error).localizedDescription
        }
    }

    func connect() async throws {
        var manager = try await loadOrCreateManager()
        self.manager = manager

        do {
            try startTunnel(using: manager)
        } catch {
            guard isRepairableConfigurationError(error) else {
                throw userFacingError(error)
            }

            // macOS can keep an existing Network Extension configuration around
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

        userRequestedDisconnect = false
        detail = "Подключение…"
        refreshStatus()
    }

    func disconnect() {
        userRequestedDisconnect = true
        recoveryTask?.cancel()
        recoveryTask = nil
        manager?.connection.stopVPNTunnel()
        detail = "Отключение…"
        refreshStatus()
    }

    func reconnectIfActive() async throws {
        guard isConnectedOrConnecting else { return }
        disconnect()
        // NetworkExtension may still be tearing down the old provider after
        // stopVPNTunnel returns. Reconnecting before .disconnected causes a
        // stale "Connected" UI with DNS still wired to the previous session.
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

    /// Retry the previous settings only after NetworkExtension actually stops.
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
        let previous = status
        status = manager?.connection.status ?? .invalid
        if status == .connected {
            hasObservedConnection = true
            recoveryTask?.cancel()
            recoveryTask = nil
        }
        if status == .disconnected && previous != .disconnected {
            scheduleRecoveryAfterUnexpectedFailure()
        }
        detail = switch status {
        case .invalid, .disconnected: "Отключено"
        case .connecting: "Подключение…"
        case .connected: "Подключено"
        case .reasserting: "Переподключение…"
        case .disconnecting: "Отключение…"
        @unknown default: "Неизвестное состояние"
        }
    }

    /// Only the tunnel provider can identify an internal engine failure. Do not
    /// reconnect after an explicit Stop or a manual disconnect in System Settings.
    private func scheduleRecoveryAfterUnexpectedFailure() {
        guard !userRequestedDisconnect, hasObservedConnection, recoveryTask == nil else { return }
        let events = TelemetryStore().list(limit: 12)
        guard let failure = events.first(where: { $0.type == "switch failed" }),
              !events.contains(where: { $0.type == "manual stop" && $0.timestamp >= failure.timestamp }),
              failure.id != lastHandledFailureID,
              reconnectPolicy.mayRetry(now: Date(), failureAt: failure.timestamp,
                                       explicitDisconnect: userRequestedDisconnect) else { return }
        lastHandledFailureID = failure.id
        recoveryTask = Task { [weak self] in
            defer { self?.recoveryTask = nil }
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled, !self.userRequestedDisconnect,
                      self.manager?.connection.status == .disconnected else { return }
                try await self.connect()
                TelemetryStore().append(TunnelEvent(type: "automatic reconnect",
                    detail: "Recovered after internal engine failure"))
            } catch {
                if !Task.isCancelled {
                    TelemetryStore().append(TunnelEvent(type: "automatic reconnect failed",
                        detail: error.localizedDescription))
                }
            }
        }
    }

    private func startTunnel(using manager: NETunnelProviderManager) throws {
        guard let session = manager.connection as? NETunnelProviderSession else {
            throw NSError(
                domain: "ArvectumVPN",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Не удалось открыть VPN-сессию"]
            )
        }
        try session.startTunnel(options: ["requestedByUser": true as NSNumber])
    }

    private func loadExistingManager() async throws -> NETunnelProviderManager? {
        let managers = try await loadAllManagers()
        let matching = managers.filter(isArvectumManager)
        guard let manager = matching.first(where: { $0.isEnabled }) ?? matching.first else {
            return nil
        }
        try await reload(manager)
        return manager
    }

    private func loadOrCreateManager(forceSave: Bool = false) async throws -> NETunnelProviderManager {
        let managers = try await loadAllManagers()

        let matching = managers.filter(isArvectumManager)
        let manager = matching.first(where: { $0.isEnabled }) ?? matching.first ?? NETunnelProviderManager()

        if !matching.isEmpty {
            try await reload(manager)
        }

        let changed = reconcile(manager)
        if forceSave || changed || matching.isEmpty {
            try await save(manager)
            try await reload(manager)
        }

        return manager
    }

    private func loadAllManagers() async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
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

    private func userFacingError(_ error: Error) -> NSError {
        let nsError = error as NSError
        guard nsError.domain == NEVPNErrorDomain else { return nsError }

        switch nsError.code {
        case NEVPNError.Code.configurationDisabled.rawValue:
            return NSError(
                domain: "ArvectumVPN",
                code: nsError.code,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "macOS отключила конфигурацию VPN. Откройте Системные настройки → VPN и разрешите Arvectum Proxy Launcher, затем повторите подключение."
                ]
            )
        case NEVPNError.Code.configurationStale.rawValue:
            return NSError(
                domain: "ArvectumVPN",
                code: nsError.code,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Конфигурация VPN была изменена системой. Перезапустите подключение — приложение перечитает и восстановит её."
                ]
            )
        case NEVPNError.Code.configurationInvalid.rawValue:
            return NSError(
                domain: "ArvectumVPN",
                code: nsError.code,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "macOS отклонила конфигурацию Packet Tunnel. Конфигурация была восстановлена, но системе всё ещё не удалось её запустить."
                ]
            )
        default:
            return nsError
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
