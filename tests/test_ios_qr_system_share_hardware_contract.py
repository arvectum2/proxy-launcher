"""An independent QA app may attest Apple sheet presentation; never deliver or capture."""
from pathlib import Path
import unittest

root=Path(__file__).resolve().parents[1]
qa=root/"mobile/ios/HardwareQA/QRDeviceQA/App"
home=(qa/"QRDeviceQAApp.swift").read_text()
share=(qa/"QRSystemShareAttestation.swift").read_text()
spec=(qa.parent/"project.yml").read_text()

class ShareSheetAttestationContract(unittest.TestCase):
    def test_qa_is_opt_in_and_no_external_share(self):
        self.assertIn('"-aplQASystemShareAttestation"',home)
        self.assertIn('status.hasPrefix("PASS:")',home)
        self.assertIn('"external_share": "not_performed"',home)
        self.assertIn('"apple_activity_view": qaActivityObserved ? "presented"',home)
        self.assertIn('onPresented?()',share)
        self.assertIn('viewDidAppear(',share)
        self.assertIn("UIActivityViewController",share)
        self.assertIn('activityItems: [image, url.absoluteString]',share)
        self.assertIn('host: "share-qa.invalid"',share)

    def test_privacy_no_camera_capture_no_real_proxy(self):
        self.assertIn('AVCaptureDevice.authorizationStatus(for: .video)',home)
        self.assertIn('AVCaptureDevice.default(for: .video)',home)
        for forbidden in ('AVCaptureSession(', 'requestAccess(for:', 'startRunning(',
                          'URLSession(', 'SecItem', 'CNContactStore', 'UIPasteboard',
                          'ProfileStore(', 'NEPacketTunnelProvider', 'startVPNTunnel('):
            self.assertNotIn(forbidden, share)
            # The normal QA home has a user-tapped camera scanner view,
            # but not an automatic camera start in the new attestation flow.
            self.assertNotIn(forbidden, home)
        self.assertIn('ru.arvectum.qrdeviceqa.device',spec)
        self.assertNotIn('group.ru.arvectum.proxylauncher.ios',spec)

if __name__=='__main__': unittest.main()
