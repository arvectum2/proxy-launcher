import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return AppL10n.tr("Системная")
        case .light: return AppL10n.tr("Светлая")
        case .dark: return AppL10n.tr("Тёмная")
        }
    }
    /// Explicit language selection is authoritative while a SwiftUI Picker
    /// updates @AppStorage. UserDefaults' argument domain (used by UI tests)
    /// and UIKit's cached segmented control titles must not override it.
    func title(forLanguage language: String) -> String {
        let key: String
        switch self {
        case .system: key = "Системная"
        case .light: key = "Светлая"
        case .dark: key = "Тёмная"
        }
        return AppL10n.tr(key, language: language)
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
