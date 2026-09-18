import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tools import third_party_license_bundle as bundle


REPO = Path(__file__).resolve().parents[1]


class LicenseBundleVerificationTests(unittest.TestCase):
    def make_bundle(self, root: Path) -> Path:
        records = []
        for component in bundle.REQUIRED_COMPONENTS:
            target = root / component / "LICENSE-1.txt"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(f"complete license fixture for {component}\n", encoding="utf-8")
            records.append(
                {
                    "component": component,
                    "source_basename": "LICENSE.txt",
                    "bundle_path": target.relative_to(root).as_posix(),
                    "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                }
            )
        manifest = {
            "schema": bundle.SCHEMA,
            "python_version": "fixture",
            "platform": "fixture",
            "components": list(bundle.REQUIRED_COMPONENTS),
            "files": records,
        }
        (root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        return root

    def test_verified_bundle_requires_all_component_texts_and_hashes(self):
        with tempfile.TemporaryDirectory() as td:
            root = self.make_bundle(Path(td))
            manifest = bundle.verify_bundle(root)
            self.assertEqual(set(manifest["components"]), set(bundle.REQUIRED_COMPONENTS))

    def test_tampered_license_text_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            root = self.make_bundle(Path(td))
            (root / "python" / "LICENSE-1.txt").write_text("tampered\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "hash mismatch"):
                bundle.verify_bundle(root)

    def test_missing_component_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            root = self.make_bundle(Path(td))
            manifest_path = root / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["components"].remove("tk")
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "missing required components"):
                bundle.verify_bundle(root)


class PromotedArtifactContractTests(unittest.TestCase):
    def test_windows_portable_workflow_has_fail_closed_gate(self):
        workflow = (REPO / ".github" / "workflows" / "windows-p0.yml").read_text(encoding="utf-8")
        self.assertIn("windows_promoted_license_compliance.ps1", workflow)

    def test_windows_gate_r6_requires_manifest_and_hash_bound_bundle(self):
        acceptance = (REPO / "tools" / "windows_rc_acceptance.ps1").read_text(encoding="utf-8")
        self.assertIn("THIRD_PARTY_LICENSES", acceptance)
        self.assertIn("arvectum.third-party-license-bundle.v1", acceptance)
        self.assertIn("Get-FileHash -LiteralPath $fullPath -Algorithm SHA256", acceptance)
        self.assertIn("$manifestAllowed", acceptance)
        self.assertIn("portable.contents", acceptance)

    def test_windows_installer_embeds_product_and_third_party_licenses(self):
        iss = (REPO / "installer" / "ArvectumProxyLauncher.iss").read_text(encoding="utf-8")
        self.assertIn('Source: "{#PayloadDir}\\LICENSE.txt"', iss)
        self.assertIn('Source: "{#PayloadDir}\\THIRD_PARTY_NOTICES.txt"', iss)
        self.assertIn('Source: "{#PayloadDir}\\THIRD_PARTY_LICENSES\\*"', iss)

    def test_linux_deb_embeds_verified_bundle(self):
        script = (REPO / "tools" / "build_linux_deb.sh").read_text(encoding="utf-8")
        self.assertIn("third_party_license_bundle.py --build", script)
        self.assertIn("usr/share/doc/$package/THIRD_PARTY_LICENSES", script)

    def test_macos_app_and_dmg_embed_verified_bundle(self):
        app = (REPO / "tools" / "build_macos_app.sh").read_text(encoding="utf-8")
        dmg = (REPO / "tools" / "build_macos_dmg.sh").read_text(encoding="utf-8")
        self.assertIn("Contents/Resources", app)
        self.assertIn("THIRD_PARTY_LICENSES", app)
        self.assertIn("THIRD_PARTY_LICENSES", dmg)
        self.assertIn("--verify", dmg)

    def test_appimage_promotion_preserves_historical_hold_and_adds_runtime_notice(self):
        script = (REPO / "tools" / "build_linux_appimage.sh").read_text(encoding="utf-8")
        runtime_notice = (REPO / "APPIMAGE_RUNTIME_LICENSE.txt").read_text(encoding="utf-8")
        roadmap = (REPO / "docs" / "ROADMAP.md").read_text(encoding="utf-8")
        self.assertIn("APPIMAGE_RUNTIME_LICENSE.txt", script)
        self.assertIn("AppImage/type2-runtime commit 75849dce7cc37e4319b633df1f116ca895c71a12", runtime_notice)
        self.assertNotIn("EXCLUDED from promoted commercial scope", script)
        self.assertIn("PROMOTED FOR NEXT RELEASE", roadmap)

        # Historical APL-IP-004 evidence remains immutable context and must not be
        # rewritten merely because a later Owner directive admits AppImage.
        review = (REPO / "docs" / "evidence" / "APL_IP_001_POST_REFACTOR_REVIEW_2026-08-22.md").read_text(encoding="utf-8")
        self.assertIn("APPIMAGE EXCLUDED FROM THE CLEAN-IP PROMOTED COMMERCIAL ARTIFACT SCOPE", review)


if __name__ == "__main__":
    unittest.main()
