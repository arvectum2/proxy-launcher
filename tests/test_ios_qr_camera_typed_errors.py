"""Source and locale safety contract for iOS QR camera failures."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CAMERA = (ROOT / "mobile/ios/App/ProxyQRScanner.swift").read_text()
IMPORT = (ROOT / "mobile/ios/App/ProxyImportView.swift").read_text()
LOCALES = sorted((ROOT / "mobile/ios/Resources").glob("*.lproj/ProxyImport.strings"))
CASES = {
    "permissionDenied": "Нет доступа к камере",
    "cameraUnavailable": "Камера недоступна",
    "inputUnavailable": "Не удалось открыть камеру",
    "outputUnavailable": "Не удалось запустить сканирование",
    "startFailed": "Не удалось запустить сканирование",
}


class QRScannerTypedErrorsContract(unittest.TestCase):
    def test_failure_is_typed_not_stringly_coupled(self):
        self.assertIn("enum ProxyQRScannerFailure: Equatable", CAMERA)
        self.assertIn("let onError: (ProxyQRScannerFailure) -> Void", CAMERA)
        self.assertIn("cameraPermissionDenied = failure.needsCameraSettings", IMPORT)
        self.assertIn("ProxyImportUX.text(failure.localizationKey)", IMPORT)
        self.assertNotIn('message == "Нет доступа к камере"', IMPORT)
        self.assertNotIn("error.localizedDescription", CAMERA)

    def test_every_failure_maps_to_existing_stable_key(self):
        for failure, key in CASES.items():
            self.assertRegex(
                CAMERA,
                rf"case \.{failure}(?::|,)\s*return \"{re.escape(key)}\"",
                failure,
            )

    def test_camera_settings_only_for_permission_denied(self):
        self.assertIn("var needsCameraSettings: Bool { self == .permissionDenied }", CAMERA)
        self.assertIn("if cameraPermissionDenied", IMPORT)
        self.assertIn("UIApplication.openSettingsURLString", IMPORT)
        self.assertIn("fail(.permissionDenied)", CAMERA)
        self.assertNotIn('onError("', CAMERA)

    def test_no_silent_start_failure_or_callback_after_dismissal(self):
        self.assertIn("let running = capture.isRunning", CAMERA)
        self.assertIn("else { self.fail(.startFailed) }", CAMERA)
        self.assertIn("guard !self.finished else { return }", CAMERA)
        self.assertIn("guard !finished else { return }", CAMERA)
        self.assertIn("capture.stopRunning()", CAMERA)
        self.assertIn("capture.startRunning()", CAMERA)

    def test_all_64_catalogs_contain_each_camera_error_translation(self):
        self.assertEqual(len(LOCALES), 64)
        for file in LOCALES:
            body = file.read_text()
            for key in set(CASES.values()):
                with self.subTest(locale=file.parent.name, key=key):
                    self.assertIn('"' + key + '" = ', body)

    def test_does_not_log_user_qr_secrets_or_expose_av_error_details(self):
        self.assertNotIn("print(", CAMERA)
        self.assertNotIn("Logger(", CAMERA)
        self.assertNotIn("os_log(", CAMERA)
        self.assertNotIn("localizedDescription", CAMERA)
        self.assertNotRegex(CAMERA, r"onError\(\s*error\s*\)")
        # Camera callback must retain original parsed-QR-only handoff.
        self.assertIn("onCode(code)", CAMERA)
        self.assertIn("ProxyProfileSharing.scannedSource(code)", IMPORT)


if __name__ == "__main__":
    unittest.main()
