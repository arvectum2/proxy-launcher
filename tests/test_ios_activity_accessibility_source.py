"""Static regression for Activity VoiceOver target and 64 existing translations."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mobile/ios/App/ActivityScreenView.swift"
RESOURCES = ROOT / "mobile/ios/Resources"


class ActivityAccessibilitySourceTests(unittest.TestCase):
    def test_refresh_button_label_owns_at_least_44x44_hit_area(self):
        source = SOURCE.read_text()
        body = source.split("private var refreshButton: some View", 1)[1].split("@ViewBuilder", 1)[0]
        self.assertIn('Text(AppL10n.tr("Обновить"))', body)
        self.assertIn('.frame(minWidth: 48, minHeight: 48)', body)
        self.assertIn('.contentShape(Rectangle())', body)
        self.assertIn('.buttonStyle(.plain)', body)
        self.assertIn('.accessibilityIdentifier("activity.refresh")', body)
        self.assertNotIn('Button(AppL10n.tr("Обновить"))', body)

    def test_empty_activity_state_uses_all_available_native_translations(self):
        source = SOURCE.read_text()
        self.assertIn('Text(AppL10n.tr("Событий пока нет"))', source)
        self.assertNotIn('Text("Событий пока нет")', source)
        locales = sorted(RESOURCES.glob("*.lproj/Localizable.strings"))
        self.assertEqual(len(locales), 64)
        for file in locales:
            with self.subTest(locale=file.parent.stem):
                self.assertIn('"Событий пока нет" = ', file.read_text())

    def test_activity_source_does_not_modify_routing_or_credentials(self):
        source = SOURCE.read_text()
        for forbidden in ('setTunnelNetworkSettings', 'SecItem', 'Keychain',
                          'tunnelProviderManager', 'writePackets', 'IPRoute'):
            self.assertNotIn(forbidden, source)
