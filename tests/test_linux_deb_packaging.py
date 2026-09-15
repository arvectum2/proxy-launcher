import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "build_linux_deb.sh"


class LinuxDebPackagingContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SCRIPT.read_text(encoding="utf-8")

    def test_package_identity_and_payload_are_canonical(self):
        self.assertIn('package="arvectum-proxy-launcher"', self.text)
        self.assertIn('/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher', self.text)
        self.assertIn('/usr/bin/arvectum-proxy-launcher', self.text)
        self.assertIn('/usr/share/applications/arvectum-proxy-launcher.desktop', self.text)
        self.assertIn('network-manager', self.text)
        self.assertIn('libglib2.0-bin', self.text)

    def test_package_does_not_run_privileged_network_mutation_hooks(self):
        for forbidden in ("postinst", "prerm", "postrm"):
            self.assertNotIn(f'"$root/DEBIAN/{forbidden}"', self.text)
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

    def test_root_ownership_and_reproducible_epoch_are_explicit(self):
        self.assertIn("--root-owner-group", self.text)
        self.assertIn("SOURCE_DATE_EPOCH", self.text)


if __name__ == "__main__":
    unittest.main()
