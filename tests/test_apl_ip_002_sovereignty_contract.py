import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "compliance" / "APL_IP_002_STACK_SOVEREIGNTY.json"


class AplIp002SovereigntyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = json.loads(CONTRACT.read_text(encoding="utf-8"))
        cls.components = {item["id"]: item for item in cls.doc["components"]}

    def test_schema_and_policy_fail_closed(self):
        self.assertEqual(
            self.doc["schema"],
            "arvectum.proxy.apl-ip-002.stack-sovereignty.v1",
        )
        policy = self.doc["policy"]
        self.assertFalse(policy["foreign_oss_is_automatic_registry_failure"])
        self.assertFalse(policy["build_only_equals_runtime_dependency"])
        self.assertFalse(policy["user_supplied_upstream_is_vendor_saas"])
        self.assertFalse(policy["github_is_sovereign_lifecycle_evidence"])
        self.assertFalse(policy["gitverse_mirror_alone_proves_full_lifecycle_compliance"])

    def test_runtime_has_no_vendor_cloud_control_plane(self):
        runtime = self.doc["runtime_findings"]
        self.assertFalse(runtime["mandatory_vendor_api"])
        self.assertFalse(runtime["mandatory_vendor_cloud"])
        self.assertFalse(runtime["telemetry_service"])
        self.assertFalse(runtime["license_server"])
        self.assertFalse(runtime["automatic_update_service"])
        self.assertTrue(runtime["configured_upstream_proxy_is_user_supplied"])

    def test_material_stack_boundaries_are_present(self):
        required = {
            "cpython-3.12.10",
            "tcl-tk",
            "pyinstaller-6.22.0",
            "inno-setup-6.7.1",
            "windows-platform",
            "linux-networkmanager-polkit",
            "appimage-toolchain",
            "user-upstream-proxy",
            "github",
            "gitverse",
            "cryptopro-rutoken-release-evidence",
            "github-actions-security-tools",
        }
        self.assertTrue(required.issubset(self.components))

    def test_every_component_has_governance_fields(self):
        required = {
            "id",
            "name",
            "version",
            "scope",
            "origin",
            "rightsholder",
            "license",
            "bundled_in_release",
            "runtime_network_required",
            "criticality",
            "replaceability",
            "russian_alternative",
            "registry_risk",
            "evidence",
            "action",
        }
        for component in self.doc["components"]:
            self.assertTrue(required.issubset(component), component["id"])
            self.assertTrue(component["scope"], component["id"])
            self.assertTrue(component["evidence"], component["id"])

    def test_windows_offline_build_is_a_pass_gate(self):
        self.assertEqual(
            self.doc["gates"]["windows_offline_hash_locked_build_capability"],
            "PASS",
        )
        script = (ROOT / "tools" / "clean_build_windows.ps1").read_text(encoding="utf-8")
        self.assertIn("--no-index", script)
        self.assertIn("--require-hashes", script)
        self.assertIn("requirements-build.windows-x64.hashes.txt", script)

    def test_locked_windows_build_dependencies_are_governed(self):
        lock_entries = []
        for raw in (ROOT / "requirements-build.lock.txt").read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            lock_entries.append(line.split("==", 1)[0].lower())
        names = {c["name"].lower() for c in self.doc["components"]}
        for name in lock_entries:
            self.assertIn(name, names, f"missing APL-IP-002 inventory entry for {name}")

    def test_github_is_not_accepted_as_sovereign_baseline(self):
        github = self.components["github"]
        self.assertEqual(github["origin"], "FOREIGN_CLOUD_SERVICE")
        self.assertIn("REMEDIATION_REQUIRED", github["registry_risk"])
        self.assertEqual(self.doc["gates"]["sovereign_build_ci"], "MISSING")

    def test_gitverse_is_only_partial_evidence(self):
        gitverse = self.components["gitverse"]
        self.assertEqual(gitverse["origin"], "RUSSIAN_SERVICE")
        self.assertEqual(gitverse["registry_risk"], "EVIDENCE_REQUIRED")
        self.assertEqual(self.doc["gates"]["sovereign_source_storage"], "PARTIAL")
        self.assertEqual(self.doc["gates"]["sovereign_artifact_distribution"], "PARTIAL")

    def test_external_and_followup_gates_remain_open(self):
        gates = self.doc["gates"]
        self.assertEqual(gates["foreign_payment_accounting_review"], "EXTERNAL_PENDING")
        self.assertEqual(gates["release_bound_legal_disposition"], "PENDING_APL_IP_001")
        self.assertTrue(self.doc["handoff"]["APL-REG-001B"])
        self.assertTrue(self.doc["handoff"]["APL-IP-001"])


if __name__ == "__main__":
    unittest.main()
