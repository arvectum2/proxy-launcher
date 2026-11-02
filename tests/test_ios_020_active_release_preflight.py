"""Negative tests prevent accidental validation of the old 0.1.42 iOS branch."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "ios_active_release_preflight.py"
spec = importlib.util.spec_from_file_location("ios_active_release_preflight", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class IOS020ActiveReleasePreflightTests(unittest.TestCase):
    def test_current_020_source_is_consistent(self):
        self.assertEqual(module.verify_active_release(ROOT), ("0.2.0", "48"))

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for relpath in (module.IDENTITY_PATH, module.PROJECT_SPEC_PATH, module.XCODE_PROJECT_PATH):
            destination = self.root / relpath
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text((ROOT / relpath).read_text(encoding="utf-8"), encoding="utf-8")

    def replace(self, relpath, old, new):
        path = self.root / relpath
        content = path.read_text(encoding="utf-8")
        self.assertIn(old, content)
        path.write_text(content.replace(old, new), encoding="utf-8")

    def test_stale_0142_xcodegen_source_is_rejected(self):
        self.replace(module.PROJECT_SPEC_PATH, 'MARKETING_VERSION: "0.2.0"', 'MARKETING_VERSION: "0.1.42"')
        with self.assertRaisesRegex(ValueError, "Stale XcodeGen"):
            module.verify_active_release(self.root)

    def test_mismatched_generated_build_is_rejected(self):
        self.replace(module.XCODE_PROJECT_PATH, "CURRENT_PROJECT_VERSION = 48;", "CURRENT_PROJECT_VERSION = 47;")
        with self.assertRaisesRegex(ValueError, "Stale generated iOS Xcode project build"):
            module.verify_active_release(self.root)

    def test_unexpected_release_authorization_is_rejected(self):
        path = self.root / module.IDENTITY_PATH
        identity = json.loads(path.read_text(encoding="utf-8"))
        identity["app_store_submission_authorized"] = True
        path.write_text(json.dumps(identity), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "must not authorize"):
            module.verify_active_release(self.root)


if __name__ == "__main__":
    unittest.main()
