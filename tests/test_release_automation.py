import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ReleaseAutomationTests(unittest.TestCase):
    def read(self, name: str) -> str:
        return (ROOT / name).read_text(encoding="utf-8-sig")

    def test_release_workflow_file_exists(self):
        self.assertTrue((ROOT / ".github" / "workflows" / "release.yml").is_file())

    def test_triggers_configuration(self):
        workflow = self.read(".github/workflows/release.yml")
        self.assertIn("push:", workflow)
        self.assertIn("tags:", workflow)
        self.assertIn("- 'v*.*.*'", workflow)
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("pull_request:", workflow)
        self.assertIn("branches:", workflow)
        self.assertIn("- main", workflow)

    def test_reusable_workflow_call_and_no_build_duplication(self):
        windows_p0 = self.read(".github/workflows/windows-p0.yml")
        release = self.read(".github/workflows/release.yml")

        self.assertIn("workflow_call:", windows_p0)
        self.assertIn("uses: ./.github/workflows/windows-p0.yml", release)
        self.assertNotIn("PyInstaller", release)
        self.assertNotIn("Documents execution smoke", release)

    def test_installer_reusable_workflow_exports_artifact_name(self):
        installer = self.read(".github/workflows/windows-installer.yml")
        release = self.read(".github/workflows/release.yml")

        workflow_call = installer.split("\n  workflow_call:\n", 1)[1].split("\njobs:\n", 1)[0]
        self.assertIn("outputs:", workflow_call)
        self.assertIn("artifact_name:", workflow_call)
        self.assertIn(
            "value: ${{ jobs.installer.outputs.artifact_name }}",
            workflow_call,
        )
        self.assertIn(
            "name: ${{ needs.installer.outputs.artifact_name }}",
            release,
        )

    def test_permissions_are_least_privilege(self):
        release = self.read(".github/workflows/release.yml")
        # Global permissions must be read-only
        top_perms = release.split("jobs:")[0]
        self.assertIn("permissions:", top_perms)
        self.assertIn("contents: read", top_perms)
        self.assertNotIn("contents: write", top_perms)

        # Publish job must be the only place with contents: write
        publish_section = release.split("\n  publish:\n")[1]
        self.assertIn("contents: write", publish_section)
        self.assertNotIn("secrets.PAT", release)
        self.assertNotIn("secrets.GITHUB_TOKEN", release)
        self.assertIn("github.token", release)

    def test_tag_equality_and_ancestry_and_ci_guards(self):
        release = self.read(".github/workflows/release.yml")
        self.assertIn('EXPECTED_TAG="v${VERSION}"', release)
        self.assertIn('if [ "$TAG_NAME" != "$EXPECTED_TAG" ]', release)
        self.assertIn("git merge-base --is-ancestor", release)
        self.assertIn("origin/main", release)
        self.assertIn('gh api "repos/${{ github.repository }}/actions/runs', release)
        self.assertIn("Windows P0 portable", release)
        self.assertIn('.conclusion == "success"', release)

    def test_owner_signed_0_2_5_never_uses_automated_rebuild_publication(self):
        release = self.read(".github/workflows/release.yml")
        self.assertIn('if [ "$VERSION" = "0.2.5" ]', release)
        self.assertIn('OWNER_SIGNED_RELEASE="true"', release)
        self.assertIn('owner_signed_release=${OWNER_SIGNED_RELEASE}', release)
        self.assertIn('if [ "$OWNER_SIGNED_RELEASE" = "true" ]', release)
        self.assertIn("Automated CI rebuild publication is intentionally disabled", release)
        self.assertIn("Publish only the REL-011/012/013/015 verified owner-signed directory", release)
        self.assertIn("needs.validate.outputs.owner_signed_release != 'true'", release)
        self.assertIn('echo "should_publish=false" >> "$GITHUB_OUTPUT"', release)

    def test_publish_job_structural_protection(self):
        release = self.read(".github/workflows/release.yml")
        publish_section = release.split("\n  publish:\n")[1]
        self.assertIn("github.event_name == 'push'", publish_section)
        self.assertIn("github.ref_type == 'tag'", publish_section)
        self.assertIn("needs.validate.outputs.should_publish == 'true'", publish_section)

    def test_download_artifact_and_public_checksum_and_gh_release_create(self):
        release = self.read(".github/workflows/release.yml")
        self.assertIn("actions/download-artifact@v4", release)
        self.assertIn("sha256sum \"$ZIP_NAME\" > SHA256SUMS.txt", release)
        self.assertIn('SETUP_PATH="$(find release-stage -type f -name "$SETUP_NAME" -print -quit)"', release)
        self.assertIn('cp "$SETUP_PATH" "release-stage/${SETUP_NAME}"', release)
        self.assertIn("gh release create", release)
        self.assertIn("--verify-tag", release)
        self.assertIn("--generate-notes", release)
        self.assertIn("--prerelease", release)
        self.assertNotIn("--clobber", release)

    def test_duplicate_release_guard(self):
        release = self.read(".github/workflows/release.yml")
        self.assertIn('gh release view "$TAG"', release)
        self.assertIn('gh release view "$TAG_NAME"', release)

    def test_workflow_dispatch_and_pr_cannot_publish(self):
        release = self.read(".github/workflows/release.yml")
        self.assertIn('echo "should_publish=false"', release)
        self.assertIn("refs/heads/main", release)

    def test_cross_platform_release_includes_exact_main_astra_deb(self):
        release = self.read(".github/workflows/release.yml")
        self.assertIn('LINUX_DEB_NAME="Arvectum-Proxy-Launcher-${VERSION}-astra-linux-amd64.deb"', release)
        self.assertIn("linux-deb.yml/runs?head_sha=${{ github.sha }}", release)
        self.assertIn("Linux Debian package, RED OS RPM, and Linux AppImage push CI", release)
        self.assertIn("apl-lnx-007-deb-ubuntu-22.04", release)
        self.assertIn('sha256sum "$LINUX_DEB_NAME" >> SHA256SUMS.txt', release)
        self.assertIn('"release-stage/${LINUX_DEB_NAME}"', release)

    def test_cross_platform_release_includes_exact_main_redos_rpm(self):
        release = self.read(".github/workflows/release.yml")
        rpm_workflow = self.read(".github/workflows/linux-rpm.yml")
        self.assertIn('LINUX_RPM_NAME="Arvectum-Proxy-Launcher-${VERSION}-redos-linux-x86_64.rpm"', release)
        self.assertIn("linux-rpm.yml/runs?head_sha=${{ github.sha }}", release)
        self.assertIn("RED OS RPM, and Linux AppImage push CI", release)
        self.assertIn("apl-redos-rpm-ubuntu-22.04", release)
        self.assertIn('sha256sum "$LINUX_RPM_NAME" >> SHA256SUMS.txt', release)
        self.assertIn('"release-stage/${LINUX_RPM_NAME}"', release)
        self.assertIn("rpm2cpio", rpm_workflow)
        self.assertIn("tools/build_linux_rpm.sh", rpm_workflow)

    def test_cross_platform_release_includes_exact_main_appimage(self):
        release = self.read(".github/workflows/release.yml")
        appimage_workflow = self.read(".github/workflows/linux-appimage.yml")
        self.assertIn('LINUX_APPIMAGE_NAME="Arvectum_Proxy_Launcher-${VERSION}-x86_64.AppImage"', release)
        self.assertIn("linux-appimage.yml/runs?head_sha=${{ github.sha }}", release)
        self.assertIn("Linux AppImage push CI", release)
        self.assertIn("apl-lnx-008-appimage", release)
        self.assertIn('sha256sum "$LINUX_APPIMAGE_NAME" >> SHA256SUMS.txt', release)
        self.assertIn('"release-stage/${LINUX_APPIMAGE_NAME}"', release)
        self.assertIn("APPIMAGE_RUNTIME_LICENSE.txt", appimage_workflow)
        self.assertIn("tools/build_linux_appimage.sh", appimage_workflow)

    def test_cross_platform_release_includes_exact_main_macos_notarized_dmgs(self):
        release = self.read(".github/workflows/release.yml")
        macos = self.read(".github/workflows/macos-packaging.yml")
        production = self.read(".github/workflows/macos-production-signing.yml")
        policy = self.read("RELEASE_POLICY.md")

        self.assertIn(
            'MACOS_ARM_NAME="Arvectum-Proxy-Launcher-${VERSION}-macos-arm64.dmg"',
            release,
        )
        self.assertIn(
            'MACOS_X64_NAME="Arvectum-Proxy-Launcher-${VERSION}-macos-x64.dmg"',
            release,
        )
        self.assertIn(
            "macos-production-signing.yml/runs?head_sha=${{ github.sha }}",
            release,
        )
        self.assertIn(
            "macos-production-signing.yml/runs?head_sha=${{ github.sha }}&branch=main&event=workflow_dispatch",
            release,
        )
        self.assertIn("apl-mac-production-arm64", release)
        self.assertIn("apl-mac-production-x86_64", release)
        self.assertIn('sha256sum "$MACOS_ARM_NAME" >> SHA256SUMS.txt', release)
        self.assertIn('sha256sum "$MACOS_X64_NAME" >> SHA256SUMS.txt', release)
        self.assertIn('"release-stage/${MACOS_ARM_NAME}"', release)
        self.assertIn('"release-stage/${MACOS_X64_NAME}"', release)
        self.assertIn("macos-15-intel", macos)
        self.assertIn("Developer ID Application: LLC ARVECTUM", production)
        self.assertIn("ArvectumReleaseBot", production)
        self.assertIn("notarized", policy.lower())
        self.assertNotIn("Open Anyway", policy)

    def test_release_evidence_requires_macos_packaging_and_production_signing(self):
        evidence = self.read(".github/workflows/release-evidence.yml")
        self.assertIn(
            '"macos-packaging.yml|macOS packaging|required|push"',
            evidence,
        )
        self.assertIn(
            '"macos-production-signing.yml|macOS production signing|required|workflow_dispatch"',
            evidence,
        )
        self.assertIn(
            "github.event.workflow_run.event == 'workflow_dispatch'",
            evidence,
        )

    def test_pull_request_release_validation_does_not_duplicate_windows_builds(self):
        release = self.read(".github/workflows/release.yml")
        guard = "github.event_name != 'pull_request' && needs.validate.outputs.owner_signed_release != 'true'"
        self.assertGreaterEqual(release.count(guard), 2)
        self.assertIn("uses: ./.github/workflows/windows-p0.yml", release)
        self.assertIn("uses: ./.github/workflows/windows-installer.yml", release)

    def test_gitverse_mirror_accepts_prefixed_checksum_manifest(self):
        mirror = self.read(".github/workflows/sync-release-to-gitverse.yml")
        self.assertIn("-name '*SHA256SUMS.txt'", mirror)
        self.assertIn('test "${#manifests[@]}" -eq 1', mirror)
        self.assertIn('payload_count=', mirror)

    def test_gitverse_mirror_accepts_android_release_namespace(self):
        mirror = self.read(".github/workflows/sync-release-to-gitverse.yml")
        self.assertIn("android-v[0-9]*.[0-9]*.[0-9]*", mirror)
        self.assertIn("v[0-9]*.[0-9]*.[0-9]*", mirror)

    def test_release_calls_verified_gitverse_mirror(self):
        release = self.read(".github/workflows/release.yml")
        mirror = self.read(".github/workflows/sync-release-to-gitverse.yml")
        self.assertIn("uses: ./.github/workflows/sync-release-to-gitverse.yml", release)
        self.assertIn("secrets: inherit", release)
        self.assertIn("workflow_call:", mirror)
        self.assertIn("gh release download", mirror)
        self.assertIn("SHA256SUMS.txt", mirror)
        self.assertIn("single-file ZIP wrapper", mirror)
        self.assertIn("Immutable GitVerse asset differs", mirror)
        self.assertIn("-X PATCH", mirror)
        self.assertIn("UPDATED GitVerse release metadata", mirror)
        self.assertIn("gitverse-release-metadata-update.json", mirror)
        self.assertNotIn("DELETE", mirror)


if __name__ == "__main__":
    unittest.main()
