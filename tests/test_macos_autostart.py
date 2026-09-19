import os
import plistlib
import tempfile
import unittest
from pathlib import Path

from macos_autostart import LABEL, DEFAULT_EXECUTABLE, enable_autostart, disable_autostart, is_autostart_enabled

class MacOSAutostartTests(unittest.TestCase):
    def test_enable_is_per_user_atomic_plist(self):
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, "Library", "LaunchAgents", LABEL + ".plist")
            enable_autostart(path)
            self.assertTrue(is_autostart_enabled(path))
            # chmod permission bits are meaningful on macOS/POSIX. The broad Windows
            # regression suite still validates plist contents/ownership semantics,
            # while macOS CI enforces the real 0600 filesystem mode.
            if os.name != "nt":
                self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            with open(path, "rb") as stream:
                payload = plistlib.load(stream)
            self.assertEqual(payload["ProgramArguments"], [DEFAULT_EXECUTABLE])
            self.assertTrue(payload["RunAtLoad"])
            self.assertFalse(payload["KeepAlive"])

    def test_foreign_launchagent_is_neither_overwritten_nor_deleted(self):
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, LABEL + ".plist")
            original = b"<?xml version='1.0'?><plist><dict><key>Label</key><string>foreign</string></dict></plist>"
            Path(path).write_bytes(original)
            with self.assertRaises(RuntimeError):
                enable_autostart(path)
            self.assertFalse(disable_autostart(path))
            self.assertEqual(Path(path).read_bytes(), original)

    def test_disable_removes_only_owned_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, LABEL + ".plist")
            enable_autostart(path)
            self.assertTrue(disable_autostart(path))
            self.assertFalse(os.path.exists(path))
            self.assertFalse(disable_autostart(path))

if __name__ == '__main__': unittest.main()
