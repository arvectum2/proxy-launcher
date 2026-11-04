"""Portable real-Git history tests: independent of shallow CI checkout depth."""
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "mobile/ios/Tools/verify_release_feature_source.py"
spec = importlib.util.spec_from_file_location("release_git_synthetic", SCRIPT)
assert spec and spec.loader
gate = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = gate
spec.loader.exec_module(gate)


class LocalGitFeatureGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="apl-source-gate-")
        cls.repo = Path(cls.tmp.name)

        def git(*args):
            p = subprocess.run(
                ["git", "-C", str(cls.repo), *args],
                capture_output=True, text=True, check=False,
            )
            if p.returncode:
                raise RuntimeError("Git fixture setup failed: " + p.stderr[:500])
            return p.stdout.strip()

        git("init", "-q")
        (cls.repo / "README.md").write_text("App before feature\n")
        git("add", ".")
        git("-c", "user.name=APL QA", "-c", "user.email=qa@example.invalid",
            "commit", "-qm", "base-no-QR")
        cls.before = git("rev-parse", "HEAD")

        files = (
            "mobile/ios/SharedCore/ProxyProfileSharing.swift",
            "mobile/ios/App/ProxyShareView.swift",
            "mobile/ios/App/ProxyQRScanner.swift",
        )
        for name in files:
            path = cls.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// Synthetic QR test file\n")
        git("add", ".")
        git("-c", "user.name=APL QA", "-c", "user.email=qa@example.invalid",
            "commit", "-qm", "QR-added")
        cls.feature = git("rev-parse", "HEAD")

        (cls.repo / files[2]).unlink()
        git("add", "-A")
        git("-c", "user.name=APL QA", "-c", "user.email=qa@example.invalid",
            "commit", "-qm", "QR-scanner-removed")
        cls.with_missing_file = git("rev-parse", "HEAD")

        cls.repo_patch = mock.patch.object(gate, "REPO", cls.repo)
        cls.features_patch = mock.patch.object(gate, "FEATURES", {
            "qr-profile-share": {
                "required_commit": cls.feature,
                "required_files": files,
            }
        })
        cls.repo_patch.start()
        cls.features_patch.start()

    @classmethod
    def tearDownClass(cls):
        cls.features_patch.stop()
        cls.repo_patch.stop()
        cls.tmp.cleanup()

    def test_absent_before_feature(self):
        result = gate.source_status(self.before, "qr-profile-share")
        self.assertFalse(result["source_feature_present"])
        self.assertFalse(result["required_commit_ancestor"])

    def test_source_present_does_not_prove_ipa(self):
        result = gate.source_status(self.feature, "qr-profile-share")
        self.assertTrue(result["source_feature_present"])
        self.assertFalse(result["signed_binary_feature_verified"])
        self.assertFalse(result["app_store_publication_verified"])

    def test_deleted_source_is_fail_closed_despite_ancestor(self):
        result = gate.source_status(self.with_missing_file, "qr-profile-share")
        self.assertTrue(result["required_commit_ancestor"])
        self.assertFalse(result["required_files_present"])
        self.assertFalse(result["source_feature_present"])

    def test_bad_ref_is_rejected(self):
        for ref in ("does-not-exist", "--upload-pack=unsafe"):
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                gate.source_status(ref, "qr-profile-share")

    def invoke(self, sha, required):
        output = io.StringIO()
        argv = [str(SCRIPT), "--feature", "qr-profile-share",
                "--source-ref", sha, required]
        with mock.patch.object(sys, "argv", argv), mock.patch("sys.stdout", output):
            code = gate.main()
        return code, json.loads(output.getvalue())

    def test_cli_require_present_rejects_old_source(self):
        rc, result = self.invoke(self.before, "--require-present")
        self.assertEqual(rc, 3)
        self.assertFalse(result["source_feature_present"])

    def test_cli_require_present_accepts_source_not_binary(self):
        rc, result = self.invoke(self.feature, "--require-present")
        self.assertEqual(rc, 0)
        self.assertTrue(result["source_feature_present"])
        self.assertFalse(result["signed_binary_feature_verified"])

    def test_cli_require_absent_rejects_new_source(self):
        rc, result = self.invoke(self.feature, "--require-absent")
        self.assertEqual(rc, 3)
        self.assertTrue(result["source_feature_present"])


if __name__ == "__main__":
    unittest.main()
