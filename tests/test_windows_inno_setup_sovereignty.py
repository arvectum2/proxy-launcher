import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
LOCK = (ROOT / 'tools' / 'inno-setup-windows.lock').read_text(encoding='utf-8')
PREPARE = (ROOT / 'tools' / 'prepare_windows_inno_setup_base.ps1').read_text(encoding='utf-8')
INSTALL = (ROOT / 'tools' / 'install_verified_windows_inno_setup.ps1').read_text(encoding='utf-8')
BUILD = (ROOT / 'tools' / 'build_windows_installer.ps1').read_text(encoding='utf-8')
ISS = (ROOT / 'installer' / 'ArvectumProxyLauncher.iss').read_text(encoding='utf-8')


class WindowsInnoSetupSovereigntyTests(unittest.TestCase):
    def test_exact_inno_setup_release_is_locked(self):
        expected = (
            'INNO_VERSION=6.7.1',
            'INNO_RELEASE_TAG=is-6_7_1',
            'INNO_RELEASE_COMMIT_SHORT=cfdf489',
            'INNO_INSTALLER=innosetup-6.7.1.exe',
            'INNO_INSTALLER_SIZE=10619024',
            'INNO_INSTALLER_SHA256=4d11e8050b6185e0d49bd9e8cc661a7a59f44959a621d31d11033124c4e8a7b0',
            'INNO_AUTHENTICODE_PUBLISHER=Pyrsys B.V.',
            'INNO_PUBLIC_KEY_ID=def020edee3c4835fd54d85eff8b66d4d899b22a777353ca4a114b652e5e7a28',
        )
        for token in expected:
            self.assertIn(token, LOCK)
        self.assertRegex(LOCK, r'INNO_INSTALLER_URL=https://github\.com/jrsoftware/issrc/releases/download/is-6_7_1/')

    def test_connected_acquisition_is_hash_and_authenticode_verified(self):
        for token in (
            'inno-setup-windows.lock',
            'Invoke-WebRequest',
            'INNO_INSTALLER_SIZE',
            'INNO_INSTALLER_SHA256',
            'Get-FileHash',
            'Get-AuthenticodeSignature',
            "Status -ne 'Valid'",
            'INNO_AUTHENTICODE_PUBLISHER',
            'locked-sha256+authenticode-pass',
            'inno-setup-base-manifest.json',
            'The installer is never executed by this script.',
        ):
            self.assertIn(token, PREPARE)
        self.assertNotIn('Start-Process -FilePath $Installer', PREPARE)

    def test_controlled_bundle_includes_detached_vendor_evidence(self):
        for token in (
            'INNO_ISSIG_URL',
            'INNO_PUBLIC_KEY_URL',
            'INNO_PUBLIC_KEY_ID',
            'INNO_LICENSE_URL',
            'issig_sha256',
            'public_key_sha256',
            'license_sha256',
        ):
            self.assertIn(token, PREPARE)

    def test_offline_install_revalidates_immutable_bytes_and_native_compiler_version(self):
        for token in (
            'offline-from-controlled-copy',
            'installer_sha256',
            'installer_bytes',
            'Get-FileHash',
            'issig_sha256',
            'public_key_sha256',
            'license_sha256',
            '/PORTABLE=1',
            '/CURRENTUSER',
            'ISCC.exe',
            '#if Ver != 0x06070100',
            'ARVECTUM_INNO_VERSION_MISMATCH_EXPECTED_6_7_1',
            'Output=no',
            "ObservedVersion = '6.7.1'",
            "version_verification              = 'compiler-preprocessor-ver-0x06070100'",
            'upstream_access_used              = $false',
            'inno-setup-install-evidence.json',
        ):
            self.assertIn(token, INSTALL)
        self.assertNotIn('Invoke-WebRequest', INSTALL)
        self.assertNotIn('Invoke-RestMethod', INSTALL)
        self.assertNotIn('.VersionInfo.FileVersion', INSTALL)

    def test_canonical_installer_fails_closed_on_native_compiler_version(self):
        self.assertIn('#if Ver != 0x06070100', ISS)
        self.assertIn('#error Exact Inno Setup 6.7.1 is required', ISS)
        for token in (
            "requiredInnoSetupVersion = '6.7.1'",
            "inno_setup_version=$requiredInnoSetupVersion",
            "inno_setup_version_verification='compiler-preprocessor-ver-0x06070100'",
            'iscc_sha256=$isccHash',
            'Inno Setup $requiredInnoSetupVersion compiler contract PASS.',
        ):
            self.assertIn(token, BUILD)
        self.assertNotIn('.VersionInfo.FileVersion', BUILD)
        self.assertNotIn("requiredInnoSetupVersion = '6.7.2'", BUILD)
        self.assertIn('$env:LOCALAPPDATA\\Programs\\Inno Setup 6\\ISCC.exe', BUILD)

    def test_locked_hash_is_single_sha256(self):
        matches = re.findall(r'^INNO_INSTALLER_SHA256=([0-9a-f]{64})$', LOCK, re.MULTILINE)
        self.assertEqual(matches, ['4d11e8050b6185e0d49bd9e8cc661a7a59f44959a621d31d11033124c4e8a7b0'])


if __name__ == '__main__':
    unittest.main()
