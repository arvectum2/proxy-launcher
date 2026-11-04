"""Prevent UI test target drift when shared production Swift code gains types."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class IOSTestTargetSourceTests(unittest.TestCase):
    def test_ui_target_includes_shared_diagnostic_dependencies(self):
        spec = (ROOT / "mobile/ios/project.yml").read_text(encoding="utf-8")
        section = spec.split("  SmartExclusionsUITests:\n", 1)[1].split("    dependencies:\n", 1)[0]
        for path in ("SharedCore/ProxyFailureReason.swift", "SharedCore/TunnelEngineHandoff.swift", "SharedCore/ProxyModel.swift"):
            with self.subTest(path=path):
                self.assertIn("      - " + path + "\n", section)
                self.assertTrue((ROOT / "mobile/ios" / path).is_file())

if __name__ == "__main__":
    unittest.main()
