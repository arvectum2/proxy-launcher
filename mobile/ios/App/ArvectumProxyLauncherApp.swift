import SwiftUI
#if !targetEnvironment(macCatalyst)
import YandexMobileAds
#endif

#if APL_PRODUCT_OWNER_QA
@main
struct ArvectumProxyLauncherApp: App {
    var body:some Scene {WindowGroup {ProductOwnerQAView()}}
}
#else
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
#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PRODUCT_RUNTIME_REVIEW && APL_NATIVE_RUNTIME_QA_HARNESS && APL_NATIVE_PERSISTENT_LIBRARY && !targetEnvironment(simulator)
                if NativeRuntimeReviewQAView.enabled {NativeRuntimeReviewQAView()}
                else {ordinaryRoot}
#else
                ordinaryRoot
#endif
            }
            .preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)
            .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
            .environment(\.layoutDirection, ["fa", "ar", "ur", "he"].contains(AppL10n.effectiveLanguage) ? .rightToLeft : .leftToRight)
        }
    }
    private var ordinaryRoot:some View {
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
    }
}

#endif
