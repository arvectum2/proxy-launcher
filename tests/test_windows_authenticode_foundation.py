import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class WindowsAuthenticodeFoundationTests(unittest.TestCase):
    def read(self, name: str) -> str:
        return (ROOT / name).read_text(encoding="utf-8-sig")

    def test_signing_script_exists_and_uses_modern_authenticode_algorithms(self):
        script = self.read("tools/windows_authenticode.ps1")
        self.assertIn("'/fd', 'SHA256'", script)
        self.assertIn("'/tr', $TimestampUrl, '/td', 'SHA256'", script)
        self.assertIn("'verify', '/pa', '/all', '/v'", script)
        self.assertIn("1.3.6.1.5.5.7.3.3", script)
        self.assertIn("1.2.840.113549.1.1.1", script)
        self.assertIn("RSACertificateExtensions", script)
        self.assertIn("3072", script)

    def test_production_signing_requires_timestamp_by_default(self):
        script = self.read("tools/windows_authenticode.ps1")
        self.assertIn("Production Authenticode signing requires an RFC 3161 timestamp URL", script)
        self.assertIn("[switch]$SkipTimestamp", script)

    def test_private_key_material_is_not_part_of_repository_contract(self):
        script = self.read("tools/windows_authenticode.ps1")
        lowered = script.lower()
        self.assertNotIn("pfx_password", lowered)
        self.assertNotIn("certificatepassword", lowered)
        self.assertNotIn("/f',", script)
        self.assertIn("WINDOWS_SIGNING_CERT_THUMBPRINT", script)

    def test_ci_smoke_uses_ephemeral_rsa_3072_test_certificate_and_real_pe(self):
        workflow = self.read(".github/workflows/windows-authenticode.yml")
        self.assertIn("New-SelfSignedCertificate", workflow)
        self.assertIn("-Type CodeSigningCert", workflow)
        self.assertIn("-KeyAlgorithm RSA", workflow)
        self.assertIn("-KeyLength 3072", workflow)
        self.assertIn("./tools/clean_build_windows.ps1", workflow)
        self.assertIn("dist\\Arvectum Proxy Launcher.exe", workflow)
        self.assertIn("-SkipTimestamp", workflow)
        self.assertIn("Unsigned PE unexpectedly passed Authenticode verification", workflow)
        self.assertIn("Get-AuthenticodeSignature", workflow)

    def test_foundation_does_not_claim_production_signing_is_active(self):
        policy = self.read("RELEASE_POLICY.md")
        self.assertIn("Authenticode foundation", policy)
        self.assertIn("production signing is not yet activated", policy)
        self.assertIn("portable application executable", policy)
        self.assertIn("installer executable", policy)

    def test_release_runbook_declares_activation_boundary(self):
        runbook = self.read("release/APL_REL_008_WINDOWS_CODE_SIGNING.md")
        self.assertIn("FOUNDATION READY / PRODUCTION SIGNING NOT ACTIVE", runbook)
        self.assertIn("WINDOWS_SIGNING_CERT_THUMBPRINT", runbook)
        self.assertIn("WINDOWS_SIGNING_TIMESTAMP_URL", runbook)
        self.assertIn("WINDOWS_SIGNING_EXPECTED_PUBLISHER", runbook)
        self.assertIn("private key", runbook.lower())
        self.assertIn("portable EXE", runbook)
        self.assertIn("installer EXE", runbook)


if __name__ == "__main__":
    unittest.main()
