"""Regression checks for iOS appearance and App Store release contract.

Run: python3 -m unittest discover -s tests -p test_ios_appearance_contract.py
"""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile" / "ios"


class IOSAppearanceContractTests(unittest.TestCase):
    def test_persisted_system_default_and_three_modes(self):
        app = (IOS / "App" / "ArvectumProxyLauncherApp.swift").read_text(encoding="utf-8")
        appearance = (IOS / "App" / "AppearanceMode.swift").read_text(encoding="utf-8")
        view = (IOS / "App" / "ContentView.swift").read_text(encoding="utf-8")
        self.assertIn('case system, light, dark', appearance)
        self.assertIn('@AppStorage("appearanceMode.v1")', app)
        self.assertIn('@AppStorage("appearanceMode.v1")', view)
        self.assertIn('.preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)', app)
        self.assertIn('case .system: return nil', appearance)
        self.assertIn('Picker("Тема оформления"', view)

    def test_no_fixed_dark_palette_on_main_screens(self):
        view = (IOS / "App" / "ContentView.swift").read_text(encoding="utf-8")
        self.assertIn('static let canvas = adaptive(', view)
        self.assertIn('static let graphite = adaptive(', view)
        self.assertIn('static let text = adaptive(', view)
        self.assertNotIn('Brand.navy.ignoresSafeArea()', view)
        self.assertNotIn('.foregroundStyle(.white)', view)
        disclosure = (IOS / "App" / "PrivacyDisclosureView.swift").read_text(encoding="utf-8")
        self.assertIn('Brand.canvas.ignoresSafeArea()', disclosure)
        self.assertNotIn('.foregroundStyle(.white)', disclosure)

    def test_release_version_and_project_consistent(self):
        yml = (IOS / "project.yml").read_text(encoding="utf-8")
        pbx = (IOS / "ArvectumProxyLauncherIOS.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        self.assertIn('MARKETING_VERSION: "0.1.40"', yml)
        self.assertIn('CURRENT_PROJECT_VERSION: "45"', yml)
        self.assertEqual(pbx.count('MARKETING_VERSION = 0.1.40;'), 2)
        self.assertEqual(pbx.count('CURRENT_PROJECT_VERSION = 45;'), 2)

    def test_ads_enabled_in_release_only_main_app(self):
        config = (IOS / "project.yml").read_text(encoding="utf-8")
        ads = (IOS / "App" / "SettingsBannerView.swift").read_text(encoding="utf-8")
        tunnel = (IOS / "PacketTunnel" / "PacketTunnelProvider.swift").read_text(encoding="utf-8")
        self.assertIn('package: YandexMobileAds', config)
        self.assertIn('static let isEnabled = true', ads)
        self.assertIn('R-M-20288304-1', ads)
        self.assertIn('demo-banner-yandex', ads)
        self.assertNotIn('YandexMobileAds', tunnel)
        self.assertNotIn('AppMetrica', config)


if __name__ == "__main__":
    unittest.main()
