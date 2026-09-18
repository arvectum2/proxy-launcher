import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "tools" / "build_macos_app.sh").read_text(encoding="utf-8")


class MacOSAppPackagingContractTests(unittest.TestCase):
    def test_app_identity_is_stable(self):
        self.assertIn('Arvectum Proxy Launcher.app', SCRIPT)
        self.assertIn('ru.arvectum.proxylauncher', SCRIPT)
        self.assertIn('--windowed', SCRIPT)
        self.assertIn('--onedir', SCRIPT)

    def test_app_build_has_no_network_or_proxy_mutation(self):
        for token in ('networksetup -set', 'sudo ', 'pkexec', 'curl '):
            self.assertNotIn(token, SCRIPT)

    def test_canonical_assets_are_bundled(self):
        self.assertIn('assets/arvectum.icns', SCRIPT)
        self.assertIn('no_proxy.txt:.', SCRIPT)
        self.assertIn('assets:assets', SCRIPT)
        self.assertTrue((ROOT / "assets" / "arvectum-icon-macos.png").is_file())

    @unittest.skipUnless(sys.platform == "darwin", "macOS icon metadata requires sips")
    def test_canonical_icns_preserves_transparent_squircle(self):
        result = subprocess.run(
            [
                "sips",
                "-g", "pixelWidth",
                "-g", "pixelHeight",
                "-g", "hasAlpha",
                str(ROOT / "assets" / "arvectum.icns"),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertIn("pixelWidth: 1024", result.stdout)
        self.assertIn("pixelHeight: 1024", result.stdout)
        self.assertIn("hasAlpha: yes", result.stdout)

    def test_app_bundle_contains_product_and_third_party_notices(self):
        self.assertIn('Contents/Resources', SCRIPT)
        self.assertIn('install -m644 LICENSE "$resources/LICENSE.txt"', SCRIPT)
        self.assertIn('install -m644 THIRD_PARTY_NOTICES.txt "$resources/THIRD_PARTY_NOTICES.txt"', SCRIPT)

    def test_final_bundle_is_resealed_after_license_resources_are_added(self):
        license_verify = SCRIPT.index('third_party_license_bundle.py --verify')
        resign = SCRIPT.index('codesign --force --deep --sign - "$app"')
        signature_verify = SCRIPT.index('codesign --verify --deep --strict "$app"')
        self.assertLess(license_verify, resign)
        self.assertLess(resign, signature_verify)


if __name__ == '__main__':
    unittest.main()
