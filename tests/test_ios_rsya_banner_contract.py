"""Source-level checks for the isolated iOS RSYA banner integration."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile" / "ios"


class IOSRSYABannerTests(unittest.TestCase):
    def test_ids_and_production_off_default(self):
        ads = (IOS / "App" / "SettingsBannerView.swift").read_text()
        self.assertIn('productionBannerUnitID = "R-M-20288304-1"', ads)
        self.assertIn('demoBannerUnitID = "demo-banner-yandex"', ads)
        self.assertIn('static let isEnabled = false', ads)
        self.assertIn('-APL_ENABLE_DEMO_BANNER', ads)
        self.assertIn('activeBannerUnitID = demoBannerUnitID', ads)
        self.assertIn('activeBannerUnitID = productionBannerUnitID', ads)

    def test_banner_in_settings_not_tunnel_or_connect_screen(self):
        main = (IOS / "App" / "ContentView.swift").read_text()
        self.assertEqual(main.count('SettingsBannerView()'), 1)
        self.assertGreater(main.find('SettingsBannerView()'), main.find('private var settingsScreen:'))
        self.assertNotIn('SettingsBannerView', (IOS / "PacketTunnel" / "PacketTunnelProvider.swift").read_text())
        project = (IOS / "project.yml").read_text()
        main_target = project.split('  ArvectumProxyLauncher:', 1)[1].split('  PacketTunnel:', 1)[0]
        tunnel_target = project.split('  PacketTunnel:', 1)[1]
        self.assertIn('package: YandexMobileAds', main_target)
        self.assertNotIn('package: YandexMobileAds', tunnel_target)
        self.assertIn('OTHER_LDFLAGS: "$(inherited) -ObjC"', main_target)

    def test_failed_ad_is_hidden_without_retry(self):
        ads = (IOS / "App" / "SettingsBannerView.swift").read_text()
        self.assertIn('failed = true', ads)
        self.assertIn('if IOSAdsConfig.isEnabled, !failed', ads)
        self.assertEqual(ads.count('BannerState('), 1)

    def test_ad_label_respects_new_app_language_setting(self):
        view = (IOS / "App" / "SettingsBannerView.swift").read_text()
        self.assertIn('AppL10n.tr("Реклама")', view)
        for language, value in (("ru", "Реклама"), ("en", "Advertisement")):
            strings = (IOS / "Resources" / f"{language}.lproj" / "Localizable.strings").read_text()
            self.assertIn(f'"Реклама" = "{value}";', strings)

    def test_android_placement_preserved(self):
        gradle = (IOS.parent / "android" / "app" / "build.gradle.kts").read_text()
        self.assertIn("R-M-20130429-1", gradle)


if __name__ == "__main__":
    unittest.main()
