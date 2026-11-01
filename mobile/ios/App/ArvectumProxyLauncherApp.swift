import SwiftUI
#if !targetEnvironment(macCatalyst)
import YandexMobileAds
#endif

@main
struct ArvectumProxyLauncherApp: App {
    @StateObject private var model = AppViewModel()
    @AppStorage("appearanceMode.v1") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("appLanguage.v1") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("privacyDisclosureAccepted.v1") private var privacyDisclosureAccepted = false

    init() {
#if !targetEnvironment(macCatalyst)
        // Start the SDK before the banner enters the view hierarchy. This
        // reduces first-impression latency, including on a cold app launch.
        YandexAds.initializeSDK(completionHandler: nil)
#endif
    }

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
            .environment(\.layoutDirection, ["fa", "ar", "ur", "he"].contains(AppL10n.effectiveLanguage) ? .rightToLeft : .leftToRight)
        }
    }
}
