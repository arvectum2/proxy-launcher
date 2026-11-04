"""Source / binary distinction for iOS 0.2.0 and later QR-capable releases."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "mobile/ios/Tools/verify_release_feature_source.py"
spec = importlib.util.spec_from_file_location("ios_release_feature_source", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

APPLE_020_SOURCE = "f0a93f8addb4b61961e9c53c885871a563aef9c6"
QR_FEATURE_SOURCE = "b59801f69990d621e873360762256a80919168de"


class ReleaseSourceProvenanceTests(unittest.TestCase):
    def test_apple_020_does_not_include_later_qr_feature(self):
        report = module.source_status(APPLE_020_SOURCE, "qr-profile-share")
        self.assertFalse(report["source_feature_present"])
        self.assertFalse(report["required_commit_ancestor"])
        self.assertFalse(report["signed_binary_feature_verified"])
        self.assertFalse(report["app_store_publication_verified"])

    def test_reviewed_qr_source_includes_feature_but_not_signed_binary_proof(self):
        report = module.source_status("HEAD", "qr-profile-share")
        self.assertTrue(report["source_feature_present"])
        self.assertEqual(report["required_commit"], QR_FEATURE_SOURCE)
        self.assertTrue(report["required_files_present"])
        self.assertFalse(report["signed_binary_feature_verified"])
        self.assertFalse(report["app_store_publication_verified"])

    def test_safe_diagnostics_also_postdate_020(self):
        self.assertFalse(module.source_status(
            APPLE_020_SOURCE, "safe-connection-diagnostics"
        )["source_feature_present"])
        self.assertTrue(module.source_status(
            "HEAD", "safe-connection-diagnostics"
        )["source_feature_present"])

    def test_unknown_source_rejected_without_positive_claim(self):
        with self.assertRaises(ValueError):
            module.source_status("not-an-existing-git-ref-123", "qr-profile-share")
        with self.assertRaises(ValueError):
            module.source_status("--upload-pack=anything", "qr-profile-share")

    def test_release_gate_fails_closed_for_020_without_source_feature(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--source-ref", APPLE_020_SOURCE,
             "--feature", "qr-profile-share", "--require-present"],
            text=True, capture_output=True, cwd=ROOT, check=False,
        )
        self.assertEqual(result.returncode, 3)
        data = json.loads(result.stdout)
        self.assertFalse(data["source_feature_present"])

    def test_release_gate_accepts_source_but_never_claims_ipa(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--source-ref", "HEAD",
             "--feature", "qr-profile-share", "--require-present"],
            text=True, capture_output=True, cwd=ROOT, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertTrue(data["source_feature_present"])
        self.assertFalse(data["signed_binary_feature_verified"])

    def test_missing_source_files_do_not_get_source_presence_credit(self):
        # Even when commit ancestry is true, the file gate is independently
        # required, and it detects removal or renamed sources.
        with mock.patch.object(
            module, "git",
            side_effect=lambda *args: (
                subprocess.CompletedProcess(args, 1, "", "")
                if args[0] == "cat-file" else original_git(*args)
            ),
        ):
            self.assertFalse(module.source_status("HEAD", "qr-profile-share")[
                "source_feature_present"
            ])


original_git = module.git

if __name__ == "__main__":
    unittest.main()
