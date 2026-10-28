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
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct ArvectumProxyLauncherApp: App {
    @StateObject private var model = AppViewModel()
    @AppStorage("appearanceMode.v1") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("appLanguage.v1") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("privacyDisclosureAccepted.v1") private var privacyDisclosureAccepted = false

    var body: some Scene {
        WindowGroup {
            Group {
                if privacyDisclosureAccepted {
                    ContentView()
                } else {
                    PrivacyDisclosureView {
                        privacyDisclosureAccepted = true
                    }
                }
            }
            .environmentObject(model)
            .preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)
            .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
        }
    }
}
