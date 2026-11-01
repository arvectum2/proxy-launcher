import Foundation

/// The locale preference is independent of the color-scheme preference.
/// The cases cover the 50 fully populated APL iOS source languages.
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
    case nl
    case indonesian = "id"
    case tr
    case hi
    case ar
    case vi
    case pl
    case th
    case ur
    case bn
    case pa
    case ta
    case te
    case mr
    case gu
    case kn
    case ml
    case uz
    case ms
    case fil
    case sw
    case ro
    case hu
    case cs
    case sk
    case el
    case he
    case ha
    case am
    case sv
    case da
    case fi
    case nb
    case bg
    case sr
    case hr
    case ca
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
        case .nl: return "Nederlands"
        case .indonesian: return "Bahasa Indonesia"
        case .tr: return "Türkçe"
        case .hi: return "हिन्दी"
        case .ar: return "العربية"
        case .vi: return "Tiếng Việt"
        case .pl: return "Polski"
        case .th: return "ไทย"
        case .ur: return "اردو"
        case .bn: return "বাংলা"
        case .pa: return "ਪੰਜਾਬੀ (ਗੁਰਮੁਖੀ)"
        case .ta: return "தமிழ்"
        case .te: return "తెలుగు"
        case .mr: return "मराठी"
        case .gu: return "ગુજરાતી"
        case .kn: return "ಕನ್ನಡ"
        case .ml: return "മലയാളം"
        case .uz: return "Oʻzbekcha (lotin)"
        case .ms: return "Bahasa Melayu"
        case .fil: return "Filipino"
        case .sw: return "Kiswahili"
        case .ro: return "Română"
        case .hu: return "Magyar"
        case .cs: return "Čeština"
        case .sk: return "Slovenčina"
        case .el: return "Ελληνικά"
        case .he: return "עברית"
        case .ha: return "Hausa"
        case .am: return "አማርኛ"
        case .sv: return "Svenska"
        case .da: return "Dansk"
        case .fi: return "Suomi"
        case .nb: return "Norsk bokmål"
        case .bg: return "Български"
        case .sr: return "Српски (ћирилица)"
        case .hr: return "Hrvatski"
        case .ca: return "Català"
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

    // 0.2 uses shorter iPhone labels. Reuse the existing *native* 0.1.x
    // translations of semantically equivalent labels before falling back to
    // English. This keeps Home and Settings localized in all 50 catalogs.
    private static let legacyLabelAliases: [String: String] = [
        "Домой": "Главная",
        "Тема": "Тема оформления",
        "Язык": "Язык приложения",
        "Автоматизация": "Автоматизация приложений",
    ]

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
        if id == "pa-pk" || id.hasPrefix("pa-arab") { return nil }
        if id == "uz-cyrl" || id.hasPrefix("uz-cyrl-") { return nil }
        if id == "sr-latn" || id.hasPrefix("sr-latn-") { return nil }
        if id == "ha-arab" || id.hasPrefix("ha-arab-") { return nil }
        if id == "no" || id.hasPrefix("no-") { return "nb" }
        for code in ["en", "ru", "es", "fr", "de", "it", "ja", "ko", "fa", "nl", "id", "tr", "hi", "ar", "vi", "pl", "th", "ur", "bn", "pa", "ta", "te", "mr", "gu", "kn", "ml", "uz", "ms", "fil", "sw", "ro", "hu", "cs", "sk", "el", "he", "ha", "am", "sv", "da", "fi", "nb", "bg", "sr", "hr", "ca"] {
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

    /// Feature-specific localization tables avoid ambiguous common keys.
    /// For example, import's «Проверить» means Preview, while the primary
    /// profile action «Проверить» means Check.
    static func tr(_ key: String, table: String) -> String {
        let missing = "__APL_020_MISSING_TRANSLATION__"
        for code in [effectiveLanguage, "en"] {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            let value = bundle.localizedString(forKey: key, value: missing, table: table)
            if value != missing { return value }
        }
        return key
    }

    static func tr(_ key: String) -> String {
        // Preserve the reviewed 155-key legacy catalog. The 0.2 ProfileManagement
        // strings now have native values for all 50 languages; English remains
        // a defensive fallback for any future missing/optional source key.
        let missing = "__APL_020_MISSING_TRANSLATION__"
        for name in [effectiveLanguage, "en"] {
            guard let path = Bundle.main.path(forResource: name, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            for table in ["Localizable", "ProfileManagement"] {
                let value = bundle.localizedString(forKey: key, value: missing, table: table)
                if value != missing { return value }
            }
            if let previousKey = legacyLabelAliases[key] {
                let previousValue = bundle.localizedString(
                    forKey: previousKey, value: missing, table: "Localizable"
                )
                if previousValue != missing { return previousValue }
            }
        }
        return key

    }
}
