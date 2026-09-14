import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def _load(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


collector = _load("redos_state_collector", "qa/collect_redos_network_state.py")
comparator = _load("redos_state_comparator", "qa/compare_redos_network_state.py")
preflight = _load("redos_preflight", "qa/collect_redos_acceptance_preflight.py")
verifier = _load("redos_bundle_verifier", "qa/verify_redos_acceptance_bundle.py")


def _snapshot(proxy_url_hash: str = "a" * 64) -> dict:
    return {
        "schema": 1,
        "collector": "APL-REG-001C-REDOS",
        "privacy": "test",
        "connection_count": 1,
        "connections": [
            {
                "identity_sha256": "1" * 64,
                "type": "802-3-ethernet",
                "device": "eth0",
                "proxy": {
                    "method": "none",
                    "browser_only": False,
                    "pac_url_present": False,
                    "pac_url_sha256": proxy_url_hash,
                    "pac_script_present": False,
                    "pac_script_sha256": "0" * 64,
                },
            }
        ],
    }


class RedOsAcceptanceToolingTests(unittest.TestCase):
    def test_terse_split_preserves_escaped_colon(self):
        self.assertEqual(
            collector._split_terse(r"uuid:802-3-ethernet:enp0s3\:managed"),
            ("uuid", "802-3-ethernet", "enp0s3:managed"),
        )

    def test_preflight_detects_red_os_markers(self):
        self.assertTrue(preflight.detect_redos({"ID": "redos"}))
        self.assertTrue(preflight.detect_redos({"PRETTY_NAME": "RED OS 8"}))
        self.assertTrue(preflight.detect_redos({"NAME": "РЕД ОС"}))
        self.assertFalse(preflight.detect_redos({"ID": "fedora", "PRETTY_NAME": "Fedora Linux 40"}))

    def test_exact_comparator_passes_identical_proxy_state(self):
        ok, failures = comparator.compare(_snapshot(), _snapshot())
        self.assertTrue(ok)
        self.assertEqual(failures, [])

    def test_exact_comparator_rejects_proxy_drift(self):
        before = _snapshot()
        after = _snapshot("b" * 64)
        ok, failures = comparator.compare(before, after)
        self.assertFalse(ok)
        self.assertTrue(any("proxy state differs" in item for item in failures))

    def test_verifier_fails_closed_on_empty_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            failures = verifier.verify(Path(directory))
        self.assertTrue(failures)
        self.assertTrue(any("missing/non-empty" in item for item in failures))

    def test_verifier_accepts_complete_mechanical_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate_sha = "a" * 64
            for name in verifier.REQUIRED_FILES:
                (root / name).write_text("placeholder\n", encoding="utf-8")
            (root / "01-preflight.txt").write_text(
                "\n".join(
                    (
                        "collector=APL-REG-001C-REDOS",
                        "redos_detected=yes",
                        "allow_non_redos=no",
                        "virtualization=none",
                        "ci_detected=no",
                        "architecture=x86_64",
                        "candidate_package=arvectum-proxy-launcher",
                        "candidate_architecture=x86_64",
                        f"candidate_sha256={candidate_sha}",
                        "dnf=/usr/bin/dnf",
                        "rpm=/usr/bin/rpm",
                        "nmcli=/usr/bin/nmcli",
                    )
                ) + "\n",
                encoding="utf-8",
            )
            (root / "03-package.txt").write_text(
                f"candidate_sha256={candidate_sha}\ninstall=PASS\n", encoding="utf-8"
            )
            for name in (
                "02-network-before.json", "06-network-enabled.json",
                "08-network-after-disable.json", "11-network-after-crash-recovery.json",
                "13-network-after-reboot-recovery.json",
            ):
                (root / name).write_text(json.dumps(_snapshot(), sort_keys=True), encoding="utf-8")
            (root / "HOST_ATTESTATION.env").write_text(
                "physical_host=YES\ninteractive_graphical_session=YES\noperator_confirmed=YES\n",
                encoding="utf-8",
            )
            checks = "\n".join(f"- {check}: PASS" for check in verifier.CHECKS)
            (root / "SUMMARY.md").write_text(
                "APL-REG-001C — REAL RED OS ACCEPTANCE\nRESULT: PASS\n\n"
                f"{checks}\npending rollback: NO\nfinal proxy state: BASELINE\n",
                encoding="utf-8",
            )
            self.assertEqual(verifier.verify(root), [])

    def test_verifier_rejects_virtual_or_non_redos_preflight(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in verifier.REQUIRED_FILES:
                (root / name).write_text("placeholder\n", encoding="utf-8")
            (root / "01-preflight.txt").write_text(
                "collector=APL-REG-001C-REDOS\nredos_detected=no\nallow_non_redos=yes\n"
                "virtualization=kvm\nci_detected=yes\narchitecture=x86_64\n"
                "candidate_package=arvectum-proxy-launcher\ncandidate_architecture=x86_64\n"
                f"candidate_sha256={'a' * 64}\ndnf=/usr/bin/dnf\nrpm=/usr/bin/rpm\nnmcli=/usr/bin/nmcli\n",
                encoding="utf-8",
            )
            failures = verifier.verify(root)
            text = "\n".join(failures)
            self.assertIn("does not prove RED OS", text)
            self.assertIn("used --allow-non-redos", text)
            self.assertIn("virtualized host", text)
            self.assertIn("collected in CI", text)


if __name__ == "__main__":
    unittest.main()
