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

    def test_bundle_version_is_bound_to_canonical_version_before_final_seal(self):
        self.assertIn('product_version="$(tr -d \'[:space:]\' < "$repo_root/VERSION")"', SCRIPT)
        self.assertIn('bundle_version="${product_version%%[-+]*}"', SCRIPT)
        self.assertIn('set_plist_string CFBundleShortVersionString "$bundle_version"', SCRIPT)
        self.assertIn('set_plist_string CFBundleVersion "$bundle_version"', SCRIPT)
        short_verify = SCRIPT.index("Print :CFBundleShortVersionString")
        build_verify = SCRIPT.index("Print :CFBundleVersion")
        resign = SCRIPT.index('codesign --force --deep --sign - "$app"')
        self.assertLess(short_verify, resign)
        self.assertLess(build_verify, resign)

    def test_production_signing_is_explicit_and_hardened(self):
        self.assertIn('APL_MACOS_SIGN_IDENTITY', SCRIPT)
        self.assertIn('Developer ID Application:', SCRIPT)
        self.assertIn('--timestamp --options runtime --sign "$sign_identity"', SCRIPT)
        self.assertIn("TeamIdentifier=VML75VY94V", SCRIPT)

    def test_default_path_still_supports_ad_hoc_ci_builds(self):
        self.assertIn('codesign --force --deep --sign - "$app"', SCRIPT)

    def test_app_bundle_contains_product_and_third_party_notices(self):
        self.assertIn('Contents/Resources', SCRIPT)
        self.assertIn('install -m644 LICENSE "$resources/LICENSE.txt"', SCRIPT)
        self.assertIn('install -m644 THIRD_PARTY_NOTICES.txt "$resources/THIRD_PARTY_NOTICES.txt"', SCRIPT)

    def test_final_bundle_is_resealed_after_license_resources_are_added(self):
        license_verify = SCRIPT.index('third_party_license_bundle.py --verify')
        production_seal = SCRIPT.index('sign_identity="${APL_MACOS_SIGN_IDENTITY:-}"')
        production_verify = SCRIPT.index('codesign --verify --deep --strict "$app"', production_seal)
        ad_hoc_seal = SCRIPT.index('codesign --force --deep --sign - "$app"')
        self.assertLess(license_verify, production_seal)
        self.assertLess(production_seal, production_verify)
        self.assertLess(production_seal, ad_hoc_seal)


if __name__ == '__main__':
    unittest.main()
