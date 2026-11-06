"""Fail-closed contract: Shortcuts/app automation errors never display NSError text."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "mobile/ios/App/ApplicationExclusionsView.swift"
CORE = ROOT / "mobile/ios/SharedCore/AppAutomationFailureUX.swift"
VPN = ROOT / "mobile/ios/App/VPNShortcuts.swift"
RESOURCES = ROOT / "mobile/ios/Resources"


class AppAutomationSafeErrorContract(unittest.TestCase):
    def test_all_store_and_vpn_catches_use_fixed_diagnostic(self):
        source = APP.read_text()
        self.assertEqual(source.count('AppAutomationFailureUX.storage(translate: AppL10n.tr)'), 2)
        self.assertEqual(source.count('AppAutomationFailureUX.vpn(error, translate: AppL10n.tr)'), 2)
        self.assertEqual(source.count('catch {'), 4)
        self.assertNotIn('error.localizedDescription', source)
        self.assertNotIn('storageError = String(describing:', source)
        self.assertIn('try await AppRoutingVPNControl.applyBaseline(storedMode)', source)
        self.assertIn('try await AppRoutingVPNControl.applyBaseline(newValue)', source)
        self.assertIn('store.iosAppRoutingMode = newValue', source)

    def test_pure_diagnostics_do_not_materialize_any_untrusted_error_string(self):
        source = CORE.read_text()
        self.assertIn('ProxyFailureReason.classify(error)', source)
        self.assertIn('reason == .unknown ? "VPN" : reason.code', source)
        self.assertIn('translate("Сохранить")', source)
        self.assertIn('translate("Настройки")', source)
        self.assertIn('translate("Недоступен")', source)
        for forbidden in ('localizedDescription', 'userInfo', 'NSError(', 'NSLog(',
                          'UserDefaults', 'Keychain', 'URLSession', 'Socket',
                          '.domain', 'error as?', 'String(describing:', 'print('):
            self.assertNotIn(forbidden, source)

    def test_all_display_keys_exist_in_exactly_64_locale_catalogs(self):
        files = sorted(RESOURCES.glob('*.lproj/Localizable.strings'))
        self.assertEqual(len(files), 64)
        for file in files:
            with self.subTest(locale=file.parent.name):
                catalog = file.read_text()
                for key in ('Сохранить', 'Настройки', 'Недоступен'):
                    self.assertIn('"' + key + '" = ', catalog)

    def test_no_vpn_command_semantics_or_privileges_added(self):
        source = CORE.read_text() + APP.read_text()
        for forbidden in ('setTunnelNetworkSettings', 'startVPNTunnel', 'stopVPNTunnel',
                          'NEVPNManager', 'NEPacketTunnelProvider', 'tun2proxy',
                          'SecItemAdd', 'SecItemDelete'):
            self.assertNotIn(forbidden, source)
        self.assertIn('try await setConnected(mode == .normallyOn)', VPN.read_text())
