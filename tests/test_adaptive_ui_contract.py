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
        self.assertIn("static let mint = Color(red: 0, green: 200/255, blue: 160/255)", IOS)

    def test_navigation_order_is_shared(self):
        desktop_items = (
            '("home", "Главная")',
            '("profiles", "Профили")',
            '("activity", "Активность")',
            '("settings", "Настройки")',
        )
        android_items = (
            'destination(Destination.HOME, "Главная")',
            'destination(Destination.PROFILES, "Профили")',
            'destination(Destination.ACTIVITY, "Активность"',
            'destination(Destination.SETTINGS, "Настройки"',
        )
        ios_items = (
            'case .home: return "Главная"',
            'case .profiles: return "Профили"',
            'case .activity: return "Активность"',
            'case .settings: return "Настройки"',
        )
        for source, fragments in ((DESKTOP, desktop_items), (ANDROID, android_items), (IOS, ios_items)):
            positions = [source.index(fragment) for fragment in fragments]
            self.assertEqual(positions, sorted(positions))

    def test_one_stateful_primary_connection_action(self):
        self.assertIn('self.btn_primary = ttk.Button(', DESKTOP)
        self.assertNotIn("self.btn_on =", DESKTOP)
        self.assertNotIn("self.btn_off =", DESKTOP)
        self.assertIn('STATE_CONNECTED -> "Отключить"', ANDROID)
        self.assertIn('case .connected, .reasserting: return "Отключить"', IOS)
        self.assertIn('case .connecting: return "Подключение…"', IOS)

    def test_advanced_actions_are_progressively_disclosed(self):
        self.assertIn('("activity", "Активность")', DESKTOP)
        self.assertIn('("settings", "Настройки")', DESKTOP)
        self.assertIn('text="Диагностика"', DESKTOP)
        self.assertIn('text="Восстановить настройки сети"', DESKTOP)
        self.assertIn('showSettingsHubDialog()', ANDROID)
        self.assertIn('private var settingsScreen: some View', IOS)

    def test_mobile_and_desktop_composition_is_adaptive_not_pixel_cloned(self):
        self.assertIn("#if targetEnvironment(macCatalyst)", IOS)
        self.assertIn("if geometry.size.width >= 700", IOS)
        self.assertIn("desktopShell", IOS)
        self.assertIn("mobileShell", IOS)
        self.assertIn("self.root.minsize(720, 600)", DESKTOP)
        self.assertIn("private fun buildNavigationBar(): View", ANDROID)

    def test_linux_reuses_shared_desktop_primary_action(self):
        self.assertIn("self._apply_primary_action(view)", LINUX)


if __name__ == "__main__":
    unittest.main()
