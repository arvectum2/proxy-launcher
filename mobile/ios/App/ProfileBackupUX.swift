import Foundation

/// ProfileBackupError uses vetted, already-translated ProfileManagement keys.
/// Never display errors from Files, Keychain, CryptoKit, or security scopes
/// verbatim: they may contain file paths or internal storage diagnostics.
enum ProfileBackupUX {
    enum Operation {
        case exportFile
        case importFile
        case createBackup
        case restoreBackup
    }

    static func message(_ error: Error, operation: Operation) -> String {
        if let failure = error as? ProfileBackupError,
           let safeKey = failure.errorDescription {
            return AppL10n.tr(safeKey, table: "ProfileManagement")
        }

        // Unclassified platform errors have no user-safe, translatable key.
        // Use stable actionable wording, without echoing arbitrary NSError.
        // Existing seven typed failures have genuine 64-locale translations.
        let russian = AppL10n.effectiveLanguage == "ru"
        switch operation {
        case .exportFile:
            return russian
                ? "Не удалось сохранить файл копии. Выберите другое место."
                : "Could not save the backup file. Choose another location."
        case .importFile:
            return russian
                ? "Не удалось прочитать выбранный файл резервной копии."
                : "Could not read the selected backup file."
        case .createBackup:
            return russian
                ? "Не удалось создать зашифрованную копию."
                : "Could not create the encrypted backup."
        case .restoreBackup:
            return russian
                ? "Не удалось восстановить профили из копии."
                : "Could not restore profiles from the backup."
        }
    }
}
