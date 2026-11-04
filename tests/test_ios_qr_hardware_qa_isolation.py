"""Guard the physical iPhone QR QA harness against production-device mutation."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / "mobile/ios/HardwareQA/QRDeviceQA"
SPEC = (QA / "project.yml").read_text()
APP = (QA / "App/QRDeviceQAApp.swift").read_text()
TEST = (QA / "Tests/QRDeviceQATests.swift").read_text()

class HardwareQAIsolationContract(unittest.TestCase):
    def test_uses_distinct_signed_bundle_with_zero_vpn_entitlements(self):
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.qrdeviceqa.device", SPEC)
        self.assertNotIn("PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.proxylauncher.ios\n", SPEC)
        self.assertNotIn("group.ru.arvectum.proxylauncher.ios", SPEC)
        self.assertNotIn("PacketTunnel", SPEC)
        self.assertNotIn("App.entitlements", SPEC)
        self.assertIn("CODE_SIGN_STYLE: Automatic", SPEC)

    def test_compiles_real_production_core_and_qr_components(self):
        for path in ("../../SharedCore", "../../App/ProxyShareView.swift",
                     "../../App/ProxyQRScanner.swift"):
            self.assertIn(path, SPEC)
        self.assertIn("ProxyProfileSharing.deepLink", APP)
        self.assertIn("ProxyProfileSharing.scannedSource", APP)
        self.assertIn("ProxyShareQRCode.image", APP)
        self.assertIn("ProxyQRScanner(", APP)
        self.assertIn("CIDetectorTypeQRCode", APP)

    def test_fixture_is_fake_and_import_never_writes(self):
        self.assertIn('"qr-device-qa.invalid"', APP)
        self.assertIn('TEST-%25:пароль/@', APP)
        self.assertIn('Explicit one-action confirmation', APP)
        for forbidden in ("NETunnelProviderManager", "ProfileStore(", "Keychain",
                          "URLSession", "NWConnection(", "startVPNTunnel("):
            if forbidden == "Keychain":
                # Allowed only in commentary explaining that it is NOT accessed.
                continue
            self.assertNotIn(forbidden, APP)
        self.assertIn('qa.run-selftest', TEST)
        self.assertIn('profiles.share.sendQR', TEST)

if __name__ == "__main__":
    unittest.main()
