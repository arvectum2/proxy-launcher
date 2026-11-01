"""Source-level checks for the isolated iOS RSYA banner integration."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile" / "ios"


class IOSRSYABannerTests(unittest.TestCase):
    def test_ids_and_production_enabled(self):
        ads = (IOS / "App" / "SettingsBannerView.swift").read_text(encoding="utf-8")
        self.assertIn('productionBannerUnitID = "R-M-20288304-1"', ads)
        self.assertIn('demoBannerUnitID = "demo-banner-yandex"', ads)
        self.assertIn('static let isEnabled = true', ads)
        self.assertIn('-APL_ENABLE_DEMO_BANNER', ads)
        self.assertIn('activeBannerUnitID = demoBannerUnitID', ads)
        self.assertIn('activeBannerUnitID = productionBannerUnitID', ads)

    def test_banner_visible_in_tab_safe_area_not_buried_in_settings(self):
        main = (IOS / "App" / "ContentView.swift").read_text(encoding="utf-8")
        self.assertEqual(main.count('SettingsBannerView('), 1)
        self.assertIn('NativeHomeAdView(width:', main)
        self.assertIn('R-M-20288304-2', (IOS / 'App' / 'SettingsBannerView.swift').read_text(encoding='utf-8'))
        self.assertLess(main.find('SettingsBannerView('), main.find('private var settingsScreen:'))
        mobile_shell = main.split('private var mobileShell:', 1)[1].split('#if targetEnvironment(macCatalyst)', 1)[0]
        home = main.split('private var homeScreen: some View {', 1)[1].split('private var dashboardCardMaxHeight', 1)[0]
        self.assertIn('TabView(selection: $destination)', mobile_shell)
        self.assertNotIn('SettingsBannerView(', mobile_shell)
        self.assertNotIn('.safeAreaInset(edge: .bottom, spacing: 0)', mobile_shell)
        self.assertIn('SettingsBannerView(', home)
        self.assertIn('maxAdHeight: tight ? 120 : (compact ? 160 : 220)', home)
        self.assertIn('NativeHomeAdView(width:', home)
        self.assertLess(home.index('homeMeasured("header")'), home.index('SettingsBannerView('))
        self.assertLess(home.index('SettingsBannerView('), home.index('homeConnectControl'))
        self.assertLess(home.index('homeConnectControl'), home.index('homeProfileControl'))
        settings = main.split('private var settingsScreen:', 1)[1].split('private var profileSelectionMenu', 1)[0]
        self.assertNotIn('SettingsBannerView(', settings)
        self.assertNotIn('SettingsBannerView', (IOS / "PacketTunnel" / "PacketTunnelProvider.swift").read_text(encoding="utf-8"))
        project = (IOS / "project.yml").read_text(encoding="utf-8")
        main_target = project.split('  ArvectumProxyLauncher:', 1)[1].split('  PacketTunnel:', 1)[0]
        tunnel_target = project.split('  PacketTunnel:', 1)[1]
        self.assertIn('package: YandexMobileAds', main_target)
        self.assertNotIn('package: YandexMobileAds', tunnel_target)
        self.assertIn('OTHER_LDFLAGS: "$(inherited) -ObjC"', main_target)

    def test_failed_ad_retries_once_with_backoff(self):
        ads = (IOS / "App" / "SettingsBannerView.swift").read_text(encoding="utf-8")
        self.assertIn('failed = true', ads)
        self.assertIn('if IOSAdsConfig.isEnabled, !failed', ads)
        self.assertEqual(ads.count('BannerState('), 1)
        self.assertIn('maxAttempts = 2', ads)
        self.assertIn('retryDelayNs: UInt64 = 45_000_000_000', ads)
        self.assertIn('scheduleRetryIfNeeded()', ads)
        self.assertIn('rsya.bannerStatus.v1', ads)
        self.assertIn('rsya.bannerStatus.secondary.v1', ads)
        native = (IOS / 'App' / 'NativeHomeAdView.swift').read_text(encoding='utf-8')
        self.assertIn('NativeAdLoader()', native)
        self.assertIn('try native.bind(with: adView)', native)
        self.assertIn('nativeAd(_ ad: NativeAd, didTrackImpression', native)
        self.assertIn('SettingsBannerView(adWidth: width, maxAdHeight: 76', native)
        self.assertIn('UserDefaults.standard.set("impression"', ads)
        app = (IOS / "App" / "ArvectumProxyLauncherApp.swift").read_text(encoding="utf-8")
        self.assertIn('YandexAds.initializeSDK(completionHandler: nil)', app)

    def test_no_collapsed_banner_and_failure_is_logged(self):
        ads = (IOS / "App" / "SettingsBannerView.swift").read_text(encoding="utf-8")
        self.assertNotIn('.frame(height: loaded ? nil : 1)', ads)
        self.assertNotIn('.opacity(loaded ? 1 : 0)', ads)
        self.assertIn('.frame(minHeight: placement == .primary ? 80 : 42,', ads)
        self.assertIn('Logger(subsystem: "ru.arvectum.proxylauncher.ios", category: "RSYA")', ads)
        self.assertIn('logger.error("RSYA banner load failed:', ads)
        self.assertIn('logger.info("RSYA banner impression")', ads)

    def test_ad_label_respects_new_app_language_setting(self):
        view = (IOS / "App" / "SettingsBannerView.swift").read_text(encoding="utf-8")
        self.assertIn('Text(IOSAdsConfig.localizedAdLabel)', view)
        self.assertIn('labels[AppL10n.effectiveLanguage]', view)
        # The 50-language banner owns these labels independently of the
        # 155-key product UI catalogs; no two-locale-only extra string key.
        self.assertIn('"ru": "Реклама"', view)
        self.assertIn('"en": "Ad"', view)

    def test_android_placement_preserved(self):
        gradle = (IOS.parent / "android" / "app" / "build.gradle.kts").read_text(encoding="utf-8")
        self.assertIn("R-M-20130429-1", gradle)


if __name__ == "__main__":
    unittest.main()
