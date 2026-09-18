import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "compliance" / "APL_IP_001_V0_2_9_CLEAN_IP.json"
SIGNOFF = ROOT / "docs" / "APL_IP_001_V0_2_9_SIGNOFF.md"
EVIDENCE = ROOT / "docs" / "evidence" / "APL_IP_001_V0_2_9_CANDIDATE_RECONCILIATION_2026-09-18.md"


def git(*args: str, check: bool = True) -> str:
    completed = subprocess.run(
        ["git", *args], cwd=ROOT, text=True, capture_output=True, check=check
    )
    return completed.stdout.strip()


def git_object_available(ref: str) -> bool:
    completed = subprocess.run(
        ["git", "cat-file", "-e", f"{ref}^{{commit}}"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    return completed.returncode == 0


class AplIp001V029ReconciliationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(CONTRACT.read_text(encoding="utf-8"))

    def require_full_history_objects(self, *refs: str) -> None:
        missing = [ref for ref in refs if not git_object_available(ref)]
        if missing:
            self.skipTest(
                "historical Git objects unavailable in shallow checkout; "
                "dedicated APL-IP-001 workflow enforces this with fetch-depth=0: "
                + ", ".join(missing)
            )

    def test_exact_release_identity(self):
        identity = self.data["accepted_release_identity"]
        self.assertEqual(identity["product_source_commit"], "ca7c1019e78cb3ee1e57173f2b58ecea0c27b919")
        self.assertEqual(identity["product_source_tree"], "55f2d50f96387e5d55583ac90ca3d0b48f80ce99")
        self.assertEqual(identity["immutable_tag"], "v0.2.9")
        self.assertEqual(identity["annotated_tag_object"], "59dfd56191c8d9aa0e71a9fba2d86baaaf843520")
        self.assertEqual(identity["immutable_tag_commit"], "d13d9dac2ae2439c2fe70d32e1b168df320a9bd2")
        self.assertEqual(identity["tag_commit_tree"], identity["product_source_tree"])

    def test_tag_resolves_to_governed_commit(self):
        identity = self.data["accepted_release_identity"]
        self.require_full_history_objects(identity["immutable_tag"])
        resolved = git("rev-parse", f'{identity["immutable_tag"]}^{{commit}}')
        self.assertEqual(resolved, identity["immutable_tag_commit"])

    def test_source_and_tag_are_exact_same_tree(self):
        identity = self.data["accepted_release_identity"]
        self.require_full_history_objects(identity["product_source_commit"], identity["immutable_tag_commit"])
        source_tree = git("rev-parse", f'{identity["product_source_commit"]}^{{tree}}')
        tag_tree = git("rev-parse", f'{identity["immutable_tag_commit"]}^{{tree}}')
        self.assertEqual(source_tree, identity["product_source_tree"])
        self.assertEqual(tag_tree, identity["tag_commit_tree"])
        self.assertEqual(source_tree, tag_tree)

    def test_release_asset_digests_are_governed(self):
        assets = self.data["accepted_release_identity"]["release_assets"]
        expected = {
            "windows_portable_zip_sha256": "6f541b28c08834170258b48e27ffeafc6a0ad0e9c3a27760ec02cc7d01a305d0",
            "windows_setup_sha256": "a483c64205ad8a0d7a2e53e795714dd67d30c5c95f70f231d05a45b6f6db425c",
            "astra_deb_sha256": "f1bdb58ed4dad02bcc391ae88c8102062a2ed75860f5735cbe45dd6569d77711",
            "redos_rpm_sha256": "59a3a45562da3c65691e901471bdaab16f0de94f5bbc4dfa786f524d417660fc",
            "sha256sums_asset_sha256": "20042bcc6e65fce39cdeb777ff4c6e06c91403034cbcd1eaf1bd9ecc9823bc38",
        }
        self.assertEqual(assets, expected)
        for digest in assets.values():
            self.assertEqual(len(digest), 64)

    def test_material_release_steps_all_require_human_carry_forward(self):
        drift = self.data["material_drift_since_v0_2_5"]
        self.assertEqual(
            set(drift),
            {
                "v0_2_5_to_v0_2_6",
                "v0_2_6_to_v0_2_7",
                "v0_2_7_to_v0_2_8",
                "v0_2_8_to_v0_2_9",
            },
        )
        self.assertTrue(all(item["human_factual_carry_forward_required"] for item in drift.values()))

    def test_exact_tree_has_provenance_and_sbom_evidence(self):
        tree = self.data["accepted_release_identity"]["product_source_tree"]
        automated = self.data["automated_evidence"]
        self.assertEqual(automated["provenance"]["workflow_run_id"], 35255499712)
        self.assertEqual(automated["provenance"]["artifact_id"], 10511679846)
        self.assertEqual(automated["provenance"]["evidence_tree"], tree)
        self.assertEqual(automated["provenance"]["result"], "SUCCESS")
        self.assertEqual(automated["sbom"]["workflow_run_id"], 35255499669)
        self.assertEqual(automated["sbom"]["artifact_id"], 10512014953)
        self.assertEqual(automated["sbom"]["evidence_tree"], tree)
        self.assertEqual(automated["sbom"]["result"], "SUCCESS")

    def test_existing_private_instrument_is_preserved_without_fabricated_scope(self):
        rights = self.data["rights_basis"]
        self.assertEqual(rights["private_instrument_date"], "2026-09-14")
        self.assertFalse(rights["duplicate_version_specific_reexecution_required_by_repository"])
        self.assertFalse(rights["future_result_scope_verified"])
        self.assertEqual(rights["post_2026_09_14_contributions_basis"], "HUMAN_REQUIRED")

    def test_human_legal_gates_cannot_be_automatically_approved(self):
        for gate in ("R-1A", "R-1B", "R-2", "R-3", "R-4"):
            self.assertEqual(self.data["human_legal_gates"][gate]["status"], "HUMAN_REQUIRED")
        policy = self.data["policy"]
        self.assertFalse(policy["automated_legal_approval"])
        self.assertFalse(policy["automated_authorship_proof"])
        self.assertFalse(policy["clean_ip_tag_authorized"])
        self.assertFalse(policy["existing_release_tags_may_be_moved"])
        self.assertEqual(self.data["machine_verdict"], "CONDITIONAL_HUMAN_LEGAL_GATE")

    def test_appimage_remains_out_of_scope_hold(self):
        self.assertEqual(
            self.data["third_party_boundary"]["appimage_distribution_status"],
            "HOLD_EXCLUDED_FROM_CURRENT_CLEAN_IP_APPROVAL_SCOPE",
        )

    def test_signoff_and_evidence_are_fail_closed(self):
        signoff = SIGNOFF.read_text(encoding="utf-8")
        evidence = EVIDENCE.read_text(encoding="utf-8")
        self.assertIn("NOT APPROVED", signoff)
        self.assertIn("NO CLEAN-IP TAG MAY BE CREATED", signoff)
        self.assertIn("NO CLEAN-IP TAG IS AUTHORIZED", evidence)
        self.assertIn("CONDITIONAL_HUMAN_LEGAL_GATE", evidence)


if __name__ == "__main__":
    unittest.main()
