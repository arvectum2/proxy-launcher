"""Regression for a physical iPhone Mirroring finding: theme segments keep Russian after English switch."""
from pathlib import Path
import re

BASE = Path(__file__).resolve().parents[1] / "mobile/ios"
APP = BASE / "App"


def test_compact_theme_picker_is_recreated_on_language_change():
    source = (APP / "CompactSettingsView.swift").read_text()
    picker = source.split("private var themePicker: some View {", 1)[1].split(
        "private var adaptiveThemePicker:", 1)[0]
    assert '.accessibilityIdentifier("settings.theme")' in picker
    assert ".id(appLanguage)" in picker, (
        "SwiftUI can cache the previous locale's segmented Picker item titles"
    )
    assert "mode.title(forLanguage: appLanguage)" in picker
    appearance = (APP / "AppearanceMode.swift").read_text()
    assert "AppL10n.tr(key, language: language)" in appearance
    for key in ("Системная", "Светлая", "Тёмная"):
        assert f'AppL10n.tr("{key}")' in appearance


def test_all_shipped_locales_have_theme_option_names():
    localizations = sorted((BASE / "Resources").glob("*.lproj"))
    assert len(localizations) == 64
    for locale in localizations:
        text = (locale / "Localizable.strings").read_text()
        for key in ("Системная", "Светлая", "Тёмная"):
            assert re.search(rf'^"{key}"\s*=\s*"[^"]+"\s*;', text, re.M), (
                f"{locale.name} is missing the theme segment translation {key}"
            )
    english = (BASE / "Resources/en.lproj/Localizable.strings").read_text()
    for russian, expected in (("Системная", "System"), ("Светлая", "Light"), ("Тёмная", "Dark")):
        assert f'"{russian}" = "{expected}";' in english


def test_in_app_language_switch_has_simulator_ui_regression():
    text = (BASE / "Tests/UITests/CompactSettingsUITests.swift").read_text()
    assert "testThemeSegmentsRelocalizeWithoutRestartingAppOrChangingAppearance" in text
    assert 'theme.buttons["System"]' in text
    assert 'theme.buttons["Системная"]' in text
