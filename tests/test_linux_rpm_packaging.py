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
        self.assertIn('/usr/bin/arvectum-proxy-launcher', self.text)
        self.assertIn('/usr/share/applications/arvectum-proxy-launcher.desktop', self.text)
        self.assertIn('Requires:       NetworkManager', self.text)

    def test_package_does_not_ship_privileged_lifecycle_scriptlets(self):
        for forbidden in ("%pre\n", "%post\n", "%preun\n", "%postun\n", "%trigger"):
            self.assertNotIn(forbidden, self.text)
        self.assertNotIn("nmcli connection modify", self.text)
        self.assertNotIn("sudo ", self.text)
        self.assertNotIn("pkexec", self.text)

    def test_user_state_is_not_packaged(self):
        for forbidden in (
            "proxy_settings.json",
            "linux_proxy_backup.json",
            ".config/autostart",
            "XDG_CONFIG_HOME",
            "XDG_STATE_HOME",
        ):
            self.assertNotIn(forbidden, self.text)

    def test_package_contains_license_and_third_party_notices(self):
        self.assertIn("LICENSE", self.text)
        self.assertIn("THIRD_PARTY_NOTICES.txt", self.text)
        self.assertIn("THIRD_PARTY_LICENSES", self.text)

    def test_reproducible_payload_metadata_is_explicit(self):
        self.assertIn("SOURCE_DATE_EPOCH", self.text)
        self.assertIn("--sort=name", self.text)
        self.assertIn("--owner=0 --group=0 --numeric-owner", self.text)
        self.assertIn("_buildhost arvectum-reproducible", self.text)
        self.assertIn("%global __os_install_post %{nil}", self.text)
        self.assertIn('"/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher"', self.text)

    def test_red_os_acceptance_package_is_explicitly_x86_64(self):
        self.assertIn('[[ "$arch" == "x86_64" ]]', self.text)


if __name__ == "__main__":
    unittest.main()
