import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
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
        }
    }
}
