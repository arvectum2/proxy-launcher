import SwiftUI

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
