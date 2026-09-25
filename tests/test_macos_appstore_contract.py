import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
STORE = ROOT / "mobile" / "macos-appstore"
PROJECT = (STORE / "project.yml").read_text(encoding="utf-8")
FETCH = (STORE / "Tools" / "fetch_tun2proxy.py").read_text(encoding="utf-8")
APP_SHARED = (STORE / "Shared" / "AppShared.swift").read_text(encoding="utf-8")


def plist(path):
    with path.open("rb") as stream:
        return plistlib.load(stream)


class MacOSAppStoreContractTests(unittest.TestCase):
    def test_store_lane_is_separate_from_developer_id_bundle(self):
        self.assertIn("ru.arvectum.proxylauncher.macos", PROJECT)
        self.assertIn("ru.arvectum.proxylauncher.macos.PacketTunnel", PROJECT)
        self.assertNotIn("Developer ID Application", PROJECT)
        self.assertIn('CODE_SIGN_IDENTITY: "Apple Distribution"', PROJECT)
    def test_catalyst_is_explicit_and_does_not_derive_bundle_identifier(self):
        self.assertIn("SUPPORTS_MACCATALYST: YES", PROJECT)
        self.assertIn("DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER: NO", PROJECT)
        self.assertIn('MACCATALYST_DEPLOYMENT_TARGET: "12.0"', PROJECT)

    def test_app_and_extension_are_sandboxed_network_extension_clients(self):
        app = plist(STORE / "Config" / "App.entitlements")
        tunnel = plist(STORE / "Config" / "PacketTunnel.entitlements")
        for entitlements in (app, tunnel):
            self.assertIs(entitlements["com.apple.security.app-sandbox"], True)
            self.assertEqual(
                entitlements["com.apple.developer.networking.networkextension"],
                ["packet-tunnel-provider"],
            )
            self.assertIn(
                "VML75VY94V.ru.arvectum.proxylauncher.macos",
                entitlements["com.apple.security.application-groups"],
            )
        self.assertIs(app["com.apple.security.network.client"], True)
        self.assertIs(tunnel["com.apple.security.network.client"], True)
        self.assertIs(tunnel["com.apple.security.network.server"], True)

    def test_store_app_uses_mac_specific_shared_identity(self):
        self.assertIn("VML75VY94V.ru.arvectum.proxylauncher.macos", APP_SHARED)
        self.assertIn("ru.arvectum.proxylauncher.macos.PacketTunnel", APP_SHARED)
        self.assertIn("ru.arvectum.proxylauncher.macos.credentials", APP_SHARED)
        self.assertNotIn('group.ru.arvectum.proxylauncher.ios"', APP_SHARED)

    def test_tun2proxy_is_pinned_and_built_for_catalyst(self):
        self.assertIn('VERSION = "v0.8.3"', FETCH)
        self.assertIn('SOURCE_COMMIT = "e271de19683937f23d3f8f0eb4df0a61fc4a6e50"', FETCH)
        self.assertIn('RUST_TARGET = "aarch64-apple-ios-macabi"', FETCH)
        self.assertIn("-create-xcframework", FETCH)
        self.assertIn("disable-api-forced-exit-for-network-extension-live-restart", FETCH)

    def test_store_target_reuses_packet_tunnel_not_networksetup(self):
        self.assertIn("../ios/PacketTunnel", PROJECT)
        self.assertNotIn("macos_backend.py", PROJECT)
        self.assertNotIn("networksetup", PROJECT)


if __name__ == "__main__":
    unittest.main()
