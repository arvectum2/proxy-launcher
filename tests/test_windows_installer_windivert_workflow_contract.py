import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "windows-installer.yml"
BUILDER = ROOT / "tools" / "build_windows_windivert_stack_bundle.ps1"
HELPER = ROOT / "installer" / "windivert_service_helper.ps1"


class WindowsInstallerWinDivertWorkflowContractTests(unittest.TestCase):
    def test_canonical_installer_builds_and_embeds_production_windivert(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        bundle_step = text.index(
            "- name: Build exact production WinDivert stack bundle"
        )
        portable_step = text.index(
            "- name: Embed production WinDivert bootstrap into portable"
        )
        installer_step = text.index(
            "- name: Compile current canonical installer and verify Setup metadata"
        )
        self.assertLess(bundle_step, portable_step)
        self.assertLess(portable_step, installer_step)
        portable_block = text[portable_step:installer_step]
        self.assertIn(
            "./tools/package_windows_portable_windivert.ps1",
            portable_block,
        )
        self.assertIn(
            "-WinDivertStackBundle 'out/windows-windivert-stack'",
            portable_block,
        )

        installer_block = text[
            installer_step:
            text.index(
                "- name: Windows installer #171 portable transition",
                installer_step,
            )
        ]
        self.assertIn(
            "./tools/build_windows_installer.ps1",
            installer_block,
        )
        self.assertIn(
            "-WinDivertStackBundle 'out/windows-windivert-stack'",
            installer_block,
        )
        self.assertNotIn("-NativeStackBundle", installer_block)
        self.assertNotIn("-WindowsAppExclusionsPreview", installer_block)

    def test_synthetic_predecessor_remains_without_production_driver_payload(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        predecessor = text.index(
            "- name: Build synthetic predecessor lifecycle fixture"
        )
        installer = text.index(
            "- name: Compile current canonical installer and verify Setup metadata"
        )
        block = text[predecessor:installer]
        self.assertIn("-SyntheticPredecessor", block)
        self.assertNotIn("-WinDivertStackBundle", block)
        self.assertNotIn("-NativeStackBundle", block)

    def test_helper_does_not_depend_on_programdata_environment_variable(self):
        text = HELPER.read_text(encoding="utf-8-sig")
        self.assertIn(
            "[Environment+SpecialFolder]::CommonApplicationData",
            text,
        )
        self.assertIn("[Environment]::GetFolderPath(", text)
        self.assertNotIn("$env:ProgramData", text)
    def test_workflow_parses_all_windivert_installer_helpers(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        for required in (
            "tools/build_windows_windivert_stack_bundle.ps1",
            "tools/package_windows_portable_windivert.ps1",
            "tools/stage_windows_windivert.ps1",
            "installer/windivert_service_helper.ps1",
            "tests.test_windows_installer_windivert_workflow_contract",
        ):
            self.assertIn(required, text)

    def test_bundle_builder_uses_pinned_stage_and_native_service_sources(self):
        text = BUILDER.read_text(encoding="utf-8-sig")
        self.assertIn("tools\\stage_windows_windivert.ps1", text)
        self.assertIn("windivert_service_main.cpp", text)
        self.assertIn("windivert_service_protocol.cpp", text)
        self.assertIn("windivert_routing_session.cpp", text)
        self.assertIn("/W4 /WX", text)
        self.assertIn("/MT /O2", text)
        self.assertIn("ArvectumProxyWinDivertRoutingService.exe", text)
        self.assertIn("windivert-dependency.json", text)
        self.assertIn("arvectum.proxy.windows-windivert-build.v1", text)
        self.assertIn("source_commit = (git rev-parse HEAD).Trim()", text)


if __name__ == "__main__":
    unittest.main()
