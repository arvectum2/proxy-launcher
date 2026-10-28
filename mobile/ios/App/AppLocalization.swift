import Foundation

/// Language preference is independent of the color-scheme preference.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case ru
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return AppL10n.tr("Как в системе")
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return Locale.current
        case .ru: return Locale(identifier: "ru")
        case .en: return Locale(identifier: "en")
        }
    }
}

/// Use for dynamic String values. Literal SwiftUI labels are localized by
/// Localizable.strings and the window's .environment(\.locale) override.
enum AppL10n {
    static let storageKey = "appLanguage.v1"

    static var effectiveLanguage: String {
        let selected = UserDefaults.standard.string(forKey: storageKey) ?? "system"
        if selected == "ru" || selected == "en" { return selected }
        // Bundle-selected localization is more reliable than Locale.current
        // for multilingual iPhones with an app-specific iOS language setting.
        let bundleLanguage = Bundle.main.preferredLocalizations.first ?? "en"
        return bundleLanguage.hasPrefix("ru") ? "ru" : "en"
    }

    static func tr(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: effectiveLanguage, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}
