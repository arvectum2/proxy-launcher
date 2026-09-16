import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ReleaseEvidenceWorkflowTests(unittest.TestCase):
    def read(self, name: str) -> str:
        return (ROOT / name).read_text(encoding="utf-8-sig")

    def test_workflow_exists_and_runs_after_main_sast(self):
        workflow = self.read(".github/workflows/release-evidence.yml")
        self.assertIn("name: Release Evidence Package", workflow)
        self.assertIn("workflow_run:", workflow)
        self.assertIn("- SAST", workflow)
        self.assertIn("- completed", workflow)
        self.assertIn("- main", workflow)
        self.assertIn("workflow_dispatch:", workflow)

    def test_permissions_are_read_only(self):
        workflow = self.read(".github/workflows/release-evidence.yml")
        top = workflow.split("jobs:")[0]
        self.assertIn("contents: read", top)
        self.assertIn("actions: read", top)
        self.assertNotIn("contents: write", workflow)

    def test_exact_sha_and_main_ancestry_are_required(self):
        workflow = self.read(".github/workflows/release-evidence.yml")
        self.assertIn("github.event.workflow_run.head_sha", workflow)
        self.assertIn("40-character commit SHA", workflow)
        self.assertIn('git merge-base --is-ancestor "$SOURCE_SHA" origin/main', workflow)
        self.assertIn('test "$(git rev-parse HEAD)" = "$SOURCE_SHA"', workflow)

    def test_all_release_gates_are_collected_for_exact_push_sha(self):
        workflow = self.read(".github/workflows/release-evidence.yml")
        for required in (
            "windows-p0.yml|Windows P0 portable|required",
            "windows-installer.yml|Windows installer|required",
            "linux-deb.yml|APL-LNX-007 Debian package|required",
            "secret-scan.yml|Secret scan|optional",
            "dependency-scan.yml|Dependency vulnerability scan|optional",
            "sbom.yml|SBOM|required",
            "sast.yml|SAST|required",
        ):
            self.assertIn(required, workflow)
        self.assertIn("head_sha=${SOURCE_SHA}&event=push", workflow)
        self.assertIn('.conclusion // ""', workflow)
        self.assertIn('"success"', workflow)

    def test_exact_scanner_artifacts_are_embedded_and_verified(self):
        workflow = self.read(".github/workflows/release-evidence.yml")
        self.assertIn('arvectum-proxy-launcher-sbom-${SOURCE_SHA}', workflow)
        self.assertIn('arvectum-proxy-launcher-sast-${SOURCE_SHA}', workflow)
        self.assertIn("sha256sum -c arvectum-proxy-launcher-build.cdx.json.sha256", workflow)
        self.assertIn('sbom.get("bomFormat") != "CycloneDX"', workflow)
        self.assertIn('Path("evidence/sast/bandit.json")', workflow)

    def test_manifest_source_hashes_and_package_seal_are_present(self):
        workflow = self.read(".github/workflows/release-evidence.yml")
        self.assertIn("evidence/workflow-runs.json", workflow)
        self.assertIn("evidence/manifest.json", workflow)
        self.assertIn("evidence/source-inputs.sha256", workflow)
        self.assertIn(".github/workflows/release-evidence.yml", workflow)
        self.assertIn(".github/workflows/linux-deb.yml", workflow)
        self.assertIn(".github/workflows/release.yml", workflow)
        self.assertIn(".github/workflows/sync-release-to-gitverse.yml", workflow)
        self.assertIn("SHA256SUMS.txt", workflow)
        self.assertIn("sha256sum -c SHA256SUMS.txt", workflow)

    def test_evidence_artifact_is_exact_sha_named_and_retained(self):
        workflow = self.read(".github/workflows/release-evidence.yml")
        self.assertIn(
            "arvectum-proxy-launcher-release-evidence-${{ steps.source.outputs.sha }}",
            workflow,
        )
        self.assertIn("retention-days: 90", workflow)
        self.assertIn(
            "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
            workflow,
        )

    def test_public_release_requires_green_release_evidence(self):
        release = self.read(".github/workflows/release.yml")
        self.assertIn(".github/workflows/release-evidence.yml", release)
        self.assertIn("Release Evidence Package", release)
        self.assertIn("SUCCESSFUL_EVIDENCE_RUN", release)
        self.assertIn("release-evidence.yml/runs?head_sha=${{ github.sha }}", release)
        self.assertIn('.conclusion == "success"', release)


if __name__ == "__main__":
    unittest.main()
