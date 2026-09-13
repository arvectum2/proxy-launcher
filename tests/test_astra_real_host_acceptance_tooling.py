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


collector = _load("astra_state_collector", "qa/collect_astra_network_state.py")
comparator = _load("astra_state_comparator", "qa/compare_astra_network_state.py")
preflight = _load("astra_preflight", "qa/collect_astra_acceptance_preflight.py")
verifier = _load("astra_bundle_verifier", "qa/verify_astra_acceptance_bundle.py")


def _snapshot(proxy_url_hash: str = "a" * 64) -> dict:
    return {
        "schema": 1,
        "collector": "APL-LNX-010",
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


class AstraAcceptanceToolingTests(unittest.TestCase):
    def test_terse_split_preserves_escaped_colon(self):
        self.assertEqual(
            collector._split_terse(r"uuid:802-3-ethernet:enp0s3\:managed"),
            ("uuid", "802-3-ethernet", "enp0s3:managed"),
        )

    def test_preflight_detects_astra_markers(self):
        self.assertTrue(preflight.detect_astra({"ID": "astra"}, ""))
        self.assertTrue(
            preflight.detect_astra(
                {"ID": "debian", "PRETTY_NAME": "Astra Linux Special Edition"},
                "1.8",
            )
        )
        self.assertFalse(preflight.detect_astra({"ID": "ubuntu"}, ""))

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
                        "astra_detected=yes",
                        "allow_non_astra=no",
                        "virtualization=none",
                        "ci_detected=no",
                        "architecture=x86_64",
                        f"candidate_sha256={candidate_sha}",
                    )
                )
                + "\n",
                encoding="utf-8",
            )
            (root / "03-package.txt").write_text(
                f"candidate_sha256={candidate_sha}\ninstall=PASS\n",
                encoding="utf-8",
            )
            for name in (
                "02-network-before.json",
                "06-network-enabled.json",
                "08-network-after-disable.json",
                "11-network-after-crash-recovery.json",
                "13-network-after-reboot-recovery.json",
            ):
                (root / name).write_text(
                    json.dumps(_snapshot(), sort_keys=True), encoding="utf-8"
                )
            (root / "HOST_ATTESTATION.env").write_text(
                "physical_host=YES\n"
                "interactive_graphical_session=YES\n"
                "operator_confirmed=YES\n",
                encoding="utf-8",
            )
            checks = "\n".join(f"- {check}: PASS" for check in verifier.CHECKS)
            (root / "SUMMARY.md").write_text(
                "APL-LNX-010 — REAL ASTRA LINUX ACCEPTANCE\n"
                "RESULT: PASS\n\n"
                f"{checks}\n"
                "pending rollback: NO\n"
                "final proxy state: BASELINE\n",
                encoding="utf-8",
            )

            self.assertEqual(verifier.verify(root), [])

    def test_verifier_rejects_virtual_or_non_astra_preflight(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in verifier.REQUIRED_FILES:
                (root / name).write_text("placeholder\n", encoding="utf-8")
            (root / "01-preflight.txt").write_text(
                "astra_detected=no\n"
                "allow_non_astra=yes\n"
                "virtualization=kvm\n"
                "ci_detected=yes\n"
                "architecture=x86_64\n"
                f"candidate_sha256={'a' * 64}\n",
                encoding="utf-8",
            )
            failures = verifier.verify(root)
            text = "\n".join(failures)
            self.assertIn("does not prove Astra Linux", text)
            self.assertIn("used --allow-non-astra", text)
            self.assertIn("virtualized host", text)
            self.assertIn("collected in CI", text)


if __name__ == "__main__":
    unittest.main()
