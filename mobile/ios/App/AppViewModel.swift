import Foundation
import NetworkExtension

enum ProfileHealth: Equatable {
    case checking
    case available(Int)
    case unavailable

    var label: String {
        switch self {
        case .checking: return "проверяется"
        case .available(let latency): return "\(latency) мс"
        case .unavailable: return "недоступен"
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

    init() {
        do {
            store = try ProfileStore()
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
            store.siteExclusions = normalized
            exclusions = normalized
            try await vpn.reconnectIfActive()
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
            errorMessage = error.localizedDescription
        }
    }

    func scanProfiles() async {
        guard !profiles.isEmpty else { return }
        let probe = ProxyProbe()
        for profile in profiles {
            health[profile.id] = .checking
            do {
                let result = try await probe.resolveMeasured(profile, password: try store.password(for: profile.id))
                health[profile.id] = .available(result.latencyMs)
            } catch {
                health[profile.id] = .unavailable
            }
        }
    }

    func refreshEvents() {
        events = telemetry.list()
    }
}
