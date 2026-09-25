import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class WindowsPublicTrustTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8-sig")

    def test_machine_contract_separates_three_trust_layers(self):
        contract = json.loads(self.read("release/APL_REL_016_WINDOWS_PUBLIC_TRUST_CONTRACT.json"))
        self.assertEqual(contract["schema"], "arvectum.proxy.apl-rel-016.windows-public-trust.v1")
        self.assertEqual(contract["task"], "APL-REL-016")
        self.assertEqual(contract["immutable_predecessor"]["version"], "0.2.5")
        self.assertFalse(contract["immutable_predecessor"]["mutation_allowed"])
        self.assertEqual(contract["first_eligible_release"], "0.2.14")
        self.assertEqual(contract["current_public_baseline"]["version"], "0.2.13")
        self.assertFalse(contract["current_public_baseline"]["mutation_allowed"])
        self.assertFalse(contract["current_public_baseline"]["windows_public_authenticode_active"])
        self.assertEqual(
            set(contract["trust_layers"]),
            {"public_consumer_windows", "managed_enterprise_windows", "russian_release_evidence"},
        )
        self.assertFalse(contract["trust_layers"]["managed_enterprise_windows"]["equivalent_to_public_consumer_trust"])
        self.assertFalse(contract["trust_layers"]["russian_release_evidence"]["embedded_authenticode_equivalent"])
        self.assertFalse(contract["trust_layers"]["russian_release_evidence"]["smartscreen_reputation_equivalent"])

    def test_public_certificate_profile_is_rsa_3072_authenticode_and_timestamped(self):
        contract = json.loads(self.read("release/APL_REL_016_WINDOWS_PUBLIC_TRUST_CONTRACT.json"))
        profile = contract["trust_layers"]["public_consumer_windows"]["certificate_profile"]
        self.assertEqual(profile["key_algorithm"], "RSA")
        self.assertGreaterEqual(profile["minimum_key_bits"], 3072)
        self.assertEqual(profile["code_signing_eku_oid"], "1.3.6.1.5.5.7.3.3")
        self.assertEqual(profile["digest"], "SHA256")
        self.assertIn("Microsoft Trusted Root Program", profile["chain_requirement"])
        self.assertIn("CA/Browser Forum", profile["chain_requirement"])
        self.assertFalse(profile["self_signed_allowed"])
        timestamp = contract["trust_layers"]["public_consumer_windows"]["timestamp"]
        self.assertTrue(timestamp["required"])
        self.assertEqual(timestamp["protocol"], "RFC3161")
        self.assertEqual(timestamp["digest"], "SHA256")

    def test_russian_national_ca_is_priority_candidate_not_fabricated_public_trust(self):
        contract = json.loads(self.read("release/APL_REL_016_WINDOWS_PUBLIC_TRUST_CONTRACT.json"))
        candidate = contract["provider_policy"]["russian_national_ca_candidate"]
        self.assertEqual(candidate["observed_regulatory_source_date"], "2026-08-28")
        self.assertEqual(candidate["status"], "DRAFT_REGULATORY_CANDIDATE_NOT_PRODUCTION_PROVEN")
        self.assertEqual(candidate["priority"], "FIRST_RUSSIAN_NATIVE_PATH_TO_RECHECK")
        self.assertIn("codeSigning EKU", candidate["observed_capability"])
        self.assertIn("2.23.140.1.4.1", candidate["observed_capability"])
        self.assertTrue(candidate["manual_installation_of_russian_trusted_root_is_not_public_consumer_trust"])
        required = set(candidate["must_not_be_treated_as_public_windows_trust_until"])
        self.assertIn("microsoft_trusted_root_program_status_for_relevant_chain_is_authoritatively_verified", required)
        self.assertIn("code_signing_chain_is_accepted_on_clean_supported_windows_without_manual_root_installation", required)
        self.assertIn("rsa_3072_authenticode_and_rfc3161_timestamp_profile_passes_rel_016_gate", required)

    def test_byte_order_signs_application_before_packages_and_installer_before_final_hashes(self):
        contract = json.loads(self.read("release/APL_REL_016_WINDOWS_PUBLIC_TRUST_CONTRACT.json"))
        order = contract["direct_win32_byte_order"]
        self.assertLess(order.index("authenticode_sign_application"), order.index("package_signed_application_into_portable"))
        self.assertLess(order.index("package_signed_application_into_portable"), order.index("compile_installer_from_exact_signed_application"))
        self.assertLess(order.index("authenticode_sign_installer"), order.index("generate_final_checksums"))
        self.assertLess(order.index("generate_final_checksums"), order.index("cryptopro_rutoken_sign_final_release_manifest"))

    def test_runbook_does_not_overclaim_signature_as_reputation(self):
        runbook = self.read("release/APL_REL_016_WINDOWS_PUBLIC_TRUST.md")
        self.assertIn("SmartScreen", runbook)
        self.assertIn("Smart App Control", runbook)
        self.assertIn("App Control for Business", runbook)
        self.assertIn("Microsoft Trusted Root Program", runbook)
        self.assertIn("PUBLIC_SIGNATURE_READY_REPUTATION_PENDING", runbook)
        self.assertIn("PUBLIC_TRUST_ESTABLISHED_ON_TEST_HOST", runbook)
        self.assertIn("v0.2.5", runbook)
        self.assertIn("RELEASE-EVIDENCE-ONLY", runbook)
        self.assertIn("Russian qualified release evidence", runbook)
        self.assertIn("vendor-neutral", runbook)
        self.assertIn("RSA-3072", runbook)
        self.assertNotIn("GlobalSign is required", runbook)

    def test_public_trust_gate_checks_native_signature_motw_defender_and_manual_trp_evidence(self):
        gate = self.read("tools/windows_public_trust_gate.ps1")
        self.assertIn("Get-AuthenticodeSignature", gate)
        self.assertIn("1.3.6.1.5.5.7.3.3", gate)
        self.assertIn("1.2.840.113549.1.1.1", gate)
        self.assertIn("3072", gate)
        self.assertIn("X509Chain", gate)
        self.assertIn("AuthRoot", gate)
        self.assertIn("Zone.Identifier", gate)
        self.assertIn("ZoneId", gate)
        self.assertIn("Get-MpComputerStatus", gate)
        self.assertIn("Get-MpThreatDetection", gate)
        self.assertIn("MicrosoftTrustedRootProgramReference", gate)
        self.assertIn("membership_inferred_from_local_store = $false", gate)
        self.assertIn("PUBLIC_SIGNATURE_READY_REPUTATION_PENDING", gate)
        self.assertIn("PUBLIC_TRUST_ESTABLISHED_ON_TEST_HOST", gate)
        self.assertIn("RequireNoSmartScreenWarning", gate)

    def test_signed_portable_packager_binds_exact_signed_app_before_installer_consumption(self):
        packager = self.read("tools/package_signed_windows_portable.ps1")
        self.assertIn("Get-AuthenticodeSignature", packager)
        self.assertIn("ExpectedPublisher", packager)
        self.assertIn("ExpectedThumbprint", packager)
        self.assertIn("3072", packager)
        self.assertIn("pre_sign_exe_sha256", packager)
        self.assertIn("application-signed-before-portable", packager)
        self.assertIn("windows_promoted_license_compliance.ps1", packager)
        self.assertIn("SHA256SUMS.txt", packager)
        self.assertIn("Final portable ZIP application bytes do not match", packager)
        self.assertIn("build-result.json", packager)

    def test_installer_existing_payload_preserves_caller_supplied_portable_path(self):
        installer = self.read("tools/build_windows_installer.ps1")
        self.assertIn("$portableZipPath = Join-Path", installer)
        self.assertIn("$portableZipPath = (Resolve-Path -LiteralPath $PortableZip).Path", installer)
        self.assertIn("Hash $portableZipPath", installer)
        self.assertNotIn("$portableZip = Join-Path", installer)

    def test_authenticode_primitive_enforces_rsa_3072_profile(self):
        script = self.read("tools/windows_authenticode.ps1")
        self.assertIn("1.2.840.113549.1.1.1", script)
        self.assertIn("RSACertificateExtensions", script)
        self.assertIn("3072", script)
        self.assertIn("APL-REL-016", script)
        self.assertIn("'/fd', 'SHA256'", script)
        self.assertIn("'/tr', $TimestampUrl, '/td', 'SHA256'", script)

    def test_forbidden_shortcuts_are_explicit(self):
        contract = json.loads(self.read("release/APL_REL_016_WINDOWS_PUBLIC_TRUST_CONTRACT.json"))
        forbidden = set(contract["forbidden_shortcuts"])
        for item in {
            "mutate_v0.2.5",
            "mutate_v0.2.13",
            "disable_defender",
            "disable_smartscreen",
            "disable_smart_app_control",
            "test_signing_as_production_requirement",
            "self_signed_certificate_as_public_trust",
            "claim_windows_public_trust_from_russian_detached_signature_only",
        }:
            self.assertIn(item, forbidden)


if __name__ == "__main__":
    unittest.main()
