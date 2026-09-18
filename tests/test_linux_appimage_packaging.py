import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = (ROOT / "tools" / "build_linux_appimage.sh").read_text(encoding="utf-8")
FETCH = (ROOT / "tools" / "fetch_appimage_toolchain.sh").read_text(encoding="utf-8")
LOCK = (ROOT / "tools" / "appimage-toolchain.lock").read_text(encoding="utf-8")


class AppImagePackagingContractTests(unittest.TestCase):
    def test_appdir_contract_is_explicit(self):
        for token in ("AppRun", "arvectum-proxy-launcher.desktop", ".DirIcon", "usr/bin/arvectum-proxy-launcher"):
            self.assertIn(token, BUILD)

    def test_runtime_and_tool_are_hash_pinned(self):
        self.assertIn("APPIMAGETOOL_SHA256=", LOCK)
        self.assertIn("APPIMAGE_RUNTIME_SHA256=", LOCK)
        self.assertIn("sha256sum -c", FETCH)
        self.assertIn("sha256sum -c", BUILD)
        self.assertIn("--runtime-file", BUILD)

    def test_build_has_no_privileged_or_network_mutation(self):
        for forbidden in ("sudo ", "pkexec", "nmcli connection modify", "postinst"):
            self.assertNotIn(forbidden, BUILD)

    def test_builder_never_fetches_latest_implicitly(self):
        self.assertNotIn("/latest/", LOCK)
        self.assertNotIn("curl ", BUILD)
        self.assertIn("APPIMAGE_RUNTIME_SOURCE_COMMIT=", LOCK)

    def test_appimage_contains_product_and_third_party_notices(self):
        self.assertIn("usr/share/doc/arvectum-proxy-launcher", BUILD)
        self.assertIn('install -m644 LICENSE "$docdir/LICENSE.txt"', BUILD)
        self.assertIn('install -m644 THIRD_PARTY_NOTICES.txt "$docdir/THIRD_PARTY_NOTICES.txt"', BUILD)
        self.assertIn('install -m644 APPIMAGE_RUNTIME_LICENSE.txt "$docdir/APPIMAGE_RUNTIME_LICENSE.txt"', BUILD)

    def test_appimage_is_not_left_in_commercial_hold_by_builder(self):
        self.assertNotIn("remains EXCLUDED from promoted commercial scope", BUILD)


if __name__ == "__main__":
    unittest.main()
