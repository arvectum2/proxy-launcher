import unittest
from types import SimpleNamespace

from linux_runtime import (
    LinuxRuntimeDetectionError,
    detect_linux_runtime,
    parse_os_release,
)


ASTRA_RELEASE = '''
PRETTY_NAME="Astra Linux"
NAME="Astra Linux"
ID=astra
ID_LIKE=debian
VERSION_ID=1.8_x86-64
VERSION_CODENAME=1.8_x86-64
'''

REDOS_RELEASE = '''
PRETTY_NAME="RED OS 8.0.3 (Standard Desktop)"
NAME="RED OS"
ID=redos
ID_LIKE="rhel centos fedora"
VERSION_ID="8.0.3"
EDITION="Standard"
'''

DEBIAN_RELEASE = '''
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
ID=debian
VERSION_ID="12"
VERSION_CODENAME=bookworm
'''


class LinuxRuntimeDetectionTests(unittest.TestCase):
    def _reader(self, files):
        def read(path):
            if path not in files:
                raise FileNotFoundError(path)
            return files[path]
        return read

    def _uname(self):
        return SimpleNamespace(release="6.1.0-test", machine="x86_64")

    def test_parse_os_release_handles_quotes_comments_and_safe_keys(self):
        parsed = parse_os_release('ID=astra\nPRETTY_NAME="Astra Linux"\n# x\nBAD-KEY=x\n')
        self.assertEqual(parsed["ID"], "astra")
        self.assertEqual(parsed["PRETTY_NAME"], "Astra Linux")
        self.assertNotIn("BAD-KEY", parsed)

    def test_astra_detected_from_official_os_release_marker(self):
        runtime = detect_linux_runtime(
            platform_name="linux",
            environ={"XDG_CURRENT_DESKTOP": "FLY", "XDG_SESSION_TYPE": "x11"},
            which=lambda name: "/usr/bin/nmcli" if name == "nmcli" else None,
            uname=self._uname,
            read_text=self._reader({"/etc/os-release": ASTRA_RELEASE}),
        )
        self.assertTrue(runtime.is_astra)
        self.assertFalse(runtime.is_redos)
        self.assertTrue(runtime.is_debian_family)
        self.assertEqual(runtime.runtime_id, "astra")
        self.assertEqual(runtime.platform_label, "Linux / Astra Linux")
        self.assertEqual(runtime.version_id, "1.8_x86-64")
        self.assertEqual(runtime.desktop_environment, "FLY")
        self.assertEqual(runtime.session_type, "x11")
        self.assertTrue(runtime.network_manager_client_available)
        self.assertEqual(runtime.nmcli_path, "/usr/bin/nmcli")


    def test_redos_detected_with_distinct_product_signature(self):
        runtime = detect_linux_runtime(
            platform_name="linux",
            environ={"XDG_CURRENT_DESKTOP": "KDE", "XDG_SESSION_TYPE": "x11"},
            which=lambda name: "/usr/bin/nmcli" if name == "nmcli" else None,
            uname=self._uname,
            read_text=self._reader({"/etc/os-release": REDOS_RELEASE}),
        )
        self.assertFalse(runtime.is_astra)
        self.assertTrue(runtime.is_redos)
        self.assertFalse(runtime.is_debian_family)
        self.assertEqual(runtime.runtime_id, "redos")
        self.assertEqual(runtime.platform_label, "Linux / RED OS")
        self.assertEqual(runtime.version_id, "8.0.3")
        self.assertEqual(runtime.desktop_environment, "KDE")

    def test_astra_version_file_is_supported_as_legacy_specific_marker(self):
        runtime = detect_linux_runtime(
            platform_name="linux2",
            environ={},
            which=lambda name: None,
            uname=self._uname,
            read_text=self._reader({
                "/etc/os-release": "ID=debian\nNAME=Linux\n",
                "/etc/astra_version": "1.7.6\n",
            }),
        )
        self.assertTrue(runtime.is_astra)
        self.assertEqual(runtime.astra_version, "1.7.6")
        self.assertEqual(runtime.runtime_id, "astra")
        self.assertFalse(runtime.network_manager_client_available)

    def test_debian_is_not_misclassified_as_astra(self):
        runtime = detect_linux_runtime(
            platform_name="linux",
            environ={"DESKTOP_SESSION": "gnome"},
            which=lambda name: "/bin/nmcli",
            uname=self._uname,
            read_text=self._reader({"/etc/os-release": DEBIAN_RELEASE}),
        )
        self.assertFalse(runtime.is_astra)
        self.assertFalse(runtime.is_redos)
        self.assertTrue(runtime.is_debian_family)
        self.assertEqual(runtime.runtime_id, "debian")
        self.assertEqual(runtime.platform_label, "Linux")
        self.assertEqual(runtime.desktop_environment, "gnome")

    def test_id_like_marks_debian_family(self):
        runtime = detect_linux_runtime(
            platform_name="linux",
            environ={},
            which=lambda name: None,
            uname=self._uname,
            read_text=self._reader({
                "/etc/os-release": "ID=ubuntu\nID_LIKE=debian\nNAME=Ubuntu\n"
            }),
        )
        self.assertFalse(runtime.is_astra)
        self.assertTrue(runtime.is_debian_family)
        self.assertEqual(runtime.id_like, ("debian",))

    def test_usr_lib_os_release_is_fallback(self):
        runtime = detect_linux_runtime(
            platform_name="linux",
            environ={},
            which=lambda name: None,
            uname=self._uname,
            read_text=self._reader({"/usr/lib/os-release": "ID=fedora\nNAME=Fedora Linux\n"}),
        )
        self.assertEqual(runtime.distro_id, "fedora")
        self.assertEqual(runtime.runtime_id, "fedora")
        self.assertFalse(runtime.is_debian_family)

    def test_missing_release_files_degrade_to_generic_linux(self):
        runtime = detect_linux_runtime(
            platform_name="linux",
            environ={},
            which=lambda name: None,
            uname=self._uname,
            read_text=self._reader({}),
        )
        self.assertEqual(runtime.runtime_id, "linux")
        self.assertFalse(runtime.is_astra)
        self.assertEqual(runtime.kernel_release, "6.1.0-test")
        self.assertEqual(runtime.architecture, "x86_64")

    def test_non_linux_host_fails_closed(self):
        with self.assertRaises(LinuxRuntimeDetectionError):
            detect_linux_runtime(platform_name="darwin")


if __name__ == "__main__":
    unittest.main()
