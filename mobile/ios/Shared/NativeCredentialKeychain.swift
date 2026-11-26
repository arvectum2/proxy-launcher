import Foundation
import Security

/// Inactive adapter. Existing shared entitlement, distinct services and
/// device-only items. No fallback to legacy credentials or cloud sync.
struct NativeCredentialKeychain: NativeCredentialItems {
    enum Purpose: String { case revision = "native-revision.v1", handoff = "native-handoff.v1" }
    enum Failure: Error { case configuration, status(OSStatus) }
    let purpose: Purpose
    private var maxBytes: Int { purpose == .revision ? NativeCredentialRecord.maxBytes : NativeCredentialHandoff.maxEnvelopeBytes }
    private func query(_ account: String) throws -> [String:Any] {
        let parts = account.split(separator:"/",omittingEmptySubsequences:false).map(String.init)
        let valid: Bool
        switch purpose {
        case .revision:
            valid = parts.count == 4 && parts[0] == "record-v1" && UUID(uuidString:parts[1]) != nil && UUID(uuidString:parts[2]) != nil && NativeCredentialRecord.Kind(rawValue:parts[3]) != nil
        case .handoff:
            valid = parts.count == 2 && parts[0] == "handoff-v1" && UUID(uuidString:parts[1]) != nil
        }
        guard valid, account.count <= 128, let group = AppShared.keychainAccessGroup, !group.isEmpty else { throw Failure.configuration }
        return [kSecClass as String:kSecClassGenericPassword,
                kSecAttrService as String: AppShared.nativeCredentialServicePrefix+purpose.rawValue,
                kSecAttrAccount as String:account, kSecAttrAccessGroup as String:group,
                kSecAttrSynchronizable as String:false]
    }
    func insert(account: String, bytes: Data) throws {
        guard !bytes.isEmpty, bytes.count <= maxBytes else { throw Failure.configuration }
        var q = try query(account)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        q[kSecValueData as String] = bytes
        let status = SecItemAdd(q as CFDictionary,nil)
        guard status == errSecSuccess else { throw Failure.status(status) }
    }
    func read(account: String) throws -> Data? {
        var q = try query(account)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = result as? Data, !bytes.isEmpty, bytes.count <= maxBytes else { throw Failure.status(status) }
        return bytes
    }
    /// Attributes only, exact handoff service/group and device-local items.
    /// The OS enumerates the matching metadata; caller limits deletion work.
    /// Not used by production startup and never queries revision records.
    func handoffAccountsForValidation() throws -> [String] {
        guard purpose == .handoff else {throw Failure.configuration}
        var q = try query("handoff-v1/"+UUID().uuidString)
        q.removeValue(forKey:kSecAttrAccount as String)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status=SecItemCopyMatching(q as CFDictionary,&result)
        if status==errSecItemNotFound {return []}
        guard status==errSecSuccess,let rows=result as? [[String:Any]] else {throw Failure.status(status)}
        let accounts=try rows.map { row -> String in
            guard let name=row[kSecAttrAccount as String] as? String else {throw Failure.configuration}
            _=try query(name)
            return name
        }
        guard Set(accounts).count==accounts.count else {throw Failure.configuration}
        return accounts.sorted()
    }
    func remove(account: String) throws -> Bool {
        let status = SecItemDelete(try query(account) as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw Failure.status(status) }
        return true
    }
}

/// One metadata item, written by the app only. No migration or activation.
struct NativeCredentialCatalogKeychain: NativeCredentialCatalogStorage {
    private func query() throws -> [String:Any] {
        guard let group = AppShared.keychainAccessGroup, !group.isEmpty else { throw NativeCredentialKeychain.Failure.configuration }
        return [kSecClass as String:kSecClassGenericPassword,
                kSecAttrService as String:AppShared.nativeCredentialServicePrefix+"native-catalog.v1",
                kSecAttrAccount as String:"catalog-v1", kSecAttrAccessGroup as String:group,
                kSecAttrSynchronizable as String:false]
    }
    func load() throws -> Data? {
        var q = try query()
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = result as? Data, bytes.count <= 32_768 else { throw NativeCredentialKeychain.Failure.status(status) }
        return bytes
    }
    #if APL_PRODUCT_OWNER_QA
    func qaRemoveEmptyCatalog()throws {
        let snapshot=try NativeCredentialCatalogReader(storage:self).snapshot()
        guard snapshot.current.isEmpty,snapshot.retired.isEmpty,snapshot.selected==nil,!snapshot.hasPendingWrite else{throw NativeCredentialKeychain.Failure.configuration}
        let status=SecItemDelete(try query() as CFDictionary)
        guard status==errSecSuccess || status==errSecItemNotFound else{throw NativeCredentialKeychain.Failure.status(status)}
    }
    #endif
    func replace(_ bytes: Data) throws {
        guard !bytes.isEmpty, bytes.count <= 32_768 else { throw NativeCredentialKeychain.Failure.configuration }
        var q = try query()
        let status = SecItemUpdate(q as CFDictionary,[kSecValueData as String:bytes] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw NativeCredentialKeychain.Failure.status(status) }
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        q[kSecValueData as String] = bytes
        let add = SecItemAdd(q as CFDictionary,nil)
        guard add == errSecSuccess else { throw NativeCredentialKeychain.Failure.status(add) }
    }
}

/// Both processes use the same current selection. Inactive validation-only.
extension NativeCredentialHandoff {
    static func localDeviceValidation() -> Self {
        let reader = NativeCredentialCatalogReader(storage:NativeCredentialCatalogKeychain())
        return Self(items:NativeCredentialKeychain(purpose:.handoff),
                    repository:NativeCredentialRepository(items:NativeCredentialKeychain(purpose:.revision)),
                    authorizes:{ try reader.authorizes($0) })
    }
}
