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
        self.assertIn('Requires:       glib2', self.text)

    def test_package_does_not_claim_global_build_id_links(self):
        self.assertIn("%global _build_id_links none", self.text)

    def test_package_has_no_privileged_lifecycle_network_hooks(self):
        for forbidden in ("%post", "%pre", "%preun", "%postun"):
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

    def test_license_and_third_party_notices_are_included(self):
        self.assertIn("LICENSE", self.text)
        self.assertIn("THIRD_PARTY_NOTICES.txt", self.text)
        self.assertIn("THIRD_PARTY_LICENSES", self.text)

    def test_redos_release_and_architecture_are_explicit(self):
        self.assertIn("Release:        1.redos8", self.text)
        self.assertIn('[[ "$arch" == "x86_64" ]]', self.text)
        self.assertIn("SOURCE_DATE_EPOCH", self.text)
        self.assertIn("_buildhost redos-build", self.text)


if __name__ == "__main__":
    unittest.main()
