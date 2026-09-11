from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
EXTRACTOR = ROOT / "tools" / "bootstrap" / "apl-win-014" / "extract_pyinstaller_onefile_binaries.py"
WORKFLOW = ROOT / ".github" / "workflows" / "apl-win-014-final-0-2-4.yml"
POLICY_HELPER = ROOT / "tools" / "apl_win_014_prepare_0_2_4_supplemental_policy.ps1"
RUNBOOK = ROOT / "docs" / "APL_WIN_014_FINAL_STAND_RUNBOOK.md"


class AplWin014PyInstallerRuntimeTrustTests(unittest.TestCase):
    def test_static_extractor_is_exact_binary_only(self):
        text = EXTRACTOR.read_text(encoding="utf-8")
        for expected in (
            "CArchiveReader",
            'typecode != "b"',
            "source_application_sha256",
            "python312.dll",
            "ucrtbase.dll",
            "binary_count",
            "total_size",
        ):
            self.assertIn(expected, text)
        self.assertNotIn("subprocess", text)

    def test_final_workflow_seals_pyinstaller_native_payload(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        for expected in (
            "extract_pyinstaller_onefile_binaries.py",
            "pyinstaller-runtime",
            "pyinstaller-onefile-runtime-evidence.json",
            "PYINSTALLER_NATIVE_RUNTIME",
            ".build-venv",
            "python312.dll",
            "ucrtbase.dll",
        ):
            self.assertIn(expected, text)

    def test_policy_helper_hash_authorizes_exact_extracted_native_payload(self):
        text = POLICY_HELPER.read_text(encoding="utf-8")
        for expected in (
            "pyinstaller_runtime_evidence_filename",
            "pyinstaller_runtime_directory",
            "source_application_sha256",
            "pyinstaller_runtime_binary",
            "python312.dll",
            "ucrtbase.dll",
            "New-CIPolicy",
            "-Level Hash",
        ):
            self.assertIn(expected, text)
        self.assertNotIn("Disabled:Script Enforcement' | Out-Null", text)

    def test_runbook_documents_mei_native_trust_boundary(self):
        text = RUNBOOK.read_text(encoding="utf-8")
        for expected in (
            "%TEMP%\\_MEI",
            "python312.dll",
            "ucrtbase.dll",
            "exact-hash",
            "PyInstaller",
        ):
            self.assertIn(expected, text)


if __name__ == "__main__":
    unittest.main()
