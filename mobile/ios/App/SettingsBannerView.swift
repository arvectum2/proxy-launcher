#if !targetEnvironment(macCatalyst)
import SwiftUI
import OSLog
import YandexMobileAds

/// The unit is registered for the iOS app; the Android App Open unit is separate.
/// Apple App Review 5.4/privacy review is a mandatory gate before production use.
enum IOSAdsConfig {
    static let productionBannerUnitID = "R-M-20288304-1"
    static let demoBannerUnitID = "demo-banner-yandex"

    static let labels: [String: String] = [
        "ru": "Реклама",
        "en": "Ad",
        "es": "Publicidad",
        "fr": "Publicité",
        "de": "Anzeige",
        "it": "Pubblicità",
        "pt-BR": "Publicidade",
        "pt-PT": "Publicidade",
        "ja": "広告",
        "ko": "광고",
        "zh-Hans": "广告",
        "zh-Hant": "廣告",
        "fa": "تبلیغ",
        "nl": "Advertentie",
        "id": "Iklan",
        "tr": "Reklam",
        "hi": "विज्ञापन",
        "ar": "إعلان",
        "vi": "Quảng cáo",
        "pl": "Reklama",
        "th": "โฆษณา",
        "ur": "اشتہار",
        "bn": "বিজ্ঞাপন",
        "pa": "ਇਸ਼ਤਿਹਾਰ",
        "ta": "விளம்பரம்",
        "te": "ప్రకటన",
        "mr": "जाहिरात",
        "gu": "જાહેરાત",
        "kn": "ಜಾಹೀರಾತು",
        "ml": "പരസ്യം",
        "uz": "Reklama",
        "ms": "Iklan",
        "fil": "Ad",
        "sw": "Tangazo",
        "ro": "Publicitate",
        "hu": "Hirdetés",
        "cs": "Reklama",
        "sk": "Reklama",
        "el": "Διαφήμιση",
        "he": "פרסומת",
        "ha": "Talla",
        "am": "ማስታወቂያ",
        "sv": "Annons",
        "da": "Annonce",
        "fi": "Mainos",
        "nb": "Annonse",
        "bg": "Реклама",
        "sr": "Оглас",
        "hr": "Oglas",
        "ca": "Anunci",
    ]
    static var localizedAdLabel: String {
        labels[AppL10n.effectiveLanguage] ?? labels["en"] ?? "Ad"
    }

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

/// Non-blocking native ad footer alongside the iPhone TabView; never appears in the tunnel extension.
/// No VPN connection state, domains, proxy settings or other user data are sent.
struct SettingsBannerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var bannerState: BannerState?
    @State private var loaded = false
    @State private var failed = false
    @State private var attempts = 0
    @State private var retryTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "ru.arvectum.proxylauncher.ios", category: "RSYA")
    private let statusKey = "rsya.bannerStatus.v1"
    private let maxAttempts = 2
    private let retryDelayNs: UInt64 = 45_000_000_000

    var body: some View {
        VStack(spacing: 0) {
            if IOSAdsConfig.isEnabled, !failed {
                if let bannerState {
                    VStack(alignment: .leading, spacing: 4) {
                        if loaded {
                            Text(IOSAdsConfig.localizedAdLabel)
                                .font(.caption2)
                                .foregroundStyle(Brand.softGray)
                        }
                        Banner(state: bannerState)
                            .onAdLoad { _ in
                                loaded = true
                                failed = false
                                UserDefaults.standard.set("loaded", forKey: statusKey)
                                logger.info("RSYA banner loaded")
                            }
                            .onAdFailure { error in
                                let nsError = error as NSError
                                logger.error("RSYA banner load failed: code=\(nsError.code) domain=\(nsError.domain, privacy: .public)")
                                UserDefaults.standard.set("failed: \(nsError.code)", forKey: statusKey)
                                loaded = false
                                failed = true
                                scheduleRetryIfNeeded()
                            }
                            .onAdImpression { _ in
                                UserDefaults.standard.set("impression", forKey: statusKey)
                                logger.info("RSYA banner impression")
                            }
                            .frame(minHeight: 50)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(!loaded)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Color.clear.frame(height: 50)
                }
            }
        }
        .onAppear {
            guard IOSAdsConfig.isEnabled else { return }
            if bannerState == nil { requestBanner() }
            else if failed { scheduleRetryIfNeeded() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, failed { scheduleRetryIfNeeded() }
        }
        .onDisappear {
            retryTask?.cancel()
            retryTask = nil
        }
    }

    private func requestBanner() {
        guard attempts < maxAttempts else { return }
        attempts += 1
        loaded = false
        failed = false
        UserDefaults.standard.set("request-\(attempts)", forKey: statusKey)
        bannerState = BannerState(size: .sticky(),
                                  request: AdRequest(adUnitID: IOSAdsConfig.activeBannerUnitID))
    }

    private func scheduleRetryIfNeeded() {
        guard attempts < maxAttempts, retryTask == nil else { return }
        retryTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: retryDelayNs) }
            catch { return }
            retryTask = nil
            guard !Task.isCancelled, scenePhase == .active else { return }
            // One delayed retry after a transient SDK/no-fill failure, never
            // a request storm. SDK handles normal refresh after a success.
            requestBanner()
        }
    }
}
#endif
