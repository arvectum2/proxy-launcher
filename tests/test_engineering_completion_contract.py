import json
import pathlib
import unittest

import proxy_core


ROOT = pathlib.Path(__file__).resolve().parents[1]
CANONICAL_WORKFLOW = ROOT / ".github" / "workflows" / "apl-ip-003-canonical-source.yml"
PROVENANCE_WORKFLOW = ROOT / ".github" / "workflows" / "ip-provenance.yml"
SBOM_WORKFLOW = ROOT / ".github" / "workflows" / "sbom.yml"
SEALED_023_EVIDENCE = ROOT / "docs" / "evidence" / "WINDOWS_RUSSIAN_PRODUCTION_SIGNING_ACCEPTANCE_2026-08-20.json"
REQUIRED_HYGIENE_GUARDS = (
    "tests/test_source_hygiene.py",
    "tests/test_repository_hygiene.py",
    "tests/test_application_boundary_hygiene.py",
)


class EngineeringCompletionContractTests(unittest.TestCase):
    def test_current_version_matches_runtime_while_sealed_0_2_3_history_remains_immutable(self):
        version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
        self.assertEqual(proxy_core.APP_VERSION, version)
        self.assertTrue(SEALED_023_EVIDENCE.is_file())
        sealed = json.loads(SEALED_023_EVIDENCE.read_text(encoding="utf-8"))
        self.assertEqual(sealed["version"], "0.2.3")

    def test_retired_compatibility_module_is_physically_absent(self):
        retired = ROOT / ("proxy_core_" + "legacy.py")
        self.assertFalse(retired.exists())

    def test_all_permanent_hygiene_guards_are_wired_cross_platform(self):
        workflow = CANONICAL_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("os: [ubuntu-latest, macos-latest, windows-latest]", workflow)
        for relative in REQUIRED_HYGIENE_GUARDS:
            with self.subTest(path=relative):
                self.assertTrue((ROOT / relative).is_file())
                self.assertIn(relative, workflow)

    def test_mailmap_normalizes_only_human_history(self):
        mailmap = (ROOT / ".mailmap").read_text(encoding="utf-8")
        self.assertIn("Arvectum <arvectum@gmail.com> arutyunoveth", mailmap)
        self.assertNotIn("OpenAI", mailmap)
        self.assertNotIn("automation@", mailmap)

    def test_provenance_and_sbom_regenerate_for_main_candidates(self):
        provenance = PROVENANCE_WORKFLOW.read_text(encoding="utf-8")
        sbom = SBOM_WORKFLOW.read_text(encoding="utf-8")
        for workflow in (provenance, sbom):
            self.assertIn("pull_request:", workflow)
            self.assertIn("push:", workflow)
            self.assertIn("main", workflow)
        self.assertIn("tools/ip_provenance_check.py", provenance)
        self.assertIn("human_review_required", provenance)
        self.assertIn("legal_signoff_required", provenance)
        self.assertIn("CycloneDX", sbom)
        self.assertIn("requirements-build.lock.txt", sbom)

    def test_clean_ip_approval_remains_explicitly_human_legal_gated(self):
        provenance = (ROOT / "IP_PROVENANCE.md").read_text(encoding="utf-8")
        self.assertIn("HUMAN-LEGAL SIGN-OFF PENDING", provenance)
        self.assertIn("Clean IP baseline/tag: **BLOCKED**", provenance)
        self.assertIn("explicitly APPROVED", provenance)


if __name__ == "__main__":
    unittest.main()