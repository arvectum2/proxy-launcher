import Foundation

/// Presentation-only Smart Exclusions diagnostics; never pass untrusted
/// storage/NetworkExtension exception text to the user.
enum SiteExclusionSaveUX {
    static func failed(_ error: Error) -> String {
        let reason = SiteExclusionSaveFailure.classify(error)
        if let key = reason.translatedGraphKey {
            return AppL10n.tr(key, table: "SmartExclusions")
        }
        // If the update was rejected by the VPN subsystem, show only an
        // existing, translated fixed-code connection recovery message.
        let network = ProxyFailureReason.classify(error)
        if network != .unknown {
            return ProxyFailureReason.safeDisplay(
                for: error, translate: { AppL10n.tr($0) })
        }
        return AppL10n.effectiveLanguage == "ru"
            ? reason.russianFallback : reason.englishFallback
    }

    static func rollbackFailed() -> String {
        AppL10n.tr("VPN: не удалось восстановить прежние исключения.",
                   table: "ProfileManagement")
    }

    static func reconnectNeeded(_ error: Error) -> String {
        let key = "Прежние исключения восстановлены, но VPN нужно подключить заново:"
        // Exact codes contain no host, credentials or filesystem paths.
        let code = ProxyFailureReason.classify(error).code
        return AppL10n.tr(key, table: "ProfileManagement") + " (" + code + ")"
    }
}
