import Foundation

/// Privacy-safe user messages for local profile CRUD failures.
///
/// Keychain and profile-store errors may include OSStatus, file paths or
/// storage details. Keep them in the error layer, never in the visible UI.
enum ProfileMutationUX {
    static var saveFailed: String {
        AppL10n.tr("Не удалось сохранить профиль")
    }

    static var bulkDeleteFailed: String {
        // Existing translated key has a trailing colon because it previously
        // introduced an unsafe NSError description. Remove only punctuation.
        AppL10n.tr("Не все профили удалены:", table: "ProfileManagement")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n:："))
    }

    static var disconnectVPNBeforeDelete: String {
        AppL10n.tr("Отключите VPN перед удалением профилей", table: "ProfileManagement")
    }

    static var singleDeleteFailed: String {
        AppL10n.effectiveLanguage == "ru"
            ? "Не удалось удалить профиль."
            : "Could not delete the proxy profile."
    }
}
