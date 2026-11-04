"""iOS Files picker cancellations are silent; real access failures still surface."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHARED = (ROOT/"mobile/ios/SharedCore/ProxyFilePickerCancellation.swift").read_text()
UI = (ROOT/"mobile/ios/App/ProxyImportView.swift").read_text()


class FilesPickerCancelContract(unittest.TestCase):
    def test_domain_and_code_are_both_required(self):
        self.assertIn('ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError', SHARED)
        self.assertNotIn('error.localizedDescription', SHARED)

    def test_real_file_errors_still_report_safely(self):
        self.assertIn('if !ProxyFilePickerCancellation.isUserCancellation(error)', UI)
        self.assertIn('importError = ProxyImportUX.error(error)', UI)
        self.assertIn('ProxyImportFileReader.readUTF8(from: url)', UI)
        self.assertIn('url.startAccessingSecurityScopedResource()', UI)
        self.assertIn('url.stopAccessingSecurityScopedResource()', UI)

    def test_no_console_or_network_side_effects(self):
        executable = '\n'.join(l for l in SHARED.splitlines() if not l.lstrip().startswith('///'))
        for bad in ('print(', 'Logger(', 'os_log(', 'URLSession(', 'UIPasteboard',
                    'SecItem', 'Keychain', 'NetworkExtension'):
            self.assertNotIn(bad, executable)


if __name__ == '__main__':
    unittest.main()
