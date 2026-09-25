import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
DMG_SCRIPT = (ROOT / "tools" / "build_macos_dmg.sh").read_text(encoding="utf-8")
NOTARY_SCRIPT = (ROOT / "tools" / "notarize_macos_dmg.sh").read_text(encoding="utf-8")


class MacOSNotarizationContractTests(unittest.TestCase):
    def test_dmg_production_signing_requires_developer_id(self):
        self.assertIn("APL_MACOS_SIGN_IDENTITY", DMG_SCRIPT)
        self.assertIn("Developer\\ ID\\ Application:*", DMG_SCRIPT)
        self.assertIn('codesign --force --timestamp --sign "$sign_identity" "$out"', DMG_SCRIPT)

    def test_notary_waits_for_accepted_result(self):
        self.assertIn("xcrun notarytool", NOTARY_SCRIPT)
        self.assertIn("--wait --output-format json", NOTARY_SCRIPT)
        self.assertIn('status != "Accepted"', NOTARY_SCRIPT)

    def test_notary_supports_keychain_or_api_key_credentials(self):
        self.assertIn("APL_NOTARY_KEYCHAIN_PROFILE", NOTARY_SCRIPT)
        self.assertIn("APL_NOTARY_KEY_PATH", NOTARY_SCRIPT)
        self.assertIn("APL_NOTARY_KEY_ID", NOTARY_SCRIPT)
        self.assertIn("APL_NOTARY_ISSUER_ID", NOTARY_SCRIPT)
    def test_notary_staples_and_gatekeeper_checks_dmg(self):
        self.assertIn("xcrun stapler", NOTARY_SCRIPT)
        self.assertIn('staple "$dmg"', NOTARY_SCRIPT)
        self.assertIn('validate "$dmg"', NOTARY_SCRIPT)
        self.assertIn("spctl -a -vv -t open --context context:primary-signature", NOTARY_SCRIPT)


if __name__ == "__main__":
    unittest.main()
