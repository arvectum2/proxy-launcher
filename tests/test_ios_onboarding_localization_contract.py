"""Release contract checks for real iOS RU/EN localization and first-use proxy guide."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile" / "ios"


def strings(locale):
    source = (IOS / "Resources" / f"{locale}.lproj" / "Localizable.strings").read_text(encoding="utf-8")
    pairs = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";$', source, flags=re.MULTILINE)
    return dict(pairs)


class IOSOnboardingLocalizationContractTests(unittest.TestCase):
    def test_languages_have_parallel_real_strings(self):
        en, ru = strings("en"), strings("ru")
        self.assertGreaterEqual(len(ru), 120)
        self.assertEqual(set(en), set(ru))
        for key in ("Главная", "Настройки", "Соединение", "Подключиться", "Конфиденциальность",
                    "Подготовьте данные прокси", "Создайте профиль", "Подключитесь",
                    "Хост — адрес сервера, порт — его номер. Тип уточните у поставщика.",
                    "Язык приложения", "Первое подключение"):
            self.assertIn(key, en)
            self.assertNotEqual(key, en[key], "Untranslated critical English key: " + key)

    def test_locale_is_persisted_and_applied_to_all_screens(self):
        app = (IOS / "App" / "ArvectumProxyLauncherApp.swift").read_text(encoding="utf-8")
        language = (IOS / "App" / "AppLocalization.swift").read_text(encoding="utf-8")
        view = (IOS / "App" / "ContentView.swift").read_text(encoding="utf-8")
        self.assertIn('case system', language)
        self.assertIn('case ru', language)
        self.assertIn('case en', language)
        self.assertIn('@AppStorage("appLanguage.v1")', app)
        self.assertIn('.environment(\\.locale,', app)
        self.assertIn('Picker("Язык приложения"', view)
        self.assertIn('Text(AppL10n.tr(model.vpn.detail))', view)
        self.assertIn('Text(AppL10n.tr(type.label))', view)

    def test_onboarding_is_skippable_and_reopenable(self):
        app = (IOS / "App" / "ContentView.swift").read_text(encoding="utf-8")
        guide = (IOS / "App" / "SetupGuideView.swift").read_text(encoding="utf-8")
        self.assertIn('@AppStorage("setupGuideSeen.v1")', app)
        self.assertIn('if !setupGuideSeen && model.profiles.isEmpty', app)
        self.assertIn('setupGuideSeen = true', app)
        self.assertIn('settingsButton("Первое подключение"', app)
        self.assertIn('onClose: () -> Void', guide)
        self.assertIn('onCreateProfile: () -> Void', guide)
        self.assertIn('onCreateProfile()', guide)
        self.assertIn("APL не продаёт и не предоставляет прокси-серверы", guide)
        self.assertIn('Хост — адрес сервера, порт — его номер.', app)

    def test_next_version_and_packaging(self):
        project = (IOS / "project.yml").read_text(encoding="utf-8")
        pbx = (IOS / "ArvectumProxyLauncherIOS.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        self.assertIn('MARKETING_VERSION: "0.1.39"', project)
        self.assertIn('CURRENT_PROJECT_VERSION: "44"', project)
        self.assertIn('Localizable.strings in Resources', pbx)
        self.assertIn('AppLocalization.swift in Sources', pbx)
        self.assertIn('SetupGuideView.swift in Sources', pbx)
        self.assertIn("package: YandexMobileAds", project)
        self.assertIn("static let isEnabled = true", (IOS / "App/SettingsBannerView.swift").read_text(encoding="utf-8"))

if __name__ == "__main__":
    unittest.main()
