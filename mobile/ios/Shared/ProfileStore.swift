import Foundation
import Security

enum ProfileStoreError: LocalizedError {
    case noSharedDefaults
    case encodeFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noSharedDefaults: return "Не удалось открыть общее хранилище приложения"
        case .encodeFailed: return "Не удалось сохранить профиль"
        case .keychain(let status): return "Keychain error: \(status)"
        }
    }
}

enum IOSAppRoutingMode: String, CaseIterable, Identifiable {
    case normallyOn
    case normallyOff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normallyOn: return "APL обычно включён"
        case .normallyOff: return "APL обычно выключен"
        }
    }
}

final class ProfileStore {
    private enum Key {
        static let profiles = "profiles.v1"
        static let selectedProfileID = "selected_profile_id"
        static let automaticSelection = "automatic_selection"
        static let primaryProfileID = "primary_profile_id"
        static let restorePolicy = "restore_policy"
        static let exclusions = "site_exclusions"
        static let lastAutoProfileID = "last_auto_profile_id"
        static let recentlyFailedProfileID = "recently_failed_profile_id"
        static let recentlyFailedAt = "recently_failed_at"
        static let lastFailoverAt = "last_failover_at"
        static let iosAppRoutingMode = "ios_app_routing_mode"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() throws {
        guard let defaults = UserDefaults(suiteName: AppShared.defaultsSuite) else {
            throw ProfileStoreError.noSharedDefaults
        }
        self.defaults = defaults
    }

    func listProfiles() -> [ProxyProfile] {
        guard let data = defaults.data(forKey: Key.profiles),
              let profiles = try? decoder.decode([ProxyProfile].self, from: data) else { return [] }
        return profiles.sorted {
            let lhs = $0.name.localizedCaseInsensitiveCompare($1.name)
            return lhs == .orderedSame ? $0.id.uuidString < $1.id.uuidString : lhs == .orderedAscending
        }
    }

    func profile(id: UUID) -> ProxyProfile? {
        listProfiles().first { $0.id == id }
    }

    func password(for id: UUID) throws -> String? {
        var query = baseKeychainQuery(id: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ProfileStoreError.keychain(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func save(_ profile: ProxyProfile, password: String?, makeActive: Bool = true, preservePasswordIfNil: Bool = false) throws {
        var profiles = listProfiles()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        guard let data = try? encoder.encode(profiles) else { throw ProfileStoreError.encodeFailed }
        defaults.set(data, forKey: Key.profiles)
        if !(preservePasswordIfNil && password == nil) { try setPassword(password, for: profile.id) }
        if makeActive {
            defaults.set(profile.id.uuidString, forKey: Key.selectedProfileID)
            defaults.set(false, forKey: Key.automaticSelection)
        }
        if primaryProfileID == nil { primaryProfileID = profile.id }
    }

    func delete(id: UUID) throws {
        let remaining = listProfiles().filter { $0.id != id }
        guard let data = try? encoder.encode(remaining) else { throw ProfileStoreError.encodeFailed }
        defaults.set(data, forKey: Key.profiles)
        try setPassword(nil, for: id)
        if selectedProfileID == id { selectedProfileID = remaining.first?.id }
        if primaryProfileID == id { primaryProfileID = remaining.first?.id }
        if lastAutoProfileID == id { lastAutoProfileID = nil }
        if recentlyFailedProfileID == id { clearRecentlyFailed() }
    }

    var selectedProfileID: UUID? {
        get { uuid(forKey: Key.selectedProfileID) }
        set { setUUID(newValue, forKey: Key.selectedProfileID) }
    }

    var automaticSelection: Bool {
        get { defaults.bool(forKey: Key.automaticSelection) }
        set { defaults.set(newValue, forKey: Key.automaticSelection) }
    }

    var primaryProfileID: UUID? {
        get { uuid(forKey: Key.primaryProfileID) ?? listProfiles().first?.id }
        set { setUUID(newValue, forKey: Key.primaryProfileID) }
    }

    var restorePolicy: PrimaryRestorePolicy {
        get { PrimaryRestorePolicy(rawValue: defaults.string(forKey: Key.restorePolicy) ?? "") ?? .stayOnCurrent }
        set { defaults.set(newValue.rawValue, forKey: Key.restorePolicy) }
    }

    var siteExclusions: [String] {
        get { defaults.stringArray(forKey: Key.exclusions) ?? [] }
        set { defaults.set(newValue, forKey: Key.exclusions) }
    }

    var iosAppRoutingMode: IOSAppRoutingMode {
        get { IOSAppRoutingMode(rawValue: defaults.string(forKey: Key.iosAppRoutingMode) ?? "") ?? .normallyOn }
        set { defaults.set(newValue.rawValue, forKey: Key.iosAppRoutingMode) }
    }

    var lastAutoProfileID: UUID? {
        get { uuid(forKey: Key.lastAutoProfileID) }
        set { setUUID(newValue, forKey: Key.lastAutoProfileID) }
    }

    var recentlyFailedProfileID: UUID? {
        get { uuid(forKey: Key.recentlyFailedProfileID) }
        set { setUUID(newValue, forKey: Key.recentlyFailedProfileID) }
    }

    var recentlyFailedAt: Date? {
        get { defaults.object(forKey: Key.recentlyFailedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.recentlyFailedAt) }
    }

    var lastFailoverAt: Date? {
        get { defaults.object(forKey: Key.lastFailoverAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastFailoverAt) }
    }

    func configuration() -> TunnelConfiguration {
        TunnelConfiguration(
            selectedProfileID: selectedProfileID,
            automaticSelection: automaticSelection,
            primaryProfileID: primaryProfileID,
            restorePolicy: restorePolicy,
            siteExclusions: siteExclusions,
            lastAutoProfileID: lastAutoProfileID,
            recentlyFailedProfileID: recentlyFailedProfileID,
            recentlyFailedAt: recentlyFailedAt,
            lastFailoverAt: lastFailoverAt
        )
    }

    func markRecentlyFailed(_ id: UUID, at: Date = Date()) {
        recentlyFailedProfileID = id
        recentlyFailedAt = at
    }

    func clearRecentlyFailed() {
        recentlyFailedProfileID = nil
        recentlyFailedAt = nil
    }

    private func setPassword(_ password: String?, for id: UUID) throws {
        let query = baseKeychainQuery(id: id)
        SecItemDelete(query as CFDictionary)
        guard let password, !password.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(password.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw ProfileStoreError.keychain(status) }
    }

    private func baseKeychainQuery(id: UUID) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppShared.keychainService,
            kSecAttrAccount as String: id.uuidString,
        ]
        if let group = AppShared.keychainAccessGroup, !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    private func uuid(forKey key: String) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    private func setUUID(_ value: UUID?, forKey key: String) {
        if let value { defaults.set(value.uuidString, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}
