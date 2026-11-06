import Foundation

/// Non-sensitive, translated UI diagnostics for iOS Shortcuts app-automation.
/// Neither NSError descriptions nor storage paths, URLs, hostnames, account
/// details or credentials may appear in user-visible messages.
enum AppAutomationFailureUX {
    /// Fixed storage failure: do not guess from an arbitrary storage NSError.
    static func storage(translate: (String) -> String) -> String {
        "\(translate("Сохранить")) · STORE\n\(translate("Недоступен"))"
    }

    /// VPN baseline application failed. Only a finite, trusted, typed code is
    /// exposed; an unrecognized platform exception is reported as generic VPN.
    static func vpn(_ error: Error, translate: (String) -> String) -> String {
        let reason = ProxyFailureReason.classify(error)
        let code = reason == .unknown ? "VPN" : reason.code
        return "\(translate("Настройки")) · \(code)\n\(translate("Недоступен"))"
    }
}
