import Foundation
import NetworkExtension

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var detail = "Отключено"

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
            manager = try await loadOrCreateManager()
            refreshStatus()
        } catch {
            detail = error.localizedDescription
        }
    }

    func connect() async throws {
        let manager = try await loadOrCreateManager()
        self.manager = manager
        guard let session = manager.connection as? NETunnelProviderSession else {
            throw NSError(domain: "ArvectumVPN", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Не удалось открыть VPN-сессию"
            ])
        }
        try session.startTunnel(options: ["requestedByUser": true as NSNumber])
        detail = "Подключение…"
        refreshStatus()
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
        detail = "Отключение…"
        refreshStatus()
    }

    func reconnectIfActive() async throws {
        guard isConnectedOrConnecting else { return }
        disconnect()
        try await Task.sleep(nanoseconds: 500_000_000)
        try await connect()
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

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let existing = try await withCheckedThrowingContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: managers ?? []) }
            }
        }
        if let manager = existing.first {
            try await reload(manager)
            return manager
        }

        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppShared.providerBundleIdentifier
        proto.serverAddress = "Arvectum Proxy Launcher"
        proto.providerConfiguration = ["version": AppShared.version]
        manager.protocolConfiguration = proto
        manager.localizedDescription = "Arvectum Proxy Launcher"
        manager.isEnabled = true
        try await save(manager)
        try await reload(manager)
        return manager
    }

    private func save(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { continuation in
            manager.saveToPreferences { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func reload(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { continuation in
            manager.loadFromPreferences { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
