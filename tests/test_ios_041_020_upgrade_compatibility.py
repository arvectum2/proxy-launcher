"""Frozen iOS 0.1.41(46) persistence contract -> iOS 0.2.0(48).

Baseline compared against accepted build 46 source, without user profiles.
"""
import plistlib
import re
import unittest
from pathlib import Path

IOS = Path(__file__).resolve().parents[1] / "mobile" / "ios"
LEGACY_SHARED_DEFAULT_KEYS = {
    "profiles": "profiles.v1",
    "selectedProfileID": "selected_profile_id",
    "automaticSelection": "automatic_selection",
    "primaryProfileID": "primary_profile_id",
    "restorePolicy": "restore_policy",
    "exclusions": "site_exclusions",
    "lastAutoProfileID": "last_auto_profile_id",
    "recentlyFailedProfileID": "recently_failed_profile_id",
    "recentlyFailedAt": "recently_failed_at",
    "lastFailoverAt": "last_failover_at",
    "iosAppRoutingMode": "ios_app_routing_mode",
}


class Legacy041CompatibilityTests(unittest.TestCase):
    def test_keys_remain_unchanged_and_legacy_exclusions_are_readable(self):
        source = (IOS / "Shared" / "ProfileStore.swift").read_text()
        for name, key in LEGACY_SHARED_DEFAULT_KEYS.items():
            with self.subTest(name=name):
                self.assertRegex(source, rf'static let {name} = "{re.escape(key)}"')
        self.assertIn("decoder.decode([ProxyProfile].self, from: data)", source)
        self.assertIn("defaults.stringArray(forKey: Key.exclusions)", source)
        self.assertIn("defaults.stringArray(forKey: Key.manualExclusions)", source)
        self.assertIn("var automaticSiteExpansion: Bool", source)

    def test_app_group_and_keychain_account_identity_stable(self):
        app_shared = (IOS / "Shared" / "AppShared.swift").read_text()
        for literal in (
            "group.ru.arvectum.proxylauncher.ios",
            "ru.arvectum.proxylauncher.ios.PacketTunnel",
            "ru.arvectum.proxylauncher.ios.credentials",
            "VML75VY94V.ru.arvectum.proxylauncher.ios.shared",
        ):
            self.assertIn(literal, app_shared)
        ent = plistlib.loads((IOS / "Config" / "App.entitlements").read_bytes())
        self.assertIn("group.ru.arvectum.proxylauncher.ios",
                      ent["com.apple.security.application-groups"])
        self.assertIn("$(AppIdentifierPrefix)ru.arvectum.proxylauncher.ios.shared",
                      ent["keychain-access-groups"])
        store = (IOS / "Shared" / "ProfileStore.swift").read_text()
        for fragment in ("kSecClassGenericPassword", "AppShared.keychainService",
                         "id.uuidString", "kSecAttrAccessGroup",
                         "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"):
            self.assertIn(fragment, store)

    def test_041_codable_wire_values_and_restore_policy_unchanged(self):
        model = (IOS / "SharedCore" / "ProxyModel.swift").read_text()
        for literal in ('case auto = "AUTO"', 'case https = "HTTPS"',
                        'case http = "HTTP"', 'case socks5 = "SOCKS5"',
                        'case stayOnCurrent = "STAY_ON_CURRENT"',
                        'case returnToPrimary = "RETURN_TO_PRIMARY"'):
            self.assertIn(literal, model)
        self.assertIn("struct ProxyProfile: Codable", model)

    def test_new_encrypted_backup_is_additive(self):
        # .aplbackup was introduced after the published 0.1.41 version.
        restore = (IOS / "SharedCore" / "ProfileBackupRestorePlan.swift").read_text()
        self.assertIn("ProfileBackupRestorePlan", restore)
        view = (IOS / "App" / "ProfileBackupView.swift").read_text()
        self.assertIn(".aplbackup", view)


if __name__ == "__main__":
    unittest.main()
