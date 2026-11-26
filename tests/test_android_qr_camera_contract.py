"""Static lifecycle and permission boundaries; not hardware acceptance."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'mobile/android/app/src/main'
MAIN = (APP / 'java/ru/arvectum/proxylauncher/MainActivity.kt').read_text()
SCANNER = (APP / 'java/ru/arvectum/proxylauncher/importing/ProxyQrCameraDialog.kt').read_text()

class CameraContract(unittest.TestCase):
    def test_optional_permission_and_explicit_request(self):
        root = ET.parse(APP / 'AndroidManifest.xml').getroot()
        ns = '{http://schemas.android.com/apk/res/android}'
        for feature in ('android.hardware.camera','android.hardware.camera.autofocus'):
            self.assertTrue(any(e.get(ns+'name') == feature and e.get(ns+'required') == 'false' for e in root.findall('uses-feature')))
        self.assertEqual(MAIN.count('requestPermissions(arrayOf(Manifest.permission.CAMERA)'),1)
        self.assertIn('setOnClickListener { requestQrCamera() }',MAIN)
        self.assertIn('if (!cameraUiResumed || !canBatchImport()) return',MAIN)
        self.assertIn('checkSelfPermission(Manifest.permission.CAMERA)',SCANNER)

    def test_closed_callbacks_and_preview_only(self):
        pause = MAIN.split('override fun onPause() {',1)[1].split('override fun onStop()',1)[0]
        self.assertIn('qrCameraDialog?.close()',pause)
        self.assertIn('cameraUiResumed = false',pause)
        self.assertIn('if (cameraUiResumed && canBatchImport()) showBatchPreview(items)',MAIN)
        self.assertIn('if (closed) { device.close(); return }',SCANNER)
        self.assertIn('if (closed) { configured.close(); return }',SCANNER)
        self.assertIn('delivered.compareAndSet(false, true)',SCANNER)
        self.assertIn('if (!closed && dialog.isShowing)',SCANNER)
        for forbidden in ('saveProfile(', 'connectVpn()', 'Log.', 'ClipboardManager', 'FileOutputStream'):
            self.assertNotIn(forbidden,SCANNER)

    def test_bounded_frame_and_cleanup(self):
        self.assertIn('ProxyQrCameraFrame.supportedSize',SCANNER)
        self.assertIn('acquireLatestImage()?.use',SCANNER)
        self.assertIn('now - lastDecode < 300',SCANNER)
        self.assertIn('FLAG_SECURE',SCANNER)
        for cleanup in ('session?.close()', 'camera?.close()', 'previewSurface?.release()', 'frames?.close()', 'thread.quitSafely()'):
            self.assertIn(cleanup,SCANNER)
        self.assertIn('if (closed) return\n        closed = true',SCANNER)

if __name__ == '__main__': unittest.main()
