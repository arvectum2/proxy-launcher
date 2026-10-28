#if !targetEnvironment(macCatalyst)
import SwiftUI
import YandexMobileAds

/// The unit is registered for the iOS app; the Android App Open unit is separate.
/// Apple App Review 5.4/privacy review is a mandatory gate before production use.
enum IOSAdsConfig {
    static let productionBannerUnitID = "R-M-20288304-1"
    static let demoBannerUnitID = "demo-banner-yandex"

#if DEBUG
    // Explicit opt-in for local QA. Never contact production RSYA in debug builds.
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-APL_ENABLE_DEMO_BANNER")
    static let activeBannerUnitID = demoBannerUnitID
#else
    // Do not transmit data to ad providers from an App Store VPN client until
    // Apple 5.4 determination, privacy disclosures and owner approval are complete.
    static let isEnabled = false
    static let activeBannerUnitID = productionBannerUnitID
#endif
}

/// Non-blocking bottom-of-Settings banner; never appears in the tunnel extension.
/// No VPN connection state, domains, proxy settings or other user data are sent.
struct SettingsBannerView: View {
    @State private var bannerState: BannerState?
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        Group {
            if IOSAdsConfig.isEnabled, !failed, let bannerState {
                VStack(alignment: .leading, spacing: 4) {
                    if loaded {
                        Text(AppL10n.tr("Реклама"))
                            .font(.caption)
                            .foregroundStyle(Brand.softGray)
                    }
                    Banner(state: bannerState)
                        .onAdLoad { _ in loaded = true }
                        .onAdFailure { _ in
                            loaded = false
                            failed = true  // No retry loop, no empty placeholder.
                        }
                        .opacity(loaded ? 1 : 0)
                        .frame(height: loaded ? nil : 1) // Keep the view mounted while loading.
                        .accessibilityHidden(!loaded)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            guard IOSAdsConfig.isEnabled, bannerState == nil, !failed else { return }
            bannerState = BannerState(
                size: .sticky(),
                request: AdRequest(adUnitID: IOSAdsConfig.activeBannerUnitID)
            )
        }
    }
}
#endif
