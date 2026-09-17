from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "docs" / "registry"


class RegistryFilingPackTests(unittest.TestCase):
    def test_required_documents_exist(self):
        required = {
            "README.md",
            "APL_REG_001D_APPLICATION_WORKSHEET_RU.md",
            "APL_REG_001D_FUNCTIONAL_CHARACTERISTICS_RU.md",
            "APL_REG_001D_INSTALL_OPERATION_MANUAL_RU.md",
            "APL_REG_001D_SUPPORT_MAINTENANCE_RU.md",
            "APL_REG_001D_LICENSE_PRICE_RU.md",
            "APL_REG_001D_EXPERT_TEST_PROCEDURE_RU.md",
            "APL_REG_001E_PRIVATE_EVIDENCE_CHECKLIST.md",
            "APL_REG_001F_PRE_SUBMISSION_AUDIT.md",
        }
        self.assertEqual(required, {p.name for p in REGISTRY.glob("*.md")})

    def test_pack_is_frozen_to_current_release_and_class(self):
        for path in REGISTRY.glob("*.md"):
            text = path.read_text(encoding="utf-8")
            if "001E_PRIVATE" not in path.name:
                self.assertIn("0.2.9", text, path.name)
        worksheet = (REGISTRY / "APL_REG_001D_APPLICATION_WORKSHEET_RU.md").read_text(encoding="utf-8")
        self.assertIn("02.02", worksheet)
        self.assertIn("Программы обслуживания", worksheet)

    def test_filing_blockers_are_explicit(self):
        audit = (REGISTRY / "APL_REG_001F_PRE_SUBMISSION_AUDIT.md").read_text(encoding="utf-8")
        for gate in ("G1", "G2", "G3", "G4", "G5", "G6"):
            self.assertIn(gate, audit)
        self.assertIn("HOLD", audit)
        self.assertIn("v0.2.9", audit)
        self.assertIn("exact public", audit)

    def test_public_pack_does_not_claim_closed_private_evidence(self):
        checklist = (REGISTRY / "APL_REG_001E_PRIVATE_EVIDENCE_CHECKLIST.md").read_text(encoding="utf-8")
        self.assertIn("PRIVATE/HUMAN", checklist)
        self.assertIn("BLOCKED", checklist)
        audit = (REGISTRY / "APL_REG_001F_PRE_SUBMISSION_AUDIT.md").read_text(encoding="utf-8")
        self.assertNotIn("READY TO FILE\n", audit)

    def test_exact_linux_release_gap_is_not_hidden(self):
        index = (REGISTRY / "README.md").read_text(encoding="utf-8")
        procedure = (REGISTRY / "APL_REG_001D_EXPERT_TEST_PROCEDURE_RU.md").read_text(encoding="utf-8")
        self.assertIn("v0.2.8", index)
        self.assertIn("v0.2.9", index)
        self.assertIn("exact public 0.2.9", procedure)


if __name__ == "__main__":
    unittest.main()
