import importlib.util
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8-sig")


def load_version_generator():
    path = ROOT / "tools" / "generate_windows_version_info.py"
    spec = importlib.util.spec_from_file_location("apl_windows_version_info", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class WindowsProductizationTests(unittest.TestCase):
    def test_version_info_is_derived_from_canonical_version(self):
        version = read("VERSION").strip()
        generator = load_version_generator()
        rendered = generator.render(version)
        self.assertIn("StringStruct('CompanyName', 'ООО «Арвектум»')", rendered)
        self.assertIn("StringStruct('ProductName', 'Arvectum Proxy Launcher')", rendered)
        self.assertIn(f"StringStruct('ProductVersion', '{version}')", rendered)
        core = version.split("-", 1)[0].split("+", 1)[0]
        self.assertIn(f"StringStruct('FileVersion', '{core}.0')", rendered)
        self.assertIn("StringStruct('OriginalFilename', 'Arvectum Proxy Launcher.exe')", rendered)

    def test_canonical_build_regenerates_and_checks_final_pe_metadata(self):
        script = read("tools/clean_build_windows.ps1")
        self.assertIn("generate_windows_version_info.py", script)
        for field in (
            "CompanyName", "FileDescription", "ProductName", "ProductVersion",
            "FileVersion", "OriginalFilename",
        ):
            self.assertIn(field, script)
        self.assertIn("release\\README_WINDOWS_PORTABLE.txt", script)
        self.assertNotIn("release\\README_PORTABLE_P0.txt", script)

    def test_installer_has_canonical_branding_and_fixture_boundary(self):
        iss = read("installer/ArvectumProxyLauncher.iss")
        self.assertIn('#define AppPublisher "ООО «Арвектум»"', iss)
        self.assertIn("VersionInfoCompany={#AppPublisher}", iss)
        self.assertIn("VersionInfoDescription=Arvectum Proxy Launcher Windows Installer", iss)
        self.assertIn("VersionInfoProductTextVersion={#AppVersion}", iss)
        self.assertIn("AppPublisherURL={#AppPublisherURL}", iss)
        self.assertIn("AppSupportURL={#AppSupportURL}", iss)
        self.assertIn("SyntheticLifecycleFixture", iss)
        self.assertIn("synthetic-predecessor", iss)

    def test_upgrade_helper_distinguishes_upgrade_from_repair(self):
        helper = read("installer/upgrade_helper.ps1")
        self.assertIn("function Get-MaintenanceKind", helper)
        self.assertIn("return 'INSTALL'", helper)
        self.assertIn("return 'UPGRADE'", helper)
        self.assertIn("return 'REPAIR'", helper)
        self.assertIn("maintenance mode: $maintenanceKind", helper)

    def test_rc_e2e_covers_complete_lifecycle(self):
        script = read("qa/windows_rc_e2e.ps1")
        for marker in (
            "Assert-InstallMode 'INSTALL'", "Assert-InstallMode 'UPGRADE'", "Assert-InstallMode 'REPAIR'",
            "fresh_install_smoke", "fresh_uninstall", "upgrade", "repair", "uninstall",
            "configuration_preserved", "foreign_startup_preserved",
        ):
            self.assertIn(marker, script)
        self.assertIn("synthetic_lifecycle_fixture", script)
        self.assertIn("arvectum.proxy.windows-rc-e2e.v2", script)

    def test_rc_acceptance_is_fail_closed_and_excludes_fixture(self):
        script = read("tools/windows_rc_acceptance.ps1")
        self.assertIn("artifact.synthetic.excluded", script)
        self.assertIn("synthetic-predecessor", script)
        self.assertIn("windows-rc-acceptance.v1", script)
        self.assertIn("Windows RC acceptance FAIL", script)
        self.assertIn("production_embedded_signing_activated = $false", script)

    def test_windows_installer_workflow_executes_productization_gates(self):
        workflow = read(".github/workflows/windows-installer.yml")
        self.assertIn("-SyntheticPredecessor", workflow)
        self.assertIn("./qa/windows_rc_e2e.ps1", workflow)
        self.assertIn("./tools/windows_rc_acceptance.ps1", workflow)
        self.assertIn("out/windows-rc-e2e.json", workflow)
        self.assertIn("out/windows-rc-acceptance.json", workflow)

    def test_final_user_docs_have_no_internal_milestone_labels(self):
        for path in ("INSTALL.txt", "release/README_WINDOWS_PORTABLE.txt"):
            text = read(path)
            self.assertIsNone(re.search(r"\bP0(?:\.\d+)?\b|\bRC\d*\b", text), path)

    def test_gate_and_task_docs_present(self):
        for path in (
            "APL-WIN-010_FINAL_EXECUTABLE_METADATA_WINDOWS_BRANDING.md",
            "APL-WIN-011_RELEASE_CANDIDATE_PACKAGING_ACCEPTANCE_MATRIX.md",
            "APL-WIN-012_WINDOWS_RC_E2E.md",
            "APL-WIN-013_WINDOWS_SUPPORTABILITY_INSTALL_DOCS.md",
            "GATE_R6_WINDOWS_PRODUCTIZATION.md",
        ):
            self.assertTrue((ROOT / path).is_file(), path)


if __name__ == "__main__":
    unittest.main()
