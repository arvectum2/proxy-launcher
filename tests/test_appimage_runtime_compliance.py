import json
from pathlib import Path
import tempfile
import unittest

from tools import appimage_runtime_compliance as compliance


class AppImageRuntimeComplianceTests(unittest.TestCase):
    def test_bundle_covers_runtime_static_components_and_lock_identity(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "bundle"
            manifest = compliance.build_bundle(out)
            components = {item["component"] for item in manifest["files"]}
            self.assertIn("libfuse-lgpl-2.1", components)
            self.assertIn("mimalloc", components)
            lock = compliance.read_lock()
            self.assertEqual(manifest["runtime"]["sha256"], lock["APPIMAGE_RUNTIME_SHA256"])
            self.assertEqual(manifest["runtime"]["source_commit"], lock["APPIMAGE_RUNTIME_SOURCE_COMMIT"])
            compliance.verify_bundle(out)

    def test_tampered_runtime_license_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "bundle"
            compliance.build_bundle(out)
            (out / "mimalloc-LICENSE.txt").write_text("tampered\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "hash mismatch"):
                compliance.verify_bundle(out)

    def test_manifest_runtime_identity_is_lock_bound(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "bundle"
            compliance.build_bundle(out)
            path = out / "manifest.json"
            manifest = json.loads(path.read_text(encoding="utf-8"))
            manifest["runtime"]["sha256"] = "0" * 64
            path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "runtime identity"):
                compliance.verify_bundle(out)


if __name__ == "__main__":
    unittest.main()
