#if !targetEnvironment(macCatalyst)
import SwiftUI
import OSLog
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
    // Production banner enabled by explicit owner directive; App Store privacy metadata is unchanged.
    static let isEnabled = true
    static let activeBannerUnitID = productionBannerUnitID
#endif
}

/// Non-blocking banner above the iPhone tab bar; never appears in the tunnel extension.
/// No VPN connection state, domains, proxy settings or other user data are sent.
struct SettingsBannerView: View {
    @State private var bannerState: BannerState?
    @State private var loaded = false
    @State private var failed = false
    private let logger = Logger(subsystem: "ru.arvectum.proxylauncher.ios", category: "RSYA")

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
                        .onAdLoad { _ in
                            loaded = true
                            logger.info("RSYA banner loaded")
                        }
                        .onAdFailure { error in
                            logger.error("RSYA banner load failed: \(String(describing: error), privacy: .public)")
                            loaded = false
                            failed = true  // No retry storm; hide failed request.
                        }
                        .onAdImpression { _ in
                            logger.info("RSYA banner impression")
                        }
                        // Yandex sticky banners need their full adaptive area
                        // (at least 50pt) even *before* loading succeeds.
                        .frame(minHeight: 50)
                        .frame(maxWidth: .infinity)
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
