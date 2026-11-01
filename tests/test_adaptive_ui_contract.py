import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
DESKTOP = (ROOT / "proxy_gui.py").read_text(encoding="utf-8")
LINUX = (ROOT / "linux_gui.py").read_text(encoding="utf-8")
ANDROID = (
    ROOT
    / "mobile/android/app/src/main/java/ru/arvectum/proxylauncher/MainActivity.kt"
).read_text(encoding="utf-8")
IOS = (ROOT / "mobile/ios/App/ContentView.swift").read_text(encoding="utf-8")


class AdaptiveUiContractTests(unittest.TestCase):
    def test_shared_brand_tokens_are_preserved(self):
        for token in ("#001432", "#00C8A0", "#78FAE6", "#283246"):
            self.assertIn(token, DESKTOP)
            self.assertIn(token, ANDROID)

        self.assertIn("static let navy = Color(red: 0, green: 20/255, blue: 50/255)", IOS)
        # Light mode adds a semantic palette; preserve the original dark-mode brand mint.
        self.assertIn("static let mint = adaptive(", IOS)
        self.assertIn("dark: UIColor(red: 0, green: 200/255, blue: 160/255, alpha: 1)", IOS)

    def test_navigation_order_is_shared(self):
        desktop_items = (
            '("home", tr("Главная"))',
            '("profiles", tr("Профили"))',
            '("activity", tr("Активность"))',
            '("settings", tr("Настройки"))',
        )
        android_items = (
            'destination(Destination.HOME, getString(R.string.apl_home_',
            'destination(Destination.PROFILES, getString(R.string.apl_profiles_',
            'destination(Destination.ACTIVITY, getString(R.string.apl_activity_',
            'destination(Destination.SETTINGS, getString(R.string.apl_settings_',
        )
        ios_items = (
            'return AppL10n.tr("Домой")',
            'case .profiles: return AppL10n.tr("Профили")',
            'case .activity: return AppL10n.tr("Активность")',
            'case .settings: return AppL10n.tr("Настройки")',
        )
        for source, fragments in ((DESKTOP, desktop_items), (ANDROID, android_items), (IOS, ios_items)):
            positions = [source.index(fragment) for fragment in fragments]
            self.assertEqual(positions, sorted(positions))

    def test_one_stateful_primary_connection_action(self):
        self.assertIn('self.btn_primary = ttk.Button(', DESKTOP)
        self.assertNotIn("self.btn_on =", DESKTOP)
        self.assertNotIn("self.btn_off =", DESKTOP)
        self.assertIn('state == ProxyVpnService.STATE_CONNECTED -> getString(R.string.apl_disconnect_', ANDROID)
        self.assertIn('case .connected, .reasserting: return "Отключить"', IOS)
        self.assertIn('case .connecting: return "Подключение…"', IOS)

    def test_advanced_actions_are_progressively_disclosed(self):
        self.assertIn('("activity", tr("Активность"))', DESKTOP)
        self.assertIn('("settings", tr("Настройки"))', DESKTOP)
        self.assertIn('text=tr("Диагностика")', DESKTOP)
        self.assertIn('text=tr("Восстановить настройки сети")', DESKTOP)
        self.assertIn('showSettingsHubDialog()', ANDROID)
        self.assertIn('private var settingsScreen: some View', IOS)

    def test_mobile_and_desktop_composition_is_adaptive_not_pixel_cloned(self):
        self.assertIn("#if targetEnvironment(macCatalyst)", IOS)
        # iPhone Home is intentionally a vertical header/ad/connect/profile
        # sequence at every phone size; Catalyst remains adaptive by width.
        self.assertIn("if geometry.size.width >= 820", IOS)
        self.assertIn(".frame(maxWidth: 580)", IOS)
        self.assertIn("homeConnectControl", IOS)
        self.assertIn("homeProfileControl", IOS)
        self.assertIn("desktopShell", IOS)
        self.assertIn("mobileShell", IOS)
        self.assertIn("self.root.minsize(720, 600)", DESKTOP)
        self.assertIn("private fun buildNavigationBar(): View", ANDROID)

    def test_catalyst_does_not_compile_iphone_shortcuts_control(self):
        view_start = IOS.index("struct ApplicationExclusionsView: View")
        view_end = IOS.index("struct JournalView: View", view_start)
        view = IOS[view_start:view_end]
        self.assertIn("#if targetEnvironment(macCatalyst)", view)
        self.assertIn("Настройка по открытию и закрытию приложений доступна на iPhone.", view)
        self.assertIn("#else", view)
        self.assertIn("AppRoutingVPNControl.applyBaseline", view)

    def test_linux_reuses_shared_desktop_primary_action(self):
        self.assertIn("self._apply_primary_action(view)", LINUX)


if __name__ == "__main__":
    unittest.main()
