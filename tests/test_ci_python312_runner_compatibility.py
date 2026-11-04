"""Prevent setup-python 3.12.10 failures on ubuntu-latest -> Ubuntu 26.04."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
AFFECTED = (
    "dependency-scan.yml",
    "sast.yml",
    "sbom.yml",
    "apl-ip-001-v0-2-5.yml",
    "apl-ip-001-v0-2-9.yml",
    "apl-reg-001b-sovereign-lifecycle.yml",
)


class CISetupPythonRunnerContract(unittest.TestCase):
    def test_exact_python_build_pin_is_kept(self):
        pinned = (ROOT / "BUILD_PYTHON_VERSION").read_text(encoding="utf-8").strip()
        self.assertEqual(pinned, "3.12.10")

    def test_all_affected_python_gates_use_supported_fixed_runner(self):
        for name in AFFECTED:
            with self.subTest(workflow=name):
                content = (WORKFLOWS / name).read_text(encoding="utf-8")
                self.assertEqual(content.count("runs-on: ubuntu-24.04"), 1)
                self.assertNotIn("runs-on: ubuntu-latest", content)
                self.assertIn("actions/setup-python@", content)
                self.assertIn("python-version-file: BUILD_PYTHON_VERSION", content)
                self.assertNotIn("continue-on-error: true", content)
                self.assertTrue(re.search(r"(?m)^\s+- name: (Set up|Set up build) Python$", content))


if __name__ == "__main__":
    unittest.main()
