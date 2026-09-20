import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import process_supervision
import proxy_core as core


class ProcessSupervisionTests(unittest.TestCase):
    def test_listener_status_resolves_current_pac_probe_and_settings(self):
        settings = {"local_pac_port": 19082, "pac_path": "/live.pac"}
        with mock.patch.object(core, "load_settings", return_value=settings), \
             mock.patch.object(core, "_pac_healthy", return_value=True) as probe:
            self.assertTrue(core.proxy_listener_active())
        probe.assert_called_once_with(settings)

    def test_pid_reader_preserves_json_identity_fields(self):
        record = {
            "pid": 42,
            "created": 123,
            "exe_path": "C:/owned.exe",
            "identity": "C:/owned",
        }
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_core.pid"
            path.write_text(json.dumps(record), encoding="utf-8")
            with mock.patch.object(core, "pid_path", return_value=str(path)):
                self.assertEqual(core._read_pid(), record)

    def test_legacy_pid_only_record_remains_unverified(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_core.pid"
            path.write_text("4242", encoding="utf-8")
            with mock.patch.object(core, "pid_path", return_value=str(path)):
                self.assertEqual(core._read_pid(), {"pid": 4242, "created": None})

    def test_is_running_requires_listener_before_process_identity(self):
        with mock.patch.object(core, "proxy_listener_active", return_value=False), \
             mock.patch.object(core, "_read_pid") as read_pid:
            self.assertFalse(core.is_running())
        read_pid.assert_not_called()

    def test_is_running_rejects_windows_executable_path_mismatch(self):
        record = {"pid": 42, "created": 123, "exe_path": "C:/owned.exe"}
        with mock.patch.object(core, "proxy_listener_active", return_value=True), \
             mock.patch.object(core, "is_windows", return_value=True), \
             mock.patch.object(core, "_read_pid", return_value=record), \
             mock.patch.object(core, "_windows_process_creation_time", return_value=123), \
             mock.patch.object(core, "_windows_process_executable_path", return_value="C:/foreign.exe"):
            self.assertFalse(core.is_running())

    def test_is_running_rejects_foreign_macos_listener_without_owned_pid(self):
        with mock.patch.object(core, "proxy_listener_active", return_value=True), \
             mock.patch.object(core, "is_windows", return_value=False), \
             mock.patch.object(process_supervision.sys, "platform", "darwin"), \
             mock.patch.object(core, "_read_pid", return_value=None), \
             mock.patch.object(core, "_macos_process_executable_path") as path:
            self.assertFalse(core.is_running())
        path.assert_not_called()

    def test_is_running_accepts_owned_macos_pid_and_executable(self):
        record = {
            "pid": 42,
            "created": None,
            "exe_path": "/Applications/Arvectum Proxy Launcher.app/Contents/MacOS/Arvectum Proxy Launcher",
        }
        with mock.patch.object(core, "proxy_listener_active", return_value=True), \
             mock.patch.object(core, "is_windows", return_value=False), \
             mock.patch.object(process_supervision.sys, "platform", "darwin"), \
             mock.patch.object(core, "_read_pid", return_value=record), \
             mock.patch.object(
                 core,
                 "_macos_process_executable_path",
                 return_value=record["exe_path"],
             ):
            self.assertTrue(core.is_running())

    def test_macos_kill_refuses_pid_with_foreign_executable(self):
        record = {"pid": 77, "created": None, "exe_path": "/Applications/owned"}
        with mock.patch.object(core, "is_windows", return_value=False), \
             mock.patch.object(process_supervision.sys, "platform", "darwin"), \
             mock.patch.object(
                 core, "_macos_process_executable_path", return_value="/Applications/foreign"
             ), \
             mock.patch.object(process_supervision.os, "kill") as kill:
            self.assertFalse(core._kill_pid(record))
        kill.assert_not_called()

    def test_windows_kill_requires_matching_creation_time(self):
        completed = mock.Mock(returncode=0, stderr="", stdout="")
        with mock.patch.object(core, "is_windows", return_value=True), \
             mock.patch.object(core, "_windows_process_creation_time", return_value=123), \
             mock.patch.object(process_supervision.subprocess, "run", return_value=completed) as run:
            self.assertTrue(core._kill_pid({"pid": 9999, "created": 123}))
        run.assert_called_once()
        self.assertEqual(run.call_args.args[0], ["taskkill", "/PID", "9999", "/F"])

    def test_nonwindows_kill_preserves_sigkill_contract(self):
        with mock.patch.object(core, "is_windows", return_value=False), \
             mock.patch.object(process_supervision.sys, "platform", "linux"), \
             mock.patch.object(process_supervision.os, "kill") as kill:
            self.assertTrue(core._kill_pid({"pid": 77, "created": None}))
        kill.assert_called_once_with(77, 9)

    def test_pid_remove_uses_current_pid_path(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_core.pid"
            path.write_text("1", encoding="utf-8")
            with mock.patch.object(core, "pid_path", return_value=str(path)):
                core._remove_pid()
            self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main()