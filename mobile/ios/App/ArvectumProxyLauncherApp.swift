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

    @State private var adsStartupCompleted = false

    private var shouldInitializeAds: Bool {
#if !targetEnvironment(macCatalyst)
        return IOSAdsConfig.isEnabled
#else
        return false
#endif
    }

    @MainActor private func startAdsAfterDisclosure() {
        guard privacyDisclosureAccepted, shouldInitializeAds, !adsStartupCompleted else { return }
#if !targetEnvironment(macCatalyst)
#if DEBUG
        YandexAds.enableLogging()
#endif
        YandexAds.initializeSDK(completionHandler: nil)
#endif
        adsStartupCompleted = true
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if privacyDisclosureAccepted {
                    if !shouldInitializeAds || adsStartupCompleted {
                        ContentView()
                    } else {
                        // Do not construct ad views/loaders before the explicit SDK call.
                        ProgressView().onAppear { startAdsAfterDisclosure() }
                    }
                } else {
                    PrivacyDisclosureView(appLanguage: $appLanguage) {
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
