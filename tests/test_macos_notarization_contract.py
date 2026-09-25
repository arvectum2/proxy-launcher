import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
DMG_SCRIPT = (ROOT / "tools" / "build_macos_dmg.sh").read_text(encoding="utf-8")
SIGN_APP_SCRIPT = (ROOT / "tools" / "sign_macos_app.sh").read_text(encoding="utf-8")
APP_NOTARY_SCRIPT = (ROOT / "tools" / "notarize_macos_app.sh").read_text(encoding="utf-8")
NOTARY_SCRIPT = (ROOT / "tools" / "notarize_macos_dmg.sh").read_text(encoding="utf-8")
RUNNER_SCRIPT = (ROOT / "tools" / "run_macos_production_signing.sh").read_text(encoding="utf-8")


class MacOSNotarizationContractTests(unittest.TestCase):
    def test_external_app_signer_requires_developer_id_and_product_identity(self):
        self.assertIn("Developer ID Application:", SIGN_APP_SCRIPT)
        self.assertIn("ru.arvectum.proxylauncher", SIGN_APP_SCRIPT)
        self.assertIn("--timestamp --options runtime", SIGN_APP_SCRIPT)
        self.assertIn("TeamIdentifier=VML75VY94V", SIGN_APP_SCRIPT)

    def test_app_notary_zips_staples_and_gatekeeper_checks(self):
        self.assertIn("--keepParent", APP_NOTARY_SCRIPT)
        self.assertIn("xcrun notarytool", APP_NOTARY_SCRIPT)
        self.assertIn('staple "$app"', APP_NOTARY_SCRIPT)
        self.assertIn('validate "$app"', APP_NOTARY_SCRIPT)
        self.assertIn('spctl -a -vv -t exec "$app"', APP_NOTARY_SCRIPT)

    def test_dmg_architecture_can_be_preserved_when_promoting_cloud_artifact(self):
        self.assertIn("APL_MACOS_PACKAGE_ARCH", DMG_SCRIPT)
        self.assertIn('"arm64"', DMG_SCRIPT)
        self.assertIn('"x86_64"', DMG_SCRIPT)

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

    def test_ephemeral_runner_is_current_main_only_and_one_job(self):
        self.assertIn("refusing non-current-main source", RUNNER_SCRIPT)
        self.assertIn("--ephemeral", RUNNER_SCRIPT)
        self.assertIn("registration-token", RUNNER_SCRIPT)
        self.assertIn("remove-token", RUNNER_SCRIPT)
        self.assertIn("runner_label", RUNNER_SCRIPT)
        self.assertIn("--event workflow_dispatch", RUNNER_SCRIPT)
        self.assertIn("gh workflow run macos-production-signing.yml", RUNNER_SCRIPT)

    def test_macos_production_path_is_compatible_with_system_bash_3(self):
        workflow = (ROOT / ".github" / "workflows" / "macos-production-signing.yml").read_text(encoding="utf-8")
        self.assertNotIn("${source_sha,,}", RUNNER_SCRIPT)
        self.assertNotIn("${SOURCE_SHA,,}", workflow)
        self.assertNotIn("${GITHUB_SHA,,}", workflow)
        self.assertIn("tr '[:upper:]' '[:lower:]'", RUNNER_SCRIPT)
        self.assertIn("SOURCE_SHA_LOWER", workflow)

    def test_notary_staples_and_gatekeeper_checks_dmg(self):
        self.assertIn("xcrun stapler", NOTARY_SCRIPT)
        self.assertIn('staple "$dmg"', NOTARY_SCRIPT)
        self.assertIn('validate "$dmg"', NOTARY_SCRIPT)
        self.assertIn("spctl -a -vv -t open --context context:primary-signature", NOTARY_SCRIPT)


if __name__ == "__main__":
    unittest.main()
