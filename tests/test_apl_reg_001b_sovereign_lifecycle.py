import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "compliance" / "APL_REG_001B_SOVEREIGN_LIFECYCLE.json"


class SovereignLifecycleContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(CONTRACT.read_text(encoding="utf-8"))

    def test_contract_identity(self):
        self.assertEqual(self.data["schema"], "arvectum.proxy.apl-reg-001b.sovereign-lifecycle.v1")
        self.assertEqual(self.data["tracking_issue"], 55)
        self.assertEqual(self.data["product"], "Arvectum Proxy Launcher")

    def test_fail_closed_policy(self):
        policy = self.data["policy"]
        self.assertFalse(policy["github_is_authoritative_registry_evidence"])
        self.assertFalse(policy["production_build_may_require_pypi"])
        self.assertFalse(policy["russian_service_name_alone_proves_compliance"])
        self.assertFalse(policy["private_keys_or_credentials_in_repository"])
        self.assertFalse(policy["v0_2_5_mutable"])

    def test_offline_production_build_is_required(self):
        build = self.data["lifecycle"]["build_and_compilation"]
        self.assertEqual(build["target_role"], "RUSSIAN_CONTROLLED_PRODUCTION_BUILD")
        self.assertEqual(build["windows_dependency_mode"], "offline-hash-locked")
        self.assertFalse(build["pypi_required"])
        self.assertIn("build-result.json with dependency_mode=offline-hash-locked", build["required_evidence"])

    def test_github_is_mirror_not_single_point(self):
        source = self.data["lifecycle"]["source_code"]
        artifacts = self.data["lifecycle"]["object_code_and_artifacts"]
        self.assertEqual(source["target_role"], "RUSSIAN_CONTROLLED_AUTHORITATIVE")
        self.assertEqual(source["github_role"], "COLLABORATION_AND_PUBLIC_MIRROR")
        self.assertEqual(artifacts["github_releases_role"], "OPTIONAL_PUBLIC_MIRROR")

    def test_current_activation_is_not_applicable(self):
        activation = self.data["lifecycle"]["activation_and_license_keys"]
        self.assertFalse(activation["present"])
        self.assertEqual(activation["status"], "NOT_APPLICABLE_CURRENT_PRODUCT_SCOPE")

    def test_required_bundle_inputs_exist(self):
        for relative in self.data["release_evidence_bundle"]["required_files"]:
            if relative == "build-result.json" or relative == "SHA256SUMS.txt":
                continue
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_generator_contains_fail_closed_invariants(self):
        text = (ROOT / "tools" / "apl_reg_001b_release_evidence.py").read_text(encoding="utf-8")
        self.assertIn('dependency_mode") != "offline-hash-locked"', text)
        self.assertIn("github_is_authoritative_registry_evidence", text)
        self.assertIn("MANIFEST.sha256", text)
        self.assertIn("artifact SHA256 does not match build-result.json", text)


if __name__ == "__main__":
    unittest.main()
