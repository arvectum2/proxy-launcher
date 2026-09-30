import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import linux_autostart as autostart


class LinuxAutostartTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "home"
        self.home.mkdir()
        self.executable = Path(self.temp.name) / autostart.EXPECTED_EXECUTABLE_NAME
        self.executable.write_bytes(b"binary")
        self.executable.chmod(0o755)
        self.env = {"HOME": str(self.home)}

    def status(self):
        return autostart.status(
            str(self.executable), True, environ=self.env, home=str(self.home)
        )

    def enable(self):
        return autostart.enable(
            str(self.executable), True, environ=self.env, home=str(self.home)
        )

    def disable(self):
        return autostart.disable(
            str(self.executable), True, environ=self.env, home=str(self.home)
        )

    def test_source_checkout_cannot_register_autostart(self):
        with self.assertRaises(autostart.LinuxAutostartError):
            autostart.canonical_executable(str(self.executable), frozen=False)

    def test_wrong_executable_name_is_rejected(self):
        wrong = self.executable.with_name("proxy-launcher")
        wrong.write_bytes(b"binary")
        wrong.chmod(0o755)
        with self.assertRaises(autostart.LinuxAutostartError):
            autostart.canonical_executable(str(wrong), frozen=True)

    def test_xdg_config_home_is_used_only_when_absolute(self):
        absolute = Path(self.temp.name) / "xdg"
        path = autostart.autostart_path(
            environ={"HOME": str(self.home), "XDG_CONFIG_HOME": str(absolute)}
        )
        self.assertEqual(path.parent, absolute / "autostart")
        fallback = autostart.autostart_path(
            environ={"HOME": str(self.home), "XDG_CONFIG_HOME": "relative"}
        )
        self.assertEqual(fallback.parent, self.home / ".config" / "autostart")

    def test_enable_creates_exact_owned_entry_and_verifies_state(self):
        result = self.enable()
        path = Path(result.path)
        self.assertTrue(result.enabled)
        self.assertTrue(result.managed)
        self.assertFalse(result.conflict)
        self.assertEqual(
            path.read_text(encoding="utf-8"),
            autostart.render_autostart_entry(str(self.executable.resolve())),
        )
        if os.name == "posix":
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertTrue(self.status().enabled)

    def test_enable_is_idempotent_for_exact_owned_entry(self):
        first = self.enable()
        before = Path(first.path).read_bytes()
        second = self.enable()
        self.assertTrue(second.enabled)
        self.assertEqual(Path(second.path).read_bytes(), before)

    def test_foreign_same_named_entry_is_never_overwritten(self):
        path = autostart.autostart_path(environ=self.env, home=str(self.home))
        path.parent.mkdir(parents=True)
        foreign = "[Desktop Entry]\nType=Application\nExec=/usr/bin/foreign\n"
        path.write_text(foreign, encoding="utf-8")
        with self.assertRaises(autostart.LinuxAutostartError):
            self.enable()
        self.assertEqual(path.read_text(encoding="utf-8"), foreign)
        self.assertTrue(self.status().conflict)

    def test_foreign_same_named_entry_is_never_deleted(self):
        path = autostart.autostart_path(environ=self.env, home=str(self.home))
        path.parent.mkdir(parents=True)
        foreign = "[Desktop Entry]\nType=Application\nExec=/usr/bin/foreign\n"
        path.write_text(foreign, encoding="utf-8")
        with self.assertRaises(autostart.LinuxAutostartError):
            self.disable()
        self.assertEqual(path.read_text(encoding="utf-8"), foreign)

    def test_symlink_entry_is_rejected_without_touching_target(self):
        target = Path(self.temp.name) / "foreign.desktop"
        target.write_text("foreign", encoding="utf-8")
        path = autostart.autostart_path(environ=self.env, home=str(self.home))
        path.parent.mkdir(parents=True)
        try:
            path.symlink_to(target)
        except OSError as exc:
            if os.name == "nt" and getattr(exc, "winerror", None) == 1314:
                self.skipTest("Windows process is not allowed to create symlinks")
            raise
        with self.assertRaises(autostart.LinuxAutostartError):
            self.enable()
        self.assertEqual(target.read_text(encoding="utf-8"), "foreign")

    def test_disable_removes_only_exact_owned_entry_and_verifies_absence(self):
        enabled = self.enable()
        path = Path(enabled.path)
        result = self.disable()
        self.assertFalse(result.enabled)
        self.assertTrue(result.managed)
        self.assertFalse(path.exists())

    def test_write_verification_failure_is_reported(self):
        expected = autostart.render_autostart_entry(str(self.executable.resolve()))
        original = autostart._read_regular_file
        calls = {"count": 0}

        def fake_read(path):
            calls["count"] += 1
            value = original(path)
            if calls["count"] >= 2 and value == expected:
                return expected + "tampered\n"
            return value

        with mock.patch.object(autostart, "_read_regular_file", side_effect=fake_read):
            with self.assertRaises(autostart.LinuxAutostartError):
                self.enable()

    def test_exec_path_with_spaces_is_quoted(self):
        entry = autostart.render_autostart_entry("/opt/Arvectum Proxy Launcher")
        self.assertIn('Exec="/opt/Arvectum Proxy Launcher" --start', entry)
        self.assertIn(autostart.OWNERSHIP_MARKER, entry)


if __name__ == "__main__":
    unittest.main()
