import pathlib
import tempfile
import unittest
from unittest import mock

import application_runtime
import proxy_core as core


class ApplicationRuntimeTests(unittest.TestCase):
    def test_functions_are_owned_by_canonical_module(self):
        for name in (
            "_ensure_local_files",
            "_cmd_start",
            "_cmd_stop",
            "_cmd_rollback",
            "_cmd_status",
            "main",
        ):
            self.assertEqual(getattr(core, name).__module__, "application_runtime")

    def test_bundled_defaults_copy_only_after_state_ready(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            bundled = root / "bundle"
            state = root / "state"
            bundled.mkdir()
            state.mkdir()
            (bundled / "no_proxy.txt").write_text("example.test\n", encoding="utf-8")
            (bundled / "proxy_settings.json").write_text("{}\n", encoding="utf-8")

            with mock.patch.object(core, "ensure_state_ready", return_value=True), \
                 mock.patch.object(core, "data_dir", return_value=str(state)), \
                 mock.patch.object(application_runtime.sys, "frozen", True, create=True), \
                 mock.patch.object(application_runtime.sys, "_MEIPASS", str(bundled), create=True):
                self.assertTrue(core._ensure_local_files())

            self.assertEqual(
                (state / "no_proxy.txt").read_text(encoding="utf-8"),
                "example.test\n",
            )
            self.assertEqual(
                (state / "proxy_settings.json").read_text(encoding="utf-8"),
                "{}\n",
            )

    def test_main_handoff_precedes_state_or_run_mutation(self):
        with mock.patch.object(application_runtime.sys, "argv", ["proxy_core.py", "--start"]), \
             mock.patch.object(core, "handoff_to_stable_copy", return_value=True) as handoff, \
             mock.patch.object(core, "_ensure_local_files") as bootstrap, \
             mock.patch.object(core, "repair_portable_run_entries") as repair, \
             mock.patch("builtins.print"):
            self.assertEqual(core.main(), 0)
        handoff.assert_called_once_with(["--start"])
        bootstrap.assert_not_called()
        repair.assert_not_called()

    def test_main_state_failure_blocks_run_entry_repair(self):
        with mock.patch.object(application_runtime.sys, "argv", ["proxy_core.py", "--status"]), \
             mock.patch.object(core, "handoff_to_stable_copy") as handoff, \
             mock.patch.object(core, "_ensure_local_files", return_value=False), \
             mock.patch.object(core, "repair_portable_run_entries") as repair, \
             mock.patch("builtins.print"):
            self.assertEqual(core.main(), 1)
        handoff.assert_not_called()
        repair.assert_not_called()

    def test_start_without_upstream_fails_before_process_or_network_mutation(self):
        settings = dict(core.DEFAULT_SETTINGS)
        settings["upstream"] = [{"host": "", "port": 8000, "username": "", "password": ""}]
        with mock.patch.object(core, "load_settings", return_value=settings), \
             mock.patch.object(core, "is_running") as running, \
             mock.patch.object(core, "ProxyCore") as proxy_core, \
             mock.patch.object(core, "enable_system_proxy") as enable, \
             mock.patch("builtins.print"):
            self.assertEqual(core._cmd_start(), 2)
        running.assert_not_called()
        proxy_core.assert_not_called()
        enable.assert_not_called()

    def test_start_enable_failure_stops_proxy_and_removes_pid(self):
        settings = dict(core.DEFAULT_SETTINGS)
        settings["upstream"] = [{"host": "proxy.test", "port": 8000, "username": "", "password": ""}]
        proxy = mock.Mock()
        proxy.start.return_value = (True, "OK")
        with mock.patch.object(core, "load_settings", return_value=settings), \
             mock.patch.object(core, "is_running", return_value=False), \
             mock.patch.object(core, "ProxyCore", return_value=proxy), \
             mock.patch.object(core, "_write_pid") as write_pid, \
             mock.patch.object(core, "enable_system_proxy", return_value=False), \
             mock.patch.object(core, "_remove_pid") as remove_pid, \
             mock.patch("builtins.print"):
            self.assertEqual(core._cmd_start(), 1)
        write_pid.assert_called_once_with()
        proxy.stop.assert_called_once_with()
        remove_pid.assert_called_once_with(application_runtime.os.getpid())

    def test_successful_start_always_stops_and_removes_pid_on_interrupt(self):
        settings = dict(core.DEFAULT_SETTINGS)
        settings["upstream"] = [{"host": "proxy.test", "port": 8000, "username": "", "password": ""}]
        stop_event = mock.Mock()
        stop_event.wait.side_effect = KeyboardInterrupt
        proxy = mock.Mock(_stop=stop_event)
        proxy.start.return_value = (True, "OK")
        with mock.patch.object(application_runtime.sys, "platform", "linux"), \
             mock.patch.object(core, "load_settings", return_value=settings), \
             mock.patch.object(core, "is_running", return_value=False), \
             mock.patch.object(core, "ProxyCore", return_value=proxy), \
             mock.patch.object(core, "_write_pid") as write_pid, \
             mock.patch.object(core, "enable_system_proxy", return_value=True), \
             mock.patch.object(core, "_remove_pid") as remove_pid, \
             mock.patch("builtins.print"):
            self.assertEqual(core._cmd_start(), 0)
        write_pid.assert_called_once_with()
        stop_event.wait.assert_called_once_with(3600)
        proxy.stop.assert_called_once_with()
        remove_pid.assert_called_once_with(application_runtime.os.getpid())

    def test_non_macos_proxy_loop_keeps_historical_wait_contract(self):
        stop_event = mock.Mock()
        stop_event.wait.side_effect = KeyboardInterrupt
        proxy = mock.Mock(_stop=stop_event)

        with mock.patch.object(application_runtime.sys, "platform", "linux"):
            with self.assertRaises(KeyboardInterrupt):
                core._run_proxy_loop(proxy)

        stop_event.wait.assert_called_once_with(3600)

    def test_stop_preflight_refusal_preserves_worker_and_network(self):
        with mock.patch.object(
                 core, "system_proxy_disable_preflight", return_value=False
             ) as preflight,              mock.patch.object(core, "_read_pid") as read_pid,              mock.patch.object(core, "_kill_pid") as kill,              mock.patch.object(core, "disable_system_proxy") as disable,              mock.patch("builtins.print"):
            self.assertEqual(core._cmd_stop(), 1)

        preflight.assert_called_once_with()
        read_pid.assert_not_called()
        kill.assert_not_called()
        disable.assert_not_called()

    def test_rollback_preflight_refusal_preserves_worker_and_network(self):
        with mock.patch.object(
                 core, "system_proxy_disable_preflight", return_value=False
             ) as preflight,              mock.patch.object(core, "_read_pid") as read_pid,              mock.patch.object(core, "_kill_pid") as kill,              mock.patch.object(core, "disable_system_proxy") as disable,              mock.patch("builtins.print"):
            self.assertEqual(core._cmd_rollback(), 1)

        preflight.assert_called_once_with()
        read_pid.assert_not_called()
        kill.assert_not_called()
        disable.assert_not_called()

    def test_stop_reports_incomplete_network_restore(self):
        with mock.patch.object(
                 core, "system_proxy_disable_preflight", return_value=True
             ),              mock.patch.object(core, "_read_pid", return_value=None), \
             mock.patch.object(core, "_kill_pid", return_value=False), \
             mock.patch.object(core, "is_running", return_value=False), \
             mock.patch.object(core, "_remove_pid") as remove_pid, \
             mock.patch.object(core, "disable_system_proxy", return_value=False), \
             mock.patch.object(core, "network_restore_pending", return_value=True), \
             mock.patch("builtins.print"):
            self.assertEqual(core._cmd_stop(), 1)
        remove_pid.assert_called_once_with()

    def test_stop_refreshes_recovered_pid_before_kill(self):
        recovered = {"pid": 42, "created": None, "exe_path": "/owned"}
        with mock.patch.object(
                 core, "system_proxy_disable_preflight", return_value=True
             ),              mock.patch.object(
                 core, "_read_pid", side_effect=[None, recovered]
             ), \
             mock.patch.object(core, "_kill_pid", return_value=True) as kill, \
             mock.patch.object(core, "is_running", side_effect=[True, False, False]), \
             mock.patch.object(core, "_remove_pid"), \
             mock.patch.object(core, "disable_system_proxy", return_value=True), \
             mock.patch.object(core, "network_restore_pending", return_value=False), \
             mock.patch("builtins.print"):
            self.assertEqual(core._cmd_stop(), 0)
        kill.assert_called_once_with(recovered)

    def test_rollback_reaches_network_restore_even_without_pid(self):
        with mock.patch.object(
                 core, "system_proxy_disable_preflight", return_value=True
             ),              mock.patch.object(core, "_read_pid", return_value=None), \
             mock.patch.object(core, "_kill_pid", return_value=False), \
             mock.patch.object(core, "is_running", return_value=False), \
             mock.patch.object(core, "_remove_pid") as remove_pid, \
             mock.patch.object(core, "disable_system_proxy", return_value=True) as disable, \
             mock.patch.object(core, "network_restore_pending", return_value=False), \
             mock.patch("builtins.print"):
            self.assertEqual(core._cmd_rollback(), 0)
        remove_pid.assert_called_once_with()
        disable.assert_called_once_with()

    def test_rollback_refreshes_recovered_pid_before_kill(self):
        recovered = {"pid": 42, "created": None, "exe_path": "/owned"}
        with mock.patch.object(
                 core, "system_proxy_disable_preflight", return_value=True
             ),              mock.patch.object(
                 core, "_read_pid", side_effect=[None, recovered]
             ), \
             mock.patch.object(core, "_kill_pid", return_value=True) as kill, \
             mock.patch.object(core, "is_running", side_effect=[True, False, False]), \
             mock.patch.object(core, "_remove_pid"), \
             mock.patch.object(core, "disable_system_proxy", return_value=True), \
             mock.patch.object(core, "network_restore_pending", return_value=False), \
             mock.patch("builtins.print"):
            self.assertEqual(core._cmd_rollback(), 0)
        kill.assert_called_once_with(recovered)

    def test_status_uses_canonical_runtime_seams(self):
        settings = dict(core.DEFAULT_SETTINGS)
        outputs = []
        with mock.patch.object(core, "load_settings", return_value=settings), \
             mock.patch.object(core, "is_running", return_value=True), \
             mock.patch.object(core, "pac_url", return_value="http://127.0.0.1:8082/proxy.pac"), \
             mock.patch.object(core, "system_proxy_enabled", return_value=True), \
             mock.patch.object(core, "load_no_proxy", return_value=["one.test", "two.test"]), \
             mock.patch("builtins.print", side_effect=outputs.append):
            core._cmd_status()
        self.assertIn("RUNNING", outputs[0])
        self.assertEqual(outputs[1], "system proxy: ENABLED")
        self.assertEqual(outputs[2], "exceptions: 2 domains")


if __name__ == "__main__":
    unittest.main()