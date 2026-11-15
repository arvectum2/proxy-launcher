import Foundation
import Security

/// Inactive adapter. Existing shared entitlement, distinct services and
/// device-only items. No fallback to legacy credentials or cloud sync.
struct NativeCredentialKeychain: NativeCredentialItems {
    enum Purpose: String { case revision = "native-revision.v1", handoff = "native-handoff.v1" }
    enum Failure: Error { case configuration, status(OSStatus) }
    let purpose: Purpose
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
                kSecAttrService as String: "ru.arvectum.proxylauncher.ios."+purpose.rawValue,
                kSecAttrAccount as String:account, kSecAttrAccessGroup as String:group,
                kSecAttrSynchronizable as String:false]
    }
    func insert(account: String, bytes: Data) throws {
        guard !bytes.isEmpty, bytes.count <= 48_000 else { throw Failure.configuration }
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
        guard status == errSecSuccess, let bytes = result as? Data, bytes.count <= 48_000 else { throw Failure.status(status) }
        return bytes
    }
    func remove(account: String) throws -> Bool {
        let status = SecItemDelete(try query(account) as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw Failure.status(status) }
        return true
    }
}
