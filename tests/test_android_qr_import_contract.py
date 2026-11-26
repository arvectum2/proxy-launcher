"""QR image source/build boundary checks, not a substitute for device tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "mobile/android/app"
BASE = APP / "src/main/java/ru/arvectum/proxylauncher"
ACTIVITY = (BASE / "MainActivity.kt").read_text()
READER = (BASE / "importing/ProxyQrImageReader.kt").read_text()
DECODER = (BASE / "model/ProxyQrImport.kt").read_text()
GRADLE = (APP / "build.gradle.kts").read_text()

class QrImportContract(unittest.TestCase):
    def test_pinned_dependency_and_license(self):
        self.assertIn('implementation("com.google.zxing:core:3.5.4")', GRADLE)
        self.assertIn('strictly("3.5.4")', GRADLE)
        self.assertIn("71de5d89341b5fcf5dd89da7f44e84d825d0e084cdf3ec77c9abe26b0f0ceb13", GRADLE)
        self.assertIn("dependsOn(generateBrandingResources, verifyZxingCore, verifySubscriptionArtifacts)", GRADLE)
        for name in ("LICENSE", "NOTICE"):
            self.assertTrue((APP / "src/main/assets/licenses/zxing" / name).stat().st_size > 0)

    def test_qr_uses_only_explicit_picker_and_preview(self):
        picker = ACTIVITY.split("private fun chooseQrImage()", 1)[1].split("private fun importSelectedQrImage(", 1)[0]
        worker = ACTIVITY.split("private fun importSelectedQrImage(", 1)[1].split("private fun requestQrCamera()", 1)[0]
        self.assertIn("if (!canBatchImport()) return", picker)
        self.assertIn("Intent.ACTION_OPEN_DOCUMENT", picker)
        self.assertIn('arrayOf("image/png", "image/jpeg", "image/webp")', picker)
        self.assertIn('uri.scheme != "content"', worker)
        self.assertIn("use(ProxyQrImageReader::read)", worker)
        self.assertIn("generation != batchImportGeneration", worker)
        self.assertIn("showBatchPreview(items)", worker)
        for forbidden in ("appendImportedProfiles", "connectVpn()", "takePersistableUriPermission", "Log."):
            self.assertNotIn(forbidden, picker + worker)
        manifest = (APP / "src/main/AndroidManifest.xml").read_text()
        self.assertNotIn("Manifest.permission.CAMERA", picker + worker)
        self.assertIn('android:name="android.hardware.camera" android:required="false"', manifest)
        self.assertNotIn("arvectum-proxy", manifest)

    def test_decode_bounds_and_no_implicit_navigation(self):
        self.assertIn("inJustDecodeBounds = true", READER)
        self.assertIn("ProxyQrImport.sampleSize", READER)
        self.assertIn("bitmap.recycle()", READER)
        self.assertIn("bytes.fill(0)", READER)
        self.assertIn("results.singleOrNull()", DECODER)
        self.assertIn("result.resultPoints.isNullOrEmpty()", DECODER)
        self.assertIn("ProxyBatchImport.parse(text)", DECODER)
        self.assertIn("ProxyImport.parse(value)", DECODER)

if __name__ == "__main__":
    unittest.main()
