import re
import unittest
from pathlib import Path

import proxy_core as core
import proxy_gui as gui

ROOT = Path(__file__).resolve().parents[1]
SEMVER_REGEX = r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"


class VersionPolicyTests(unittest.TestCase):
    def read(self, name: str) -> str:
        return (ROOT / name).read_text(encoding="utf-8-sig")

    def get_version(self) -> str:
        return (ROOT / "VERSION").read_text(encoding="utf-8-sig").strip()

    def test_version_file_exists_and_matches_semver(self):
        version_file = ROOT / "VERSION"
        self.assertTrue(version_file.is_file(), "VERSION file must exist at repo root")
        version = self.get_version()
        self.assertRegex(version, SEMVER_REGEX, f"VERSION '{version}' is not valid SemVer")
        self.assertNotIn(" ", version)
        self.assertFalse(version.startswith("v"), "VERSION should not contain leading 'v'")

    def test_proxy_core_app_version_matches_version_file(self):
        version = self.get_version()
        self.assertEqual(core.APP_VERSION, version)
        self.assertEqual(gui.APP_VERSION, version)

    def test_engineering_milestone_is_separated_and_not_in_version(self):
        version = self.get_version()
        milestone = getattr(core, "ENGINEERING_MILESTONE", None)
        self.assertIsNotNone(milestone, "core.ENGINEERING_MILESTONE must be defined")
        self.assertNotIn(milestone, version, "Engineering milestone must not be part of VERSION")
        for forbidden in ("P0", "P0.2", "P0.4", "RC", "RC2", "final", "latest", "fixed"):
            self.assertNotIn(forbidden, version.split("-")[0], f"Forbidden milestone/word '{forbidden}' in public version")

    def test_version_info_metadata_matches_canonical_version(self):
        version = self.get_version()
        info_text = self.read("version_info.txt")

        # Check ProductVersion
        prod_match = re.search(r"StringStruct\('ProductVersion',\s*'([^']+)'\)", info_text)
        self.assertTrue(prod_match, "ProductVersion StringStruct not found in version_info.txt")
        self.assertEqual(prod_match.group(1), version)

        # SemVer MAJOR.MINOR.PATCH -> FileVersion MAJOR.MINOR.PATCH.0
        parts = version.split("-")[0].split(".")
        self.assertEqual(len(parts), 3, "Expected 3 parts in SemVer numeric version")
        expected_filevers = f"{parts[0]}.{parts[1]}.{parts[2]}.0"
        expected_tuple_str = f"({parts[0]},{parts[1]},{parts[2]},0)"

        file_match = re.search(r"StringStruct\('FileVersion',\s*'([^']+)'\)", info_text)
        self.assertTrue(file_match, "FileVersion StringStruct not found in version_info.txt")
        self.assertEqual(file_match.group(1), expected_filevers)

        compact_info = info_text.replace(" ", "").replace("\r", "").replace("\n", "")
        self.assertIn(f"filevers={expected_tuple_str}", compact_info)
        self.assertIn(f"prodvers={expected_tuple_str}", compact_info)

    def test_active_platform_builders_use_canonical_version_source(self):
        version = self.get_version()
        self.assertEqual(version, "0.2.11")

        live_paths = {
            "macOS app": "tools/build_macos_app.sh",
            "macOS DMG": "tools/build_macos_dmg.sh",
            "Windows portable": "tools/clean_build_windows.ps1",
            "Windows installer": "tools/build_windows_installer.ps1",
            "Linux DEB": "tools/build_linux_deb.sh",
            "Linux RPM": "tools/build_linux_rpm.sh",
            "Linux AppImage": "tools/build_linux_appimage.sh",
        }
        for label, path in live_paths.items():
            with self.subTest(platform_builder=label):
                text = self.read(path)
                self.assertIn("VERSION", text)

        installer = self.read("installer/ArvectumProxyLauncher.iss")
        self.assertIn("#ifndef AppVersion", installer)
        self.assertIn("#error AppVersion must be supplied", installer)
        self.assertNotIn('#define AppVersion "0.2.', installer)

        # The root-level 0.2.2 installer is retained as legacy/history and
        # must never become a canonical build input again.
        for path in (
            ".github/workflows/windows-installer.yml",
            "tools/build_windows_installer.ps1",
        ):
            self.assertNotIn("ArvectumProxyLauncherSetup.iss", self.read(path))

    def test_canonical_artifact_naming_uses_canonical_version(self):
        policy_text = self.read("RELEASE_POLICY.md")
        self.assertIn("Arvectum-Proxy-Launcher-X.Y.Z-windows-x64-portable.zip", policy_text)
        self.assertIn("Arvectum-Proxy-Launcher-X.Y.Z-windows-x64-setup.exe", policy_text)
        self.assertIn("Arvectum-Proxy-Launcher-X.Y.Z-macos-arm64.dmg", policy_text)
        self.assertIn("Arvectum-Proxy-Launcher-X.Y.Z-astra-linux-amd64.deb", policy_text)
        self.assertIn("Arvectum-Proxy-Launcher-X.Y.Z-redos-linux-x86_64.rpm", policy_text)
        self.assertIn("Arvectum-Proxy-Launcher-X.Y.Z-linux-x86_64.tar.gz", policy_text)
        self.assertIn("SHA256SUMS.txt", policy_text)

        workflow_text = self.read(".github/workflows/windows-p0.yml")
        self.assertNotIn("Arvectum-Proxy-Launcher-Windows-P0", workflow_text)

        clean_build_script = self.read("tools/clean_build_windows.ps1")
        self.assertIn("VERSION", clean_build_script)
        self.assertIn("SHA256SUMS.txt", clean_build_script)
        self.assertIn("Arvectum-Proxy-Launcher-$ProductVersion-windows-x64-portable", clean_build_script)


if __name__ == "__main__":
    unittest.main()