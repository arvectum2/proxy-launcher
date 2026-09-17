import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
COLLECTOR = ROOT / "qa" / "collect_redos_acceptance_preflight.py"


def _load():
    spec = importlib.util.spec_from_file_location("redos_preflight", COLLECTOR)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


collector = _load()


class RedOsAcceptanceToolingTests(unittest.TestCase):
    def test_redos_detection_accepts_canonical_id(self):
        self.assertTrue(collector.detect_redos({"ID": "redos", "PRETTY_NAME": "RED OS 8.0.3"}))

    def test_redos_detection_rejects_generic_linux(self):
        self.assertFalse(collector.detect_redos({"ID": "ubuntu", "PRETTY_NAME": "Ubuntu 24.04"}))

    def test_candidate_sha256_is_exact(self):
        with tempfile.TemporaryDirectory() as td:
            candidate = pathlib.Path(td) / "candidate.rpm"
            candidate.write_bytes(b"APL-REG-001C")
            self.assertEqual(
                collector._sha256(candidate),
                "9541941c064a325b015edb52dcafc8169d231889fd779c7589d9399227b58787",
            )

    def test_collect_is_read_only_and_records_redos_identity(self):
        osr = {
            "ID": "redos",
            "PRETTY_NAME": "RED OS 8.0.3 (Standard Desktop)",
            "VERSION_ID": "8.0.3",
            "EDITION": "Standard",
            "PLATFORM_ID": "platform:red80",
        }
        with mock.patch.object(collector, "_os_release", return_value=osr), \
             mock.patch.object(collector.shutil, "which", return_value=None), \
             mock.patch.object(collector.platform, "machine", return_value="x86_64"), \
             mock.patch.object(collector.platform, "release", return_value="6.12.101-1.red80.x86_64"), \
             mock.patch.object(collector, "_read", return_value=""):
            data, details = collector.collect(None, False)
        self.assertEqual(data["mutation"], "false")
        self.assertEqual(data["redos_detected"], "yes")
        self.assertEqual(data["os_version_id"], "8.0.3")
        self.assertEqual(data["os_edition"], "Standard")
        self.assertEqual(data["architecture"], "x86_64")
        self.assertEqual(details, [])

    def test_script_contains_no_mutating_package_or_network_commands(self):
        text = COLLECTOR.read_text(encoding="utf-8")
        for forbidden in (
            "dnf install",
            "rpm -i",
            "rpm -U",
            "nmcli connection modify",
            "nmcli connection up",
            "sudo ",
            "pkexec",
        ):
            self.assertNotIn(forbidden, text)


if __name__ == "__main__":
    unittest.main()
