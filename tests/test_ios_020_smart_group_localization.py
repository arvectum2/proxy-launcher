"""Release guard for iOS 0.2.0 grouped Smart Exclusions translations.

This checks catalog completeness and copy invariants without contacting any
translation service or changing app language preferences on a real device.
"""
from pathlib import Path
from collections import Counter
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile" / "ios"
CATALOGS = IOS / "Resources"
UX = (IOS / "App" / "SmartExclusionsUX.swift").read_text(encoding="utf-8")
SETTINGS = (IOS / "App" / "CompactSettingsView.swift").read_text(encoding="utf-8")
SCREEN = (IOS / "App" / "ExclusionsView.swift").read_text(encoding="utf-8")

KEYS = (
    "Автоматически расширять исключения",
    "Добавить связанный домен",
    "Адрес связанного домена",
    "Системная связь",
    "Добавлено вручную",
    "В автоматическом режиме проверенные поддомены добавляются сами. В ручном режиме выбирайте их из предложений. Сохраните изменения для применения.",
)
PAIR = re.compile(r'^\s*"([^"\n]+)"\s*=\s*"([^"\n]*)"\s*;', re.MULTILINE)
BAD_SAVE = {
    "ar": "توفير…",
    "de": "Sparen…",
    "el": "Οικονομία…",
    "es": "Ahorro…",
    "fr": "Économie…",
    "he": "חִסָכוֹן…",
    "hu": "Megtakarítás…",
    "id": "Penghematan…",
    "it": "Risparmio…",
    "ko": "절약…",
    "nl": "Besparing…",
    "pl": "Oszczędność…",
    "ro": "Economisire…",
    "th": "ประหยัด…",
}
# Different scripts are expected in Cyrillic-using and some neighbouring
# locales, but untranslated Russian control labels are never a safe fallback.
NATIVE_CYRILLIC = {"be", "bg", "kk", "ky", "ru", "sr", "tg", "uk"}


class SmartGroupLocaleCoverage(unittest.TestCase):
    def test_every_existing_locale_has_all_six_group_controls(self):
        files = sorted(CATALOGS.glob("*.lproj/SmartExclusions.strings"))
        app_locales = {p.parent.stem for p in CATALOGS.glob("*.lproj/Localizable.strings")}
        self.assertEqual(len(app_locales), 64)
        self.assertEqual({p.parent.stem for p in files}, app_locales)
        for file in files:
            with self.subTest(language=file.parent.stem):
                text = file.read_text(encoding="utf-8")
                pairs = PAIR.findall(text)
                values = dict(pairs)
                self.assertEqual(Counter(k for k, _ in pairs).most_common(1)[0][1], 1,
                                 "Duplicate localization key")
                self.assertTrue(set(KEYS).issubset(values),
                                f"Missing controls: {set(KEYS) - set(values)}")
                for key in KEYS:
                    value = values[key]
                    self.assertTrue(value.strip(), key)
                    self.assertLess(len(value), 500, "Text must remain readable")
                    self.assertNotIn("%@", value, "No injected runtime placeholders")
                    self.assertNotIn("\\n", value, "No escaped format-line breaks")
                    if file.parent.stem not in NATIVE_CYRILLIC:
                        self.assertFalse(re.search(r"[А-Яа-яЁё]", value), f"Russian fallback: {key}")
                if file.parent.stem in BAD_SAVE:
                    self.assertNotEqual(values["Сохранение…"], BAD_SAVE[file.parent.stem])

    def test_language_controls_route_through_contextual_catalog(self):
        self.assertIn('settingsRow("Автоматически расширять исключения")', SETTINGS)
        self.assertIn('SmartExclusionsUX.text("Автоматически расширять исключения")', SETTINGS)
        self.assertIn('SmartExclusionsUX.text("Добавить связанный домен")', SCREEN)
        self.assertIn('SmartExclusionsUX.text("Адрес связанного домена")', SCREEN)
        self.assertIn('SmartExclusionsUX.text("Системная связь")', SCREEN)
        self.assertIn('edge.userLinked == true ? "Добавлено вручную"', SCREEN)
        self.assertIn('AppL10n.tr(russian, table: "SmartExclusions")', UX)
        for key in KEYS:
            self.assertIn(key, UX)

    def test_key_english_and_rtl_copy_has_real_translation(self):
        for lang, desired in [
            ("en", "Expand exclusions automatically"),
            ("fr", "Étendre automatiquement les exclusions"),
            ("de", "Ausnahmen automatisch erweitern"),
            ("he", "הרחבה אוטומטית של חריגים"),
            ("ar", "توسيع الاستثناءات تلقائيًا"),
            ("zh-Hans", "自动扩展排除项"),
        ]:
            with self.subTest(lang=lang):
                text = (CATALOGS / (lang + ".lproj") / "SmartExclusions.strings").read_text()
                translations = dict(PAIR.findall(text))
                self.assertEqual(translations[KEYS[0]], desired)


if __name__ == "__main__":
    unittest.main()
