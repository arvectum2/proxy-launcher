import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "build_linux_rpm.sh"


class LinuxRpmPackagingContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SCRIPT.read_text(encoding="utf-8")

    def test_package_identity_and_payload_are_canonical(self):
        self.assertIn('package="arvectum-proxy-launcher"', self.text)
        self.assertIn('/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher', self.text)
        self.assertIn('%{_bindir}/arvectum-proxy-launcher', self.text)
        self.assertIn('Requires:       NetworkManager', self.text)
        self.assertIn('Requires:       glib2', self.text)
        self.assertIn('Requires:       kf5-kconfig-core', self.text)
        self.assertIn('Requires:       dbus-tools', self.text)
        self.assertIn('redos-linux-${arch}.rpm', self.text)

    def test_package_has_no_privileged_network_or_lifecycle_scriptlets(self):
        for forbidden in ("%pre", "%post", "%preun", "%postun", "nmcli connection modify", "sudo ", "pkexec"):
            self.assertNotIn(forbidden, self.text)

    def test_user_state_is_not_packaged(self):
        for forbidden in (
            "proxy_settings.json",
            "linux_proxy_backup.json",
            ".config/autostart",
            "XDG_CONFIG_HOME",
            "XDG_STATE_HOME",
        ):
            self.assertNotIn(forbidden, self.text)

    def test_package_contains_desktop_icon_and_license_evidence(self):
        self.assertIn('arvectum-proxy-launcher.desktop', self.text)
        self.assertIn('arvectum-proxy-launcher.png', self.text)
        self.assertIn('THIRD_PARTY_NOTICES.txt', self.text)
        self.assertIn('THIRD_PARTY_LICENSES', self.text)
        self.assertIn('LICENSE', self.text)

    def test_reproducible_epoch_and_payload_inspection_are_explicit(self):
        self.assertIn('SOURCE_DATE_EPOCH', self.text)
        self.assertIn('rpm -qip', self.text)
        self.assertIn('rpm -qlp', self.text)
        self.assertIn('artifact="$(cd "$(dirname "$artifact")" && pwd)/$(basename "$artifact")"', self.text)


if __name__ == "__main__":
    unittest.main()
