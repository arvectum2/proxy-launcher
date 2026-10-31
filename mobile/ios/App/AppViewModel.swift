import Foundation
import Combine
import NetworkExtension

enum ProfileHealth: Equatable {
    case checking
    case available(Int)
    case unavailable(ProxyFailureReason)

    var label: String {
        switch self {
        case .checking: return AppL10n.tr("проверяется")
        case .available(let latency): return "\(latency) мс"
        case .unavailable(let reason):
            let status = AppL10n.tr("недоступен")
            return reason == .unknown ? status : "\(status) · \(reason.code)"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var profiles: [ProxyProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var automaticSelection = true
    @Published var primaryProfileID: UUID?
    @Published var returnToPrimary = false
    @Published var exclusions: [String] = []
    @Published var health: [UUID: ProfileHealth] = [:]
    @Published var events: [TunnelEvent] = []
    @Published var errorMessage: String?

    let vpn = VPNController()
    private let store: ProfileStore
    private let telemetry = TelemetryStore()
    private var cancellables: Set<AnyCancellable> = []
    private var healthScanGeneration = 0

    init() {
        do {
            store = try ProfileStore()

            // VPNController is its own ObservableObject. Forward its changes
            // through AppViewModel so SwiftUI refreshes controls that read
            // model.vpn.status/detail instead of showing the previous state.
            vpn.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)

            refresh()
        } catch {
            fatalError("App Group storage is unavailable: \(error.localizedDescription)")
        }
    }

    var selectedLabel: String {
        if automaticSelection { return "Авто" }
        return profiles.first(where: { $0.id == selectedProfileID })?.name ?? "Выберите прокси"
    }

    func prepare() async {
        await vpn.prepare()
        await scanProfiles()
        refreshEvents()
    }

    func refresh() {
        profiles = store.listProfiles()
        // Removing a profile must not leave obsolete diagnostics in memory.
        let currentIDs = Set(profiles.map(\.id))
        health = health.filter { currentIDs.contains($0.key) }
        selectedProfileID = store.selectedProfileID
        automaticSelection = store.automaticSelection
        primaryProfileID = store.primaryProfileID
        returnToPrimary = store.restorePolicy == .returnToPrimary
        exclusions = store.siteExclusions
        refreshEvents()
    }

    func selectAuto() {
        store.automaticSelection = true
        automaticSelection = true
        selectedProfileID = nil
    }

    func select(_ profile: ProxyProfile) {
        store.selectedProfileID = profile.id
        store.automaticSelection = false
        automaticSelection = false
        selectedProfileID = profile.id
    }

    func setPrimary(_ profile: ProxyProfile) {
        store.primaryProfileID = profile.id
        primaryProfileID = profile.id
    }

    func setReturnToPrimary(_ enabled: Bool) {
        store.restorePolicy = enabled ? .returnToPrimary : .stayOnCurrent
        returnToPrimary = enabled
    }

    func saveProfile(
        editingID: UUID?,
        name: String,
        host: String,
        portText: String,
        type: ProxyType,
        username: String,
        password: String
    ) -> Bool {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty, let port = Int(portText), (1...65535).contains(port) else {
            errorMessage = "Проверьте адрес и порт прокси"
            return false
        }

        let profile = ProxyProfile(
            id: editingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(cleanHost):\(port)" : name,
            host: cleanHost,
            port: port,
            type: type,
            username: username
        )
        do {
            let isEditing = editingID != nil
            try store.save(
                profile,
                password: password.isEmpty ? nil : password,
                makeActive: !isEditing || selectedProfileID == editingID,
                preservePasswordIfNil: isEditing && password.isEmpty
            )
            refresh()
            Task { await scanProfiles() }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteProfile(id: UUID) {
        do { try store.delete(id: id); refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ profile: ProxyProfile) {
        do {
            try store.delete(id: profile.id)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveExclusions(_ raw: [String]) async -> Bool {
        do {
            let normalized = try SiteExclusionPolicy.normalizeAll(raw)
            let previous = store.siteExclusions
            store.siteExclusions = normalized
            do {
                try await vpn.reconnectIfActive()
            } catch {
                // Do not persist a configuration that failed to activate.
                store.siteExclusions = previous
                exclusions = previous
                // Best-effort recovery of the previous active tunnel settings.
                try? await vpn.reconnectIfActive()
                throw error
            }
            exclusions = normalized
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleVPN() async {
        errorMessage = nil
        if vpn.isConnectedOrConnecting {
            vpn.disconnect()
            return
        }
        guard !profiles.isEmpty else {
            errorMessage = "Сначала добавьте хотя бы один прокси"
            return
        }
        if !automaticSelection, selectedProfileID == nil {
            select(profiles[0])
        }
        do {
            try await vpn.connect()
        } catch {
            // Preserve the actionable NetworkExtension explanation but
            // identify system tunnel failures unambiguously in the alert.
            let kind = ProxyFailureReason.classify(error)
            errorMessage = kind == .tunnel
                ? "VPN: " + error.localizedDescription
                : error.localizedDescription
        }
    }

    func scanProfiles() async {
        // Saving another profile while an async network probe is suspended
        // must not let stale responses overwrite newer health results.
        healthScanGeneration &+= 1
        let generation = healthScanGeneration
        let snapshot = profiles
        guard !snapshot.isEmpty else { health = [:]; return }
        let probe = ProxyProbe()
        for profile in snapshot {
            guard generation == healthScanGeneration else { return }
            health[profile.id] = .checking
            do {
                let result = try await probe.resolveMeasured(profile, password: try store.password(for: profile.id))
                guard generation == healthScanGeneration else { return }
                health[profile.id] = .available(result.latencyMs)
            } catch {
                guard generation == healthScanGeneration else { return }
                health[profile.id] = .unavailable(ProxyFailureReason.classify(error))
            }
        }
    }

    func refreshEvents() {
        events = telemetry.list()
    }
}
