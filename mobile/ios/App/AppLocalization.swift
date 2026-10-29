import Foundation

/// The locale preference is independent of the color-scheme preference.
/// The cases match the 12-language Arvectum Tools Core source baseline.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case ru
    case es
    case fr
    case de
    case ptBR = "pt-BR"
    case ptPT = "pt-PT"
    case it
    case ja
    case ko
    case fa
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return AppL10n.tr("Как в системе")
        case .en: return "English"
        case .ru: return "Русский"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .ptBR: return "Português (Brasil)"
        case .ptPT: return "Português (Portugal)"
        case .it: return "Italiano"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fa: return "فارسی"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        }
    }

    var locale: Locale {
        // `.system` must follow iOS's per-app language preference too, not
        // only Locale.current, which may be different from Bundle localizations.
        Locale(identifier: self == .system ? AppL10n.systemLanguage : rawValue)
    }
}

/// Dynamic translations, for strings not inferred from SwiftUI literal keys.
enum AppL10n {
    static let storageKey = "appLanguage.v1"

    static func supportedLanguage(_ identifier: String) -> String? {
        let id = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if id == "zh" || id.hasPrefix("zh-hans") || id.hasPrefix("zh-cn") || id.hasPrefix("zh-sg") {
            return "zh-Hans"
        }
        if id.hasPrefix("zh-hant") || id.hasPrefix("zh-tw") || id.hasPrefix("zh-hk") || id.hasPrefix("zh-mo") {
            return "zh-Hant"
        }
        if id == "pt" || id.hasPrefix("pt-pt") { return "pt-PT" }
        if id.hasPrefix("pt-br") { return "pt-BR" }
        for code in ["en", "ru", "es", "fr", "de", "it", "ja", "ko", "fa"] {
            if id == code || id.hasPrefix(code + "-") { return code }
        }
        return nil
    }

    static var systemLanguage: String {
        // Prefer the language actually negotiated for this app by iOS.
        for identifier in Bundle.main.preferredLocalizations {
            if let code = supportedLanguage(identifier) { return code }
        }
        return "en"
    }

    static var effectiveLanguage: String {
        let selected = UserDefaults.standard.string(forKey: storageKey) ?? "system"
        if selected != "system", let value = AppLanguage(rawValue: selected) {
            return value.rawValue
        }
        return systemLanguage
    }

    static func tr(_ key: String) -> String {
        let language = effectiveLanguage
        for name in [language, "en"] {
            if let path = Bundle.main.path(forResource: name, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                // All shipped catalogs are key-complete, and Russian values
                // legitimately equal the Russian lookup keys.
                return bundle.localizedString(forKey: key, value: key, table: "Localizable")
            }
        }
        return key
    }
}
