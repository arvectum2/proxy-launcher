import Foundation
import Security

struct SavedProxySubscription: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let providerHost: String
    let createdAt: Date
    var refresh: SubscriptionRefreshSettings? = nil
    var lastAttempt: Date? = nil
}

/// An absent policy is always manual. An opt-in never immediately requests data.
struct SubscriptionRefreshSettings: Codable, Equatable {
    enum Interval: String, Codable, CaseIterable, Identifiable {
        case manual, hourly, daily, weekly
        var id: String { rawValue }
        var seconds: TimeInterval? {
            switch self {case .manual:return nil;case .hourly:return 3600;case .daily:return 86400;case .weekly:return 604800}
        }
    }
    let interval: Interval
    let defaultType: ProxyType
    func isDue(lastAttempt: Date?, now: Date = Date()) -> Bool {
        guard let seconds=interval.seconds,let lastAttempt,defaultType != .auto else{return false}
        let age=now.timeIntervalSince(lastAttempt)
        return age.isFinite && age>=seconds
    }
}

enum ProxySubscriptionStoreError: Error {
    case storageUnavailable, corruptMetadata, tooMany, invalidTitle, keychain(OSStatus)
}

/// Provider source URLs may contain a paid subscription bearer token in their
/// query. Persist only display metadata in App Group, and store the full
/// source URL in a separate Keychain service with ThisDeviceOnly protection.
/// Unlike source-only signed managed manifests, this is user-approved
/// manual or explicitly opted-in foreground refresh; it never rewrites profiles or changes the active VPN.
final class ProxySubscriptionStore {
    private static let metadataKey = "proxy_subscriptions.v1"
    private static let service = "ru.arvectum.proxylauncher.ios.subscription.source.v1"
    private static let maxSaved = 12
    private let defaults: UserDefaults

    init() throws {
        guard let defaults = UserDefaults(suiteName: AppShared.defaultsSuite) else {
            throw ProxySubscriptionStoreError.storageUnavailable
        }
        self.defaults = defaults
    }

    func list() throws -> [SavedProxySubscription] {
        guard let bytes = defaults.data(forKey: Self.metadataKey) else { return [] }
        guard bytes.count <= 32 * 1024,
              let saved = try? JSONDecoder().decode([SavedProxySubscription].self, from: bytes),
              saved.count <= Self.maxSaved,
              Set(saved.map(\.id)).count == saved.count,
              saved.allSatisfy({$0.refresh?.defaultType != .auto && ($0.refresh == nil || $0.lastAttempt != nil)}) else {
            throw ProxySubscriptionStoreError.corruptMetadata
        }
        return saved
    }

    @discardableResult
    func add(title: String, urlText: String) throws -> SavedProxySubscription {
        let source = try ProxySubscriptionImport.sourceURL(urlText)
        var saved = try list()
        guard saved.count < Self.maxSaved else { throw ProxySubscriptionStoreError.tooMany }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = name.isEmpty ? (source.host ?? "") : name
        guard !caption.isEmpty, caption.utf8.count <= 64,
              !caption.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ProxySubscriptionStoreError.invalidTitle
        }
        let entry = SavedProxySubscription(id: UUID(), title: caption,
                                           providerHost: source.host ?? "", createdAt: Date())
        saved.append(entry)
        guard let encoded = try? JSONEncoder().encode(saved), encoded.count <= 32 * 1024 else {
            throw ProxySubscriptionStoreError.corruptMetadata
        }
        var item = baseQuery(for: entry.id)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecValueData as String] = Data(source.absoluteString.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw ProxySubscriptionStoreError.keychain(status) }
        defaults.set(encoded, forKey: Self.metadataKey)
        return entry
    }

    func configureRefresh(_ id:UUID, interval:SubscriptionRefreshSettings.Interval, defaultType:ProxyType, now:Date=Date())throws {
        guard defaultType != .auto else{throw ProxySubscriptionStoreError.corruptMetadata}
        var saved=try list();guard let index=saved.firstIndex(where:{$0.id==id}) else{throw ProxySubscriptionStoreError.corruptMetadata}
        saved[index].refresh=interval == .manual ? nil:.init(interval:interval,defaultType:defaultType)
        saved[index].lastAttempt=interval == .manual ? nil:now
        try writeMetadata(saved)
    }
    /// Reserve the attempt before any network operation, including failure.
    /// No automatic retry storm on provider or Keychain errors.
    func claimDue(_ expected:SavedProxySubscription, now:Date=Date())throws->SavedProxySubscription? {
        var saved=try list();guard let index=saved.firstIndex(where:{$0.id==expected.id}),saved[index]==expected,
          let policy=expected.refresh,policy.isDue(lastAttempt:expected.lastAttempt,now:now) else{return nil}
        saved[index].lastAttempt=now;try writeMetadata(saved);return saved[index]
    }
    func markManualAttempt(_ expected:SavedProxySubscription, now:Date=Date())throws->SavedProxySubscription {
        var saved=try list();guard let index=saved.firstIndex(where:{$0.id==expected.id}),saved[index]==expected else{throw ProxySubscriptionStoreError.corruptMetadata}
        guard expected.refresh != nil else{return expected}
        saved[index].lastAttempt=now;try writeMetadata(saved);return saved[index]
    }
    private func writeMetadata(_ entries:[SavedProxySubscription])throws {
        let data=try JSONEncoder().encode(entries);guard data.count<=32*1024 else{throw ProxySubscriptionStoreError.corruptMetadata};defaults.set(data,forKey:Self.metadataKey)
    }
    func source(for id: UUID) throws -> URL {
        guard try list().contains(where: { $0.id == id }) else {
            throw ProxySubscriptionStoreError.corruptMetadata
        }
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let urlText = String(data: data, encoding: .utf8) else {
            throw ProxySubscriptionStoreError.keychain(status)
        }
        return try ProxySubscriptionImport.sourceURL(urlText)
    }

    func remove(_ id: UUID) throws {
        let old = try list()
        guard old.contains(where: { $0.id == id }) else { return }
        let updated = old.filter { $0.id != id }
        guard let encoded = try? JSONEncoder().encode(updated) else {
            throw ProxySubscriptionStoreError.corruptMetadata
        }
        let status = SecItemDelete(baseQuery(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProxySubscriptionStoreError.keychain(status)
        }
        defaults.set(encoded, forKey: Self.metadataKey)
    }

    private func baseQuery(for id: UUID) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id.uuidString,
        ]
        if let group = AppShared.keychainAccessGroup, !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
}
