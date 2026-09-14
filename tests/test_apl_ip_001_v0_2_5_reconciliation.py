import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "compliance" / "APL_IP_001_V0_2_5_CLEAN_IP.json"
SIGNOFF = ROOT / "docs" / "APL_IP_001_V0_2_5_SIGNOFF.md"
EVIDENCE = ROOT / "docs" / "evidence" / "APL_IP_001_V0_2_5_CANDIDATE_RECONCILIATION_2026-09-14.md"


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


def product_boundary(path: str) -> bool:
    p = Path(path)
    if len(p.parts) == 1 and (p.suffix == ".py" or p.suffix == ".bat"):
        return True
    if p.parts and p.parts[0] == "installer":
        return True
    return False


class AplIp001V025ReconciliationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(CONTRACT.read_text(encoding="utf-8"))

    def require_full_history_objects(self, *refs: str) -> None:
        missing = [ref for ref in refs if not git_object_available(ref)]
        if missing:
            self.skipTest(
                "historical Git objects unavailable in shallow checkout; "
                "dedicated APL-IP-001 workflow enforces this assertion with fetch-depth=0: "
                + ", ".join(missing)
            )

    def test_exact_release_identity(self):
        identity = self.data["accepted_release_identity"]
        self.assertEqual(identity["product_source_commit"], "9e8ca7e851563082cd7d03d7543ccb360a37ec27")
        self.assertEqual(identity["product_source_tree"], "12eb128762ba4e50d12af35c681aa80d0818e19a")
        self.assertEqual(identity["immutable_tag"], "v0.2.5")
        self.assertEqual(identity["immutable_tag_commit"], "6509d5e7228a90bb5c0b779ea6e2b9df0e9d0d85")
        self.assertEqual(identity["application_sha256"], "1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c")
        self.assertEqual(identity["setup_sha256"], "9b5368d67874b7164ee56a245c75db4b23af593a1d72f7e947774516abcc95e3")

    def test_immutable_tag_resolves_to_governed_commit(self):
        identity = self.data["accepted_release_identity"]
        self.require_full_history_objects(identity["immutable_tag"])
        resolved = git("rev-parse", f'{identity["immutable_tag"]}^{{commit}}')
        self.assertEqual(resolved, identity["immutable_tag_commit"])

    def test_accepted_source_is_ancestor_of_tag(self):
        identity = self.data["accepted_release_identity"]
        self.require_full_history_objects(identity["product_source_commit"], identity["immutable_tag_commit"])
        result = subprocess.run(
            ["git", "merge-base", "--is-ancestor", identity["product_source_commit"], identity["immutable_tag_commit"]],
            cwd=ROOT,
        )
        self.assertEqual(result.returncode, 0)

    def test_no_product_boundary_drift_source_to_tag_or_tag_to_review_main(self):
        identity = self.data["accepted_release_identity"]
        baseline = self.data["reconciliation_baseline"]
        pairs = [
            (identity["product_source_commit"], identity["immutable_tag_commit"]),
            (identity["immutable_tag_commit"], baseline["main_commit_at_review_start"]),
        ]
        self.require_full_history_objects(*(ref for pair in pairs for ref in pair))
        for left, right in pairs:
            changed = [p for p in git("diff", "--name-only", left, right).splitlines() if p]
            material = [p for p in changed if product_boundary(p)]
            self.assertEqual(material, [], f"unexpected product-boundary drift {left}..{right}: {material}")

    def test_material_historical_runtime_drift_is_explicit(self):
        paths = {entry["path"] for entry in self.data["material_product_source_drift_since_historical_candidate"]}
        self.assertEqual(
            paths,
            {"application_filesystem.py", "portable_lifecycle.py", "proxy_core.py", "recovery_autostart.py"},
        )
        for entry in self.data["material_product_source_drift_since_historical_candidate"]:
            self.assertTrue(entry["human_factual_carry_forward_required"])
            self.assertEqual(entry["engineering_review"], "REVIEWED_NO_OBVIOUS_EXTERNAL_SOURCE_IMPORT")

    def test_exact_accepted_source_has_provenance_and_sbom_evidence(self):
        automated = self.data["automated_evidence"]
        self.assertEqual(automated["provenance"]["workflow_run_id"], 34720855901)
        self.assertEqual(automated["provenance"]["artifact_id"], 10306615531)
        self.assertEqual(automated["provenance"]["result"], "SUCCESS")
        self.assertEqual(automated["sbom"]["workflow_run_id"], 34720856022)
        self.assertEqual(automated["sbom"]["artifact_id"], 10306326080)
        self.assertEqual(automated["sbom"]["result"], "SUCCESS")
        self.assertEqual(automated["sbom"]["digest_scope"], "GITHUB_ARTIFACT_ARCHIVE")

    def test_human_legal_gates_cannot_be_automatically_approved(self):
        for gate in ("R-1", "R-2", "R-3", "R-4"):
            self.assertEqual(self.data["human_legal_gates"][gate]["status"], "HUMAN_REQUIRED")
        policy = self.data["policy"]
        self.assertFalse(policy["automated_legal_approval"])
        self.assertFalse(policy["automated_authorship_proof"])
        self.assertFalse(policy["clean_ip_tag_authorized"])
        self.assertFalse(policy["existing_v0_2_5_tag_may_be_moved"])
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
