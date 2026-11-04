import CommonCrypto
import CryptoKit
import Foundation
import Security

/// The exported file contains no readable server names, accounts or passwords.
struct BackupProfile: Codable, Equatable {
    let profile: ProxyProfile
    let password: String?
}

struct ProfileBackupPayload: Codable, Equatable {
    let profiles: [BackupProfile]
    let favorites: Set<UUID>
    let groups: [UUID: String]
}

enum ProfileBackupError: LocalizedError {
    case weakPassword, invalidFile, authenticationFailed, tooManyProfiles, encryptionFailed, partialRollback, vpnActive

    var errorDescription: String? {
        switch self {
        case .weakPassword: return "Пароль резервной копии должен содержать не менее 12 символов"
        case .invalidFile: return "Файл резервной копии повреждён или имеет неподдерживаемый формат"
        case .authenticationFailed: return "Неверный пароль или повреждённая резервная копия"
        case .tooManyProfiles: return "Слишком много прокси для резервной копии (максимум 200)"
        case .encryptionFailed: return "Не удалось безопасно зашифровать резервную копию"
        case .partialRollback: return "Восстановление прервано; часть новых профилей не удалось удалить"
        case .vpnActive: return "Отключите VPN перед восстановлением резервной копии"
        }
    }
}

private struct ProfileBackupEnvelope: Codable {
    let format: String
    let version: Int
    let kdf: String
    let iterations: Int
    let salt: Data
    let ciphertext: Data
}

enum ProfileBackupCodec {
    static let maxProfiles = 200
    static let maxFileBytes = 1_048_576
    private static let magic = "arvectum.apl.encrypted-profiles"
    private static let iterations = 210_000
    private static let saltSize = 16
    private static let keySize = 32

    static func seal(_ payload: ProfileBackupPayload, password: String) throws -> Data {
        try validatePassword(password)
        try validatePayload(payload)
        let plaintext = try JSONEncoder().encode(payload)
        guard plaintext.count <= maxFileBytes / 2 else { throw ProfileBackupError.invalidFile }
        var salt = Data(count: saltSize)
        let randomStatus = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw ProfileBackupError.encryptionFailed }
        let key = try deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw ProfileBackupError.encryptionFailed }
        let container = ProfileBackupEnvelope(format: magic, version: 1,
                                             kdf: "PBKDF2-HMAC-SHA256", iterations: iterations,
                                             salt: salt, ciphertext: combined)
        let result = try JSONEncoder().encode(container)
        guard result.count <= maxFileBytes else { throw ProfileBackupError.invalidFile }
        return result
    }

    static func open(_ data: Data, password: String) throws -> ProfileBackupPayload {
        // Reject malformed input before expensive password derivation.
        guard data.count <= maxFileBytes, data.count >= 64,
              let envelope = try? JSONDecoder().decode(ProfileBackupEnvelope.self, from: data),
              envelope.format == magic, envelope.version == 1,
              envelope.kdf == "PBKDF2-HMAC-SHA256", envelope.iterations == iterations,
              envelope.salt.count == saltSize,
              (28...maxFileBytes).contains(envelope.ciphertext.count) else {
            throw ProfileBackupError.invalidFile
        }
        // A pasted import passphrase is untrusted user input as well. Bound it
        // before running PBKDF2, just like the export path.
        try validatePassword(password)
        let key = try deriveKey(password: password, salt: envelope.salt)
        let plaintext: Data
        do {
            let sealed = try AES.GCM.SealedBox(combined: envelope.ciphertext)
            plaintext = try AES.GCM.open(sealed, using: key)
        } catch {
            throw ProfileBackupError.authenticationFailed
        }
        guard plaintext.count <= maxFileBytes / 2,
              let payload = try? JSONDecoder().decode(ProfileBackupPayload.self, from: plaintext) else {
            throw ProfileBackupError.invalidFile
        }
        try validatePayload(payload)
        return payload
    }

    private static func validatePassword(_ password: String) throws {
        guard (12...512).contains(password.count), !password.utf8.contains(0) else {
            throw ProfileBackupError.weakPassword
        }
    }

    private static func validatePayload(_ payload: ProfileBackupPayload) throws {
        guard !payload.profiles.isEmpty, payload.profiles.count <= maxProfiles else {
            throw ProfileBackupError.tooManyProfiles
        }
        let ids = payload.profiles.map(\.profile.id)
        guard Set(ids).count == ids.count else { throw ProfileBackupError.invalidFile }
        for item in payload.profiles {
            let profile = item.profile
            let host = profile.host
            guard !host.isEmpty, host.utf8.count <= 255,
                  !host.contains(where: { $0.isWhitespace || $0.isNewline }),
                  !host.contains("@"), !host.contains("/"), !host.contains("?"),
                  (1...65535).contains(profile.port),
                  profile.name.utf8.count <= 512,
                  (profile.username?.utf8.count ?? 0) <= 512,
                  (item.password?.utf8.count ?? 0) <= 4096 else {
                throw ProfileBackupError.invalidFile
            }
        }
        let idSet = Set(ids)
        guard payload.favorites.isSubset(of: idSet),
              Set(payload.groups.keys).isSubset(of: idSet),
              payload.groups.values.allSatisfy({ $0.utf8.count <= 160 }) else {
            throw ProfileBackupError.invalidFile
        }
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        var key = Data(count: keySize)
        let status = password.withCString { passwordPointer in
            salt.withUnsafeBytes { saltBuffer in
                key.withUnsafeMutableBytes { keyBuffer in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                        passwordPointer, password.utf8.count,
                                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                                        salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                        UInt32(iterations),
                                        keyBuffer.bindMemory(to: UInt8.self).baseAddress,
                                        keySize)
                }
            }
        }
        guard status == kCCSuccess else { throw ProfileBackupError.encryptionFailed }
        return SymmetricKey(data: key)
    }
}
