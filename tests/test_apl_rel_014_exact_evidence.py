import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "apl_rel_014_exact_evidence.py"
CONTRACT = ROOT / "release" / "APL_REL_014_EXACT_SIGNED_SET_CONTRACT.json"


def load_module():
    spec = importlib.util.spec_from_file_location("apl_rel_014_exact_evidence", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def make_fixture(tmp_path: Path):
    module = load_module()
    contract = {
        "schema": "arvectum.proxy.apl-rel-014-exact-set-contract.v1",
        "task": "APL-REL-014",
        "product": "Arvectum Proxy Launcher",
        "version": "0.2.4",
        "candidate_source_commit": "a" * 40,
        "candidate": {
            "portable_zip_sha256": sha(b"portable"),
            "setup_sha256": sha(b"setup"),
            "application_sha256": sha(b"application"),
        },
        "predecessor": {
            "version": "0.2.3",
            "setup_sha256": sha(b"old-setup"),
            "application_sha256": sha(b"old-application"),
        },
        "physical_evidence": {
            "schema": "arvectum.proxy.apl-win-014-final-0.2.4-physical.v1",
            "task": "APL-WIN-014",
            "required_gates": ["predecessor", "upgrade", "runtime", "rollback", "repair", "uninstall"],
            "required_app_control": ["before", "after", "code_integrity_3077"],
            "required_code_integrity_3077_count": 0,
            "required_pac_url": "http://127.0.0.1:8082/proxy.pac",
        },
        "russian_release": {
            "required_signing_mode": "russian-qualified-evidence",
            "required_signer_thumbprint": "B" * 40,
            "rel013_post_sign_binding_required": True,
        },
    }
    contract_path = tmp_path / "contract.json"
    contract_path.write_text(json.dumps(contract), encoding="utf-8")

    release = tmp_path / "release"
    release.mkdir()
    setup = release / "Arvectum-Proxy-Launcher-0.2.4-windows-x64-setup.exe"
    portable = release / "Arvectum-Proxy-Launcher-0.2.4-windows-x64-portable.zip"
    setup.write_bytes(b"setup")
    portable.write_bytes(b"portable")

    candidate = {
        "schema": "arvectum.proxy.apl-win-014-final-0.2.4-candidate.v1",
        "task": "APL-WIN-014",
        "product_version": "0.2.4",
        "supported_predecessor_version": "0.2.3",
        "candidate_source_commit": "a" * 40,
        "application": {"filename": "Arvectum Proxy Launcher.exe", "sha256": sha(b"application")},
        "setup": {"filename": setup.name, "sha256": sha(b"setup")},
        "portable_zip": {"filename": portable.name, "sha256": sha(b"portable")},
        "checks": {
            "single_application_build": "PASS",
            "portable_application_identity": "PASS",
            "setup_installed_application_identity": "PASS",
            "ci_upgrade_0_2_3_to_0_2_4": "PASS",
            "fresh_install": "PASS",
            "repair": "PASS",
            "uninstall": "PASS",
            "windows_rc_acceptance": "PASS",
            "physical_enforced_app_control": "PENDING",
        },
    }
    candidate_path = tmp_path / "candidate_evidence.json"
    candidate_path.write_text(json.dumps(candidate), encoding="utf-8")

    physical = {
        "schema": "arvectum.proxy.apl-win-014-final-0.2.4-physical.v1",
        "task": "APL-WIN-014",
        "host": "ARVECTUM-DEMO",
        "started_utc": "2026-09-11T22:12:07Z",
        "finished_utc": "2026-09-11T22:12:53Z",
        "result": "PASS",
        "candidate_source_commit": "a" * 40,
        "candidate_setup_sha256": sha(b"setup"),
        "candidate_application_sha256": sha(b"application"),
        "predecessor_setup_sha256": sha(b"old-setup"),
        "app_control": {"before": "PASS", "after": "PASS", "code_integrity_3077": "PASS"},
        "gates": {
            "predecessor": "PASS",
            "upgrade": "PASS",
            "runtime": "PASS",
            "rollback": "PASS",
            "repair": "PASS",
            "uninstall": "PASS",
        },
        "runtime": {
            "listener_pid": 4496,
            "starter_pid": 12548,
            "pac_http_status": 200,
            "pac_body_length": 5591,
            "auto_config_url": "http://127.0.0.1:8082/proxy.pac",
        },
        "code_integrity_3077_count": 0,
        "block_reason": None,
    }
    physical_path = tmp_path / "physical.json"
    physical_path.write_text(json.dumps(physical), encoding="utf-8")

    return module, contract_path, candidate_path, physical_path, release, setup


class AplRel014ExactEvidenceTests(unittest.TestCase):
    def test_repository_contract_pins_exact_accepted_0_2_4_candidate(self):
        contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
        self.assertEqual(contract["version"], "0.2.4")
        self.assertEqual(contract["candidate_source_commit"], "e2278dbbd99b0d98ba9e4f836e40b2d60ea94b30")
        self.assertEqual(contract["candidate"]["portable_zip_sha256"], "467864f286dc4c4de6c0f6033ae5cd5420a691c1bc9a32bf4891285c8c1d29bf")
        self.assertEqual(contract["candidate"]["setup_sha256"], "28eb0b06c2f478b46d5845c6bb1970c96e20a2f6fdaf1d48501ed69f52ea6965")
        self.assertEqual(contract["candidate"]["application_sha256"], "0415226f882e16a0ce370b766c4c68d3c23861f97361da093a1fd9d9f0e0832c")
        self.assertEqual(contract["predecessor"]["setup_sha256"], "5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414")
        self.assertEqual(contract["predecessor"]["application_sha256"], "f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a")

    def test_build_evidence_requires_exact_product_bytes_and_all_physical_gates(self):
        with tempfile.TemporaryDirectory() as td:
            module, contract, candidate, physical, release, _ = make_fixture(Path(td))
            evidence = module.build_evidence(contract, candidate, physical, release)
            self.assertEqual(evidence["result"], "PASS")
            self.assertEqual(evidence["scope"], "EXACT_PRODUCT_SET_READY_FOR_REL011_SIGNING")
            self.assertEqual(evidence["release_assets"]["setup"]["sha256"], sha(b"setup"))
            self.assertEqual(evidence["release_assets"]["portable_zip"]["sha256"], sha(b"portable"))
            self.assertEqual(evidence["lifecycle"]["gates"]["upgrade"], "PASS")
            self.assertEqual(evidence["lifecycle"]["gates"]["rollback"], "PASS")
            self.assertEqual(evidence["lifecycle"]["app_control"]["code_integrity_3077"], "PASS")
            self.assertEqual(evidence["lifecycle"]["code_integrity_3077_count"], 0)
            self.assertTrue(evidence["signed_set_binding"]["rel013_post_sign_binding_required"])
            self.assertFalse(evidence["signed_set_binding"]["final_signed_set_pass_claimed"])

    def test_tampered_release_asset_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            module, contract, candidate, physical, release, setup = make_fixture(Path(td))
            setup.write_bytes(b"tampered")
            with self.assertRaisesRegex(module.EvidenceError, "setup release asset SHA-256 mismatch"):
                module.build_evidence(contract, candidate, physical, release)

    def test_blocked_or_partial_physical_gate_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            module, contract, candidate, physical_path, release, _ = make_fixture(Path(td))
            physical = json.loads(physical_path.read_text(encoding="utf-8"))
            physical["gates"]["repair"] = "BLOCK"
            physical_path.write_text(json.dumps(physical), encoding="utf-8")
            with self.assertRaisesRegex(module.EvidenceError, "repair"):
                module.build_evidence(contract, candidate, physical_path, release)

    def test_code_integrity_block_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            module, contract, candidate, physical_path, release, _ = make_fixture(Path(td))
            physical = json.loads(physical_path.read_text(encoding="utf-8"))
            physical["code_integrity_3077_count"] = 1
            physical_path.write_text(json.dumps(physical), encoding="utf-8")
            with self.assertRaisesRegex(module.EvidenceError, "3077"):
                module.build_evidence(contract, candidate, physical_path, release)

    def test_cli_writes_canonical_evidence_inside_release_directory(self):
        with tempfile.TemporaryDirectory() as td:
            module, contract, candidate, physical, release, _ = make_fixture(Path(td))
            rc = module.main([
                "--contract", str(contract),
                "--candidate-evidence", str(candidate),
                "--physical-result", str(physical),
                "--release-directory", str(release),
            ])
            self.assertEqual(rc, 0)
            output = release / module.CANONICAL_EVIDENCE_NAME
            self.assertTrue(output.is_file())
            evidence = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(evidence["result"], "PASS")

    def test_cli_refuses_noncanonical_or_external_output(self):
        with tempfile.TemporaryDirectory() as td:
            module, contract, candidate, physical, release, _ = make_fixture(Path(td))
            external = Path(td) / "external.json"
            rc = module.main([
                "--contract", str(contract),
                "--candidate-evidence", str(candidate),
                "--physical-result", str(physical),
                "--release-directory", str(release),
                "--output", str(external),
            ])
            self.assertEqual(rc, 2)
            self.assertFalse(external.exists())

    def test_script_has_no_secret_or_private_key_inputs(self):
        text = SCRIPT.read_text(encoding="utf-8").lower()
        self.assertNotIn("--pin", text)
        self.assertNotIn("--password", text)
        self.assertNotIn("--pfx", text)
        self.assertNotIn("private key", text)


if __name__ == "__main__":
    unittest.main()
