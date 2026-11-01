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
    @Published var profileOrganization = ProfileOrganization()
    @Published var selectedProfileID: UUID?
    @Published var automaticSelection = true
    @Published var primaryProfileID: UUID?
    @Published var returnToPrimary = false
    @Published var exclusions: [String] = []
    @Published var manualExclusions: [String] = []
    @Published var smartGraph = SmartExclusionGraph()
    @Published var health: [UUID: ProfileHealth] = [:]
    @Published var isScanningProfiles = false
    @Published var lastProfileScanSummary = ""
    @Published var events: [TunnelEvent] = []
    @Published var errorMessage: String?

    let vpn = VPNController()
    private let store: ProfileStore
    private let telemetry = TelemetryStore()
    private var cancellables: Set<AnyCancellable> = []
    private var healthScanGeneration = 0
    private let profileScanPolicy = ProfileScanPolicy()
    private var lastAutomaticScanAt: Date?
    private var lastManualScanAt: Date?
    private var manualScanCursor = 0

    init() {
        do {
            store = try ProfileStore()
#if DEBUG && targetEnvironment(simulator)
            // Explicit disposable-simulator fixture for the system Files
            // export/import QA. Never compiled into Release or a real iPhone,
            // never creates a live proxy or exercises a paid endpoint.
            if ProcessInfo.processInfo.arguments.contains("-aplBackupFilesQA"),
               !store.listProfiles().contains(where: { $0.name == "Synthetic Files QA" }) {
                let fixture = ProxyProfile(name: "Synthetic Files QA",
                    host: "apl-files-qa.invalid", port: 8181, type: .http,
                    username: "synthetic")
                try store.save(fixture, password: "test-only-secret", makeActive: false)
            }
#endif

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
        profileOrganization = store.profileOrganization
        // Removing a profile must not leave obsolete diagnostics in memory.
        let currentIDs = Set(profiles.map(\.id))
        health = health.filter { currentIDs.contains($0.key) }
        for (id, latency) in store.proxyQuality.freshLatencies(for: currentIDs) where health[id] == nil {
            health[id] = .available(latency)
        }
        selectedProfileID = store.selectedProfileID
        automaticSelection = store.automaticSelection
        primaryProfileID = store.primaryProfileID
        returnToPrimary = store.restorePolicy == .returnToPrimary
        exclusions = store.siteExclusions
        manualExclusions = store.manualSiteExclusions
        smartGraph = store.smartGraph
        refreshEvents()
    }

    func toggleFavorite(_ id: UUID) {
        var updated = profileOrganization
        updated.toggleFavorite(id)
        store.profileOrganization = updated
        profileOrganization = store.profileOrganization
    }

    func setFavorites(_ ids: Set<UUID>, enabled: Bool) {
        var updated = profileOrganization
        updated.setFavorite(enabled, for: ids)
        store.profileOrganization = updated
        profileOrganization = store.profileOrganization
    }

    func assignProfileGroup(_ name: String?, to ids: Set<UUID>) {
        var updated = profileOrganization
        updated.assignGroup(name, to: ids)
        store.profileOrganization = updated
        profileOrganization = store.profileOrganization
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
        password: String,
        scanAfterSave: Bool = true,
        activateOnCreate: Bool = true
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
                makeActive: (!isEditing && activateOnCreate) || (isEditing && selectedProfileID == editingID),
                preservePasswordIfNil: isEditing && password.isEmpty
            )
            refresh()
            if scanAfterSave { Task { await scanProfiles() } }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Export is all-or-nothing: an inaccessible Keychain item aborts the
    /// operation rather than silently omitting a password from the backup.
    func createEncryptedProfileBackup(password: String) throws -> Data {
        let snapshot = store.listProfiles()
        let entries = try snapshot.map { profile in
            BackupProfile(profile: profile, password: try store.password(for: profile.id))
        }
        let organization = store.profileOrganization
        return try ProfileBackupCodec.seal(
            ProfileBackupPayload(profiles: entries, favorites: organization.favorites,
                                 groups: organization.groups), password: password
        )
    }

    /// Only new UUIDs are inserted. The current VPN, selected server, Auto
    /// preference and every existing Keychain secret remain untouched.
    func restoreEncryptedProfileBackup(data: Data, password: String) throws -> Int {
        guard !vpn.isConnectedOrConnecting else {
            throw ProfileBackupError.vpnActive
        }
        let payload = try ProfileBackupCodec.open(data, password: password)
        let existing = store.listProfiles()
        let plan = try ProfileBackupRestorePlan(payload: payload, existing: existing)
        guard !plan.entries.isEmpty else { return 0 }
        var createdIDs: [UUID] = []
        do {
            for entry in plan.entries {
                try store.save(entry.profile, password: entry.password, makeActive: false)
                createdIDs.append(entry.profile.id)
            }
        } catch {
            var rollbackComplete = true
            for id in createdIDs.reversed() {
                do { try store.delete(id: id) }
                catch { rollbackComplete = false }
            }
            refresh()
            if !rollbackComplete { throw ProfileBackupError.partialRollback }
            throw error
        }
        var updated = store.profileOrganization
        updated.setFavorite(true, for: plan.favorites)
        for (id, group) in plan.groups {
            updated.assignGroup(group, to: [id])
        }
        store.profileOrganization = updated
        if existing.isEmpty, let firstID = createdIDs.first {
            store.selectedProfileID = firstID
            store.automaticSelection = false
        }
        refresh()
        return createdIDs.count
    }

    /// A failed import can roll back only newly created IDs, even if an
    /// unrelated existing VPN session remains connected. No previous profile
    /// or Keychain credential is ever changed by this rollback.
    func rollbackImportedProfiles(ids: Set<UUID>) -> Bool {
        var allRemoved = true
        for id in ids where profiles.contains(where: { $0.id == id }) {
            do { try store.delete(id: id) }
            catch { allRemoved = false }
        }
        refresh()
        return allRemoved
    }

    /// Returns only IDs that were actually removed; failed deletions stay
    /// selected in the UI so partial failures are visible and retryable.
    func deleteProfiles(ids: Set<UUID>) -> Set<UUID> {
        guard !vpn.isConnectedOrConnecting else {
            errorMessage = "Отключите VPN перед удалением профилей"
            return []
        }
        var removed: Set<UUID> = []
        var firstError: Error?
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) where profiles.contains(where: { $0.id == id }) {
            do {
                try store.delete(id: id)
                removed.insert(id)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        refresh()
        if let firstError {
            errorMessage = "Не все профили удалены: " + firstError.localizedDescription
        }
        return removed
    }

    func deleteProfile(id: UUID) {
        guard !vpn.isConnectedOrConnecting else {
            errorMessage = "Отключите VPN перед удалением профилей"
            return
        }
        do { try store.delete(id: id); refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ profile: ProxyProfile) {
        deleteProfile(id: profile.id)
    }

    func saveExclusions(_ raw: [String], graph: SmartExclusionGraph? = nil) async -> Bool {
        do {
            let manual = try SiteExclusionPolicy.normalizeAll(raw)
            let nextGraph = (graph ?? smartGraph).pruned()
            let effective = try nextGraph.effective(manual: manual)
            let previousManual = store.manualSiteExclusions
            let previousGraph = store.smartGraph
            let previouslyActive = vpn.isConnectedOrConnecting
            try store.saveSmartExclusions(manual: manual, graph: nextGraph)
            do {
                try await vpn.reconnectIfActive()
            } catch {
                // Do not leave the new bypass rules persisted after a failed
                // activation; preserve both previous manual and graph state.
                let activationError = error
                do {
                    try store.saveSmartExclusions(manual: previousManual, graph: previousGraph)
                } catch {
                    errorMessage = "VPN: не удалось восстановить прежние исключения. " + error.localizedDescription
                    return false
                }
                exclusions = store.siteExclusions
                manualExclusions = previousManual
                smartGraph = previousGraph
                if previouslyActive {
                    do {
                        try await vpn.restoreAfterFailedExclusionsUpdate()
                    } catch {
                        errorMessage = "Прежние исключения восстановлены, но VPN нужно подключить заново: " + error.localizedDescription
                        return false
                    }
                }
                throw activationError
            }
            exclusions = effective
            manualExclusions = manual
            smartGraph = nextGraph
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
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-aplEphemeralTunnelQA") {
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    self?.vpn.disconnect()
                }
            }
#endif
        } catch {
            // Preserve the actionable NetworkExtension explanation but
            // identify system tunnel failures unambiguously in the alert.
            let kind = ProxyFailureReason.classify(error)
            errorMessage = kind == .tunnel
                ? "VPN: " + error.localizedDescription
                : error.localizedDescription
        }
    }

    func scanProfiles(manual: Bool = false, specificIDs: Set<UUID>? = nil) async {
        // Never launch overlapping network scans. Imported lists can contain
        // 200 paid proxies, so startup only checks 3 prioritized entries.
        guard !isScanningProfiles else { return }
        let now = Date()
        guard profileScanPolicy.permitted(
            now: now,
            lastScan: manual ? lastManualScanAt : lastAutomaticScanAt,
            manual: manual
        ) else {
            if manual { lastProfileScanSummary = AppL10n.tr("Между ручными проверками подождите 10 секунд.") }
            return
        }
        let snapshot = profiles
        guard !snapshot.isEmpty else { health = [:]; return }
        let ids: [UUID]
        if let specificIDs {
            ids = profileScanPolicy.selectedBatch(ids: snapshot.map(\.id), selected: specificIDs)
            guard !ids.isEmpty else {
                lastProfileScanSummary = AppL10n.tr("Выберите от 1 до 10 профилей")
                return
            }
        } else {
            ids = profileScanPolicy.batch(
                ids: snapshot.map(\.id), selectedID: selectedProfileID,
                primaryID: primaryProfileID, favorites: profileOrganization.favorites,
                manualCursor: manual ? manualScanCursor : nil
            )
        }
        if manual {
            lastManualScanAt = now
            if specificIDs == nil { manualScanCursor = (manualScanCursor + ids.count) % snapshot.count }
        } else {
            lastAutomaticScanAt = now
        }
        isScanningProfiles = true
        defer { isScanningProfiles = false }
        healthScanGeneration &+= 1
        let generation = healthScanGeneration
        let probe = ProxyProbe()
        var quality = store.proxyQuality
        var checked = 0
        for id in ids {
            guard generation == healthScanGeneration, !Task.isCancelled else { break }
            guard let profile = snapshot.first(where: { $0.id == id }),
                  profiles.contains(where: { $0.id == id }) else { continue }
            health[id] = .checking
            do {
                let result = try await probe.resolveMeasured(profile, password: try store.password(for: id))
                guard generation == healthScanGeneration, profiles.contains(where: { $0.id == id }) else { break }
                health[id] = .available(result.latencyMs)
                quality.markAvailable(id, latencyMs: result.latencyMs)
            } catch {
                guard generation == healthScanGeneration, profiles.contains(where: { $0.id == id }) else { break }
                health[id] = .unavailable(ProxyFailureReason.classify(error))
                quality.markUnavailable(id)
            }
            checked += 1
        }
        quality.prune(keeping: Set(profiles.map(\.id)))
        store.proxyQuality = quality
        lastProfileScanSummary = String(format: AppL10n.tr("Проверено %d из %d профилей"),
                                        checked, specificIDs == nil ? snapshot.count : ids.count)
    }

    func refreshEvents() {
        events = telemetry.list()
    }
}
