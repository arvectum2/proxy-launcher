from pathlib import Path
import os
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "tools" / "windows_app_control_prepare_harness_script_trust_clm.ps1"
PROBE = ROOT / "tools" / "windows_app_control_harness_language_probe.ps1"

BASE_POLICY_ID = "dc1c604c-46ea-40b7-9f47-cf582b225d5e"
PRODUCTION_SETUP_SHA256 = "5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class WindowsAppControlClmHarnessTrustTests(unittest.TestCase):
    def test_clm_bootstrap_is_bound_to_canonical_base_and_production_setup(self):
        body = text(BOOTSTRAP)
        self.assertIn(BASE_POLICY_ID, body)
        self.assertIn(PRODUCTION_SETUP_SHA256, body)
        self.assertIn("Arvectum APL-WIN-014 Lab Base", body)
        self.assertIn("Enabled:Audit Mode", body)
        self.assertIn("Enabled:Allow Supplemental Policies", body)

    def test_clm_bootstrap_has_no_full_language_only_entry_guards_or_known_forbidden_methods(self):
        body = text(BOOTSTRAP)
        forbidden = (
            "#Requires",
            "[Environment]::",
            "[System.Environment]::",
            "[IO.Path]::",
            "[System.IO.Path]::",
            "New-Object",
            ".WaitForExit(",
            ".ToLowerInvariant(",
            ".Trim(",
            ".Substring(",
            "[Guid]",
            "[DateTime]::",
            "[Security.Principal",
            "[System.Security.Principal",
        )
        for token in forbidden:
            self.assertNotIn(token, body, token)

    def test_clm_bootstrap_authors_script_rules_without_trusting_a_general_interpreter(self):
        body = text(BOOTSTRAP)
        policy_line = next(line for line in body.splitlines() if line.strip().startswith("New-CIPolicy "))
        self.assertIn("-Level Hash", policy_line)
        self.assertNotIn("-NoScript", policy_line)
        self.assertIn("script-scan-root", body)
        self.assertIn("verify_russian_release.ps1", body)
        self.assertIn("python_authorized=$false", body)
        self.assertIn("general_interpreter_authorized=$false", body)
        self.assertIn("Copy-Item -LiteralPath $source -Destination $destination", body)
        self.assertIn("Copy-Item -LiteralPath $releaseVerifier -Destination $releaseVerifierStaged", body)

    def test_clm_bootstrap_never_deploys_removes_or_weakens_policy(self):
        body = text(BOOTSTRAP).lower()
        for forbidden in (
            "& $citool --update-policy",
            "start-process -filepath $citool",
            "--remove-policy",
            "set-ruleoption",
            "verifiedandreputablepolicystate",
            "reg.exe add",
            "disable-windowsoptionalfeature",
        ):
            self.assertNotIn(forbidden, body)
        self.assertIn("policy_deployment='not performed'", body)
        self.assertIn("security_controls_weakened=$false", body)

    def test_harness_trust_scope_is_exact_and_contains_only_required_powershell_entrypoints(self):
        body = text(BOOTSTRAP)
        required = {
            "windows_app_control_prepare_final_stand.ps1",
            "windows_app_control_run_final_stand.ps1",
            "windows_app_control_recover_0_2_2_baseline.ps1",
            "windows_app_control_legacy_baseline_trust_pack.ps1",
            "windows_app_control_prepare_production_runtime_trust.ps1",
            "windows_app_control_enterprise_trust_pack.ps1",
            "windows_app_control_inno_runtime_material.ps1",
            "windows_app_control_verify_runtime_trust_pack.ps1",
            "windows_app_control_local_gate_complete.ps1",
            "windows_app_control_enforced_acceptance.ps1",
            "windows_app_control_preverified_release.ps1",
            "windows_app_control_harness_language_probe.ps1",
        }
        for filename in required:
            self.assertIn(f"'{filename}'", body)
        self.assertNotIn("*.ps1", body)
        self.assertNotIn("-Recurse", body)

    def test_language_probe_requires_real_fulllanguage_and_uses_previous_failure_as_positive_probe(self):
        body = text(PROBE)
        self.assertIn("#Requires -Version 5.1", body)
        self.assertIn("#Requires -RunAsAdministrator", body)
        self.assertIn("LanguageMode", body)
        self.assertIn("FullLanguage", body)
        self.assertIn("[Environment]::GetFolderPath('MyDocuments')", body)
        self.assertIn("harness App Control script trust: PASS", body)

    def test_scripts_are_ascii_safe(self):
        for path in (BOOTSTRAP, PROBE):
            path.read_bytes().decode("ascii")

    def test_scripts_parse_with_windows_powershell_when_available(self):
        if os.name != "nt":
            return
        for path in (BOOTSTRAP, PROBE):
            escaped = str(path).replace("'", "''")
            command = (
                "$e=$null;$t=$null;"
                f"[void][System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$t,[ref]$e);"
                "if($e.Count){$e|ForEach-Object{Write-Error $_.Message};exit 1}"
            )
            completed = subprocess.run(
                ["powershell.exe", "-NoProfile", "-Command", command],
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr or completed.stdout)


if __name__ == "__main__":
    unittest.main()
