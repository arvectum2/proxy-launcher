import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGER = ROOT / "tools" / "package_windows_portable_windivert.ps1"
ACCEPTANCE = ROOT / "tools" / "windows_rc_acceptance.ps1"


class WindowsPortableWinDivertTests(unittest.TestCase):
    def test_packager_is_source_commit_hash_and_signer_bound(self):
        text = PACKAGER.read_text(encoding="utf-8-sig")
        for token in (
            "source_commit does not match HEAD",
            "arvectum.proxy.windows-windivert-build.v1",
            "arvectum.proxy.windivert-dependency.v1",
            "8da085332782708d8767bcace5327a6ec7283c17cfb85e40b03cd2323a90ddc2",
            "c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2",
            "14a0cb5214d536e4fdae6aa3f5696f981eeda106cd026e9794bba489ee79d628",
            "043589F75FCE2795E7F2CC3E526D46784D5DDAB3",
            "Get-AuthenticodeSignature",
            "windivert_service_helper.ps1",
            "WINDOWS_WINDIVERT",
            "build_manifest.json",
        ):
            self.assertIn(token, text)

    def test_packager_rebinds_final_zip_and_build_result(self):
        text = PACKAGER.read_text(encoding="utf-8-sig")
        for token in (
            "$build.zip_sha256 = $zipHash",
            "windivert_stack_enabled",
            "windivert_dependency_manifest_sha256",
            "windivert_stack_manifest_sha256",
            "windivert_service_helper_sha256",
            "windivert_service_sha256",
            "portable_build_manifest_sha256",
            "SHA256SUMS.txt",
        ):
            self.assertIn(token, text)

    def test_packager_verifies_candidate_before_atomic_zip_replace(self):
        text = PACKAGER.read_text(encoding="utf-8-sig")
        candidate = text.index("$candidateZip = Join-Path")
        compress = text.index(
            "Compress-Archive -Path \"$stage\\*\" -DestinationPath $candidateZip"
        )
        verify = text.index(
            "Expand-Archive -LiteralPath $candidateZip -DestinationPath $verify"
        )
        replace = text.index(
            "[IO.File]::Replace($candidateZip, $zip, $backupZip, $true)"
        )
        self.assertLess(candidate, compress)
        self.assertLess(compress, verify)
        self.assertLess(verify, replace)
        self.assertNotIn("Remove-Item -LiteralPath $zip -Force", text)

    def test_rc_acceptance_requires_portable_windivert_sidecar(self):
        text = ACCEPTANCE.read_text(encoding="utf-8-sig")
        for token in (
            "portable.windivert.enabled",
            "portable.windivert.source_commit",
            "portable.windivert.stack_source_commit",
            "portable.windivert.service_sha256",
            "portable.windivert.dependency_manifest_sha256",
            "portable.windivert.helper_sha256",
            "portable.windivert.driver_signature",
            "portable.windivert.driver_signer",
            "WINDOWS_WINDIVERT/",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
