import unittest
from unittest import mock

import proxy_gui as gui


class _BoolVar:
    def __init__(self, value):
        self.value = value

    def get(self):
        return self.value

    def set(self, value):
        self.value = value


class _Entry:
    def __init__(self, value=""):
        self.value = str(value)

    def get(self):
        return self.value

    def delete(self, *_args):
        self.value = ""

    def insert(self, _index, value):
        self.value = str(value)


class SettingsLocalPortsTests(unittest.TestCase):
    def dialog(self, http=8080, socks=1080, pac=8082):
        dlg = gui.SettingsDialog.__new__(gui.SettingsDialog)
        dlg._local_port_fields = {
            "local_http_port": _Entry(http),
            "local_socks_port": _Entry(socks),
            "local_pac_port": _Entry(pac),
        }
        return dlg

    def test_local_ports_accept_three_distinct_valid_values(self):
        values, error = self.dialog(18080, 11080, 18082)._local_ports_values()
        self.assertEqual(error, "")
        self.assertEqual(values, {
            "local_http_port": 18080,
            "local_socks_port": 11080,
            "local_pac_port": 18082,
        })

    def test_local_ports_reject_collision_and_invalid_values(self):
        values, error = self.dialog(8080, 8080, 8082)._local_ports_values()
        self.assertIsNone(values)
        self.assertIn("три разных", error)
        values, error = self.dialog("bad", 1080, 8082)._local_ports_values()
        self.assertIsNone(values)
        self.assertIn("1 до 65535", error)

    def test_macos_recommended_ports_can_be_applied_without_network_change(self):
        dlg = self.dialog()
        dlg._set_recommended_local_ports()
        self.assertEqual(dlg._local_port_fields["local_http_port"].get(), "18080")
        self.assertEqual(dlg._local_port_fields["local_socks_port"].get(), "11080")
        self.assertEqual(dlg._local_port_fields["local_pac_port"].get(), "18082")


class AutostartOwnershipTests(unittest.TestCase):
    def test_portable_fallback_detects_noncanonical_frozen_executable(self):
        with mock.patch.object(gui.os, "name", "nt"), \
             mock.patch.object(gui.sys, "frozen", True, create=True), \
             mock.patch.object(gui.sys, "executable", r"C:\Users\Test\Downloads\Arvectum Proxy Launcher.exe"), \
             mock.patch.object(gui.core, "stable_app_exe",
                               return_value=r"C:\Users\Test\Documents\ArvectumProxyLauncher\Arvectum Proxy Launcher.exe"):
            self.assertTrue(gui._portable_fallback_active())

    def test_canonical_frozen_executable_is_not_portable_fallback(self):
        canonical = r"C:\Users\Test\Documents\ArvectumProxyLauncher\Arvectum Proxy Launcher.exe"
        with mock.patch.object(gui.os, "name", "nt"), \
             mock.patch.object(gui.sys, "frozen", True, create=True), \
             mock.patch.object(gui.sys, "executable", canonical), \
             mock.patch.object(gui.core, "stable_app_exe", return_value=canonical):
            self.assertFalse(gui._portable_fallback_active())

    def test_autostart_enable_is_refused_in_portable_fallback(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.auto_var = _BoolVar(True)
        with mock.patch.object(gui, "_is_macos", return_value=False), \
             mock.patch.object(gui.core, "load_settings",
                               return_value={"upstream": [{"host": "test.invalid"}]}), \
             mock.patch.object(gui, "_portable_fallback_active", return_value=True), \
             mock.patch.object(gui.messagebox, "showwarning") as warning:
            self.assertFalse(launcher._enable_autostart())
        self.assertFalse(launcher.auto_var.get())
        warning.assert_called_once()

    def test_macos_autostart_enable_uses_launchagent_not_windows_copy(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.auto_var = _BoolVar(True)
        module = mock.Mock()
        module.enable_autostart.return_value = "/tmp/ru.arvectum.proxylauncher.plist"
        module.is_autostart_enabled.return_value = True
        with mock.patch.object(gui, "_is_macos", return_value=True), \
             mock.patch.object(gui, "macos_autostart_module", module), \
             mock.patch.object(gui, "_portable_fallback_active") as portable, \
             mock.patch.object(gui.messagebox, "showinfo") as info:
            self.assertTrue(launcher._enable_autostart())
        module.enable_autostart.assert_called_once_with()
        portable.assert_not_called()
        info.assert_called_once()

    def test_macos_autostart_state_reads_launchagent(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        module = mock.Mock()
        module.is_autostart_enabled.return_value = True
        with mock.patch.object(gui, "_is_macos", return_value=True), \
             mock.patch.object(gui, "macos_autostart_module", module):
            self.assertTrue(launcher._autostart_enabled())
        module.is_autostart_enabled.assert_called_once_with()

    def test_foreign_task_conflict_resets_checkbox(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.auto_var = _BoolVar(True)
        launcher._autostart_run_value = mock.Mock(return_value=None)
        launcher._autostart_run_is_ours = mock.Mock(return_value=False)
        launcher._autostart_task_xml = mock.Mock(return_value="foreign task xml")
        launcher._autostart_task_is_ours = mock.Mock(return_value=False)

        with mock.patch.object(gui, "_is_macos", return_value=False), \
             mock.patch.object(gui.core, "load_settings", return_value={"upstream": [{"host": "test.invalid"}]}), \
             mock.patch.object(gui.messagebox, "showerror"):
            launcher._toggle_autostart()

        self.assertFalse(launcher.auto_var.get())

    def test_autostart_prefers_owned_per_user_run_value(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher._autostart_run_is_ours = mock.Mock(return_value=True)
        launcher._autostart_task_is_ours = mock.Mock(return_value=False)

        with mock.patch.object(gui, "_is_macos", return_value=False):
            self.assertTrue(launcher._autostart_enabled())
        launcher._autostart_task_is_ours.assert_not_called()


class FocusStatusReconciliationTests(unittest.TestCase):
    def test_focus_reconciles_external_worker_state(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.refresh_status = mock.Mock()
        launcher._refresh_status_on_focus()
        launcher.refresh_status.assert_called_once_with()


class MacOSRecoveryDebounceTests(unittest.TestCase):
    def test_macos_recovery_prompt_rechecks_before_offering_rollback(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher._recovery_prompt_shown = False
        launcher.root = mock.Mock()

        with mock.patch.object(gui, "_is_macos", return_value=True),              mock.patch.object(gui.core, "is_running", return_value=False),              mock.patch.object(gui.core, "network_restore_pending", return_value=True),              mock.patch.object(gui.messagebox, "askyesno") as ask:
            launcher._maybe_prompt_recovery()

        ask.assert_not_called()
        launcher.root.after.assert_called_once()
        delay, callback = launcher.root.after.call_args.args
        self.assertEqual(delay, 750)
        self.assertTrue(callable(callback))

    def test_macos_recovery_prompt_still_available_after_stable_rechecks(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher._recovery_prompt_shown = False
        launcher.root = mock.Mock()

        with mock.patch.object(gui, "_is_macos", return_value=True),              mock.patch.object(gui.core, "is_running", return_value=False),              mock.patch.object(gui.core, "network_restore_pending", return_value=True),              mock.patch.object(gui.messagebox, "askyesno", return_value=False) as ask:
            launcher._maybe_prompt_recovery(attempt=3)

        ask.assert_called_once()
        self.assertTrue(launcher._recovery_prompt_shown)

    def test_headless_lifecycle_spawn_is_structured_logged(self):
        process = mock.Mock()
        with mock.patch.object(gui.sys, "frozen", True, create=True),              mock.patch.object(gui.sys, "executable", "/Applications/Arvectum Proxy Launcher"),              mock.patch.object(gui.core, "structured_log") as log,              mock.patch.object(gui.subprocess, "Popen", return_value=process) as popen:
            gui._run_headless("--rollback")

        self.assertEqual(log.call_args.kwargs["event"], "proxy_gui.lifecycle.spawn")
        self.assertEqual(log.call_args.kwargs["mode"], "--rollback")
        self.assertEqual(popen.call_args.args[0], [
            "/Applications/Arvectum Proxy Launcher",
            "--rollback",
        ])


class MacOSWakeDestructiveActionGuardTests(unittest.TestCase):
    def test_long_event_loop_gap_arms_wake_guard(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.root = mock.Mock()
        launcher._mac_ui = True
        launcher._ui_heartbeat_wall = 100.0
        launcher._mac_wake_guard_until = 0.0
        launcher.refresh_status = mock.Mock()

        with mock.patch.object(gui.time, "time", return_value=200.0),              mock.patch.object(gui.core, "structured_log") as log:
            launcher._ui_heartbeat()

        self.assertEqual(launcher._ui_heartbeat_wall, 200.0)
        self.assertEqual(
            launcher._mac_wake_guard_until,
            200.0 + gui.MAC_WAKE_GUARD_WINDOW_SECONDS,
        )
        self.assertEqual(log.call_args.kwargs["event"], "proxy_gui.wake_guard.armed")
        launcher.refresh_status.assert_called_once_with()
        launcher.root.after.assert_called_once_with(
            gui.MAC_WAKE_GUARD_HEARTBEAT_MS,
            launcher._ui_heartbeat,
        )

    def test_off_self_arms_guard_from_stale_heartbeat_before_spawning_stop(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.root = mock.Mock()
        launcher._mac_ui = True
        launcher._ui_heartbeat_wall = 100.0
        launcher._mac_wake_guard_until = 0.0
        launcher.refresh_status = mock.Mock()

        with mock.patch.object(gui.time, "time", return_value=200.0),              mock.patch.object(gui.core, "structured_log") as log,              mock.patch.object(gui, "_run_headless") as run:
            launcher.off()

        run.assert_not_called()
        events = [call.kwargs["event"] for call in log.call_args_list]
        self.assertEqual(
            events,
            ["proxy_gui.wake_guard.armed", "proxy_gui.wake_guard.blocked"],
        )
        self.assertEqual(log.call_args_list[0].kwargs["source"], "destructive_action")
        self.assertEqual(log.call_args_list[1].kwargs["action"], "off")
        self.assertEqual(
            launcher._mac_wake_guard_until,
            200.0 + gui.MAC_WAKE_GUARD_WINDOW_SECONDS,
        )

    def test_off_is_blocked_during_wake_guard_without_spawning_stop(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.root = mock.Mock()
        launcher._mac_ui = True
        launcher._ui_heartbeat_wall = 104.5
        launcher._mac_wake_guard_until = 115.0
        launcher.refresh_status = mock.Mock()

        with mock.patch.object(gui.time, "time", return_value=105.0),              mock.patch.object(gui.core, "structured_log") as log,              mock.patch.object(gui, "_run_headless") as run:
            launcher.off()

        run.assert_not_called()
        self.assertEqual(log.call_args.kwargs["event"], "proxy_gui.wake_guard.blocked")
        self.assertEqual(log.call_args.kwargs["action"], "off")
        launcher.refresh_status.assert_called_once_with()
        launcher.root.after.assert_called_once()

    def test_macos_off_defers_confirmation_until_original_click_finishes(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.root = mock.Mock()
        launcher.btn_off = mock.Mock()
        launcher._mac_ui = True
        launcher._ui_heartbeat_wall = 100.5
        launcher._mac_wake_guard_until = 100.0
        launcher._off_confirmation_pending = False

        with mock.patch.object(gui.time, "time", return_value=101.0),              mock.patch.object(gui.messagebox, "askyesno") as ask,              mock.patch.object(gui, "_run_headless") as run:
            launcher.off()

        ask.assert_not_called()
        run.assert_not_called()
        self.assertTrue(launcher._off_confirmation_pending)
        launcher.btn_off.state.assert_called_once_with(["disabled"])
        launcher.root.after.assert_called_once_with(
            gui.MAC_OFF_CONFIRM_DELAY_MS,
            launcher._confirm_macos_off,
        )

    def test_macos_off_cancel_after_delay_never_spawns_stop(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.root = mock.Mock()
        launcher._mac_ui = True
        launcher._ui_heartbeat_wall = 100.5
        launcher._mac_wake_guard_until = 100.0
        launcher._off_confirmation_pending = True
        launcher.refresh_status = mock.Mock()

        with mock.patch.object(gui.time, "time", return_value=101.0),              mock.patch.object(gui.messagebox, "askyesno", return_value=False) as ask,              mock.patch.object(gui.core, "structured_log") as log,              mock.patch.object(gui, "_run_headless") as run:
            launcher._confirm_macos_off()

        ask.assert_called_once()
        self.assertEqual(ask.call_args.kwargs["default"], "no")
        run.assert_not_called()
        launcher.refresh_status.assert_called_once_with()
        self.assertEqual(log.call_args.kwargs["event"], "proxy_gui.off.cancelled")

    def test_macos_off_confirm_after_delay_spawns_stop(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.root = mock.Mock()
        launcher._mac_ui = True
        launcher._ui_heartbeat_wall = 100.5
        launcher._mac_wake_guard_until = 100.0
        launcher._off_confirmation_pending = True
        launcher._set_busy = mock.Mock()

        with mock.patch.object(gui.time, "time", return_value=101.0),              mock.patch.object(gui.messagebox, "askyesno", return_value=True) as ask,              mock.patch.object(gui.core, "structured_log") as log,              mock.patch.object(gui, "_run_headless") as run:
            launcher._confirm_macos_off()

        ask.assert_called_once()
        self.assertEqual(ask.call_args.kwargs["default"], "no")
        launcher._set_busy.assert_called_once()
        run.assert_called_once_with("--stop")
        launcher.root.after.assert_called_once_with(250, launcher._after_stop)
        self.assertEqual(log.call_args.kwargs["event"], "proxy_gui.off.confirmed")

    def test_duplicate_macos_off_request_is_ignored_while_confirmation_pending(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.root = mock.Mock()
        launcher.btn_off = mock.Mock()
        launcher._mac_ui = True
        launcher._ui_heartbeat_wall = 100.5
        launcher._mac_wake_guard_until = 100.0
        launcher._off_confirmation_pending = True

        with mock.patch.object(gui.time, "time", return_value=101.0),              mock.patch.object(gui.messagebox, "askyesno") as ask,              mock.patch.object(gui, "_run_headless") as run:
            launcher.off()

        ask.assert_not_called()
        run.assert_not_called()
        launcher.root.after.assert_not_called()

    def test_rollback_is_blocked_during_wake_guard(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.root = mock.Mock()
        launcher._mac_ui = True
        launcher._ui_heartbeat_wall = 104.5
        launcher._mac_wake_guard_until = 115.0
        launcher.refresh_status = mock.Mock()

        with mock.patch.object(gui.time, "time", return_value=105.0),              mock.patch.object(gui.core, "structured_log"),              mock.patch.object(gui, "_run_headless") as run,              mock.patch.object(gui.messagebox, "askyesno") as ask:
            launcher.restore_network(confirm=True)

        run.assert_not_called()
        ask.assert_not_called()


class FinalStatusUxTests(unittest.TestCase):
    def status(self, **overrides):
        values = {
            "running": False,
            "enabled": False,
            "pending": False,
            "orphaned_pac": False,
            "stale_proxy": False,
        }
        values.update(overrides)
        return gui._final_status_view(**values)

    def test_active_state_is_unambiguous_and_actionable(self):
        view = self.status(running=True, enabled=True)
        self.assertEqual(view["key"], "active")
        self.assertEqual(view["label"], "ПРОКСИ РАБОТАЕТ")
        self.assertFalse(view["can_on"])
        self.assertTrue(view["can_off"])
        self.assertTrue(view["can_check"])
        self.assertIn("Windows", view["hint"])

    def test_engine_only_state_avoids_internal_pac_jargon_in_primary_label(self):
        view = self.status(running=True, enabled=False)
        self.assertEqual(view["key"], "engine_only")
        self.assertEqual(view["label"], "ПРОКСИ ЗАПУЩЕН · НЕ ПОДКЛЮЧЕН")
        self.assertNotIn("PAC", view["label"])
        self.assertTrue(view["can_on"])
        self.assertTrue(view["can_off"])

    def test_recovery_state_blocks_proxy_actions_and_promotes_restore(self):
        view = self.status(pending=True)
        self.assertEqual(view["key"], "recovery_required")
        self.assertFalse(view["can_on"])
        self.assertFalse(view["can_off"])
        self.assertTrue(view["restore_primary"])
        self.assertIn("Восстановить настройки сети", view["hint"])

    def test_orphaned_state_exposes_only_safe_cleanup_action(self):
        view = self.status(orphaned_pac=True)
        self.assertEqual(view["key"], "orphaned_arvectum_pac")
        self.assertFalse(view["can_on"])
        self.assertFalse(view["can_off"])
        self.assertFalse(view["can_check"])
        self.assertTrue(view["show_orphan_action"])

    def test_diagnostics_state_is_fail_closed(self):
        view = self.status(stale_proxy=True)
        self.assertEqual(view["key"], "diagnostics_required")
        self.assertFalse(view["can_on"])
        self.assertFalse(view["can_off"])
        self.assertIn("Диагностика", view["hint"])

    def test_off_state_confirms_safe_final_state(self):
        view = self.status()
        self.assertEqual(view["key"], "off")
        self.assertEqual(view["label"], "ПРОКСИ ВЫКЛЮЧЕН")
        self.assertTrue(view["can_on"])
        self.assertFalse(view["can_off"])
        self.assertIn("Исходные сетевые настройки", view["hint"])

    def test_running_state_keeps_precedence_over_recovery_evidence(self):
        view = self.status(running=True, enabled=True, pending=True)
        self.assertEqual(view["key"], "active")

    def test_status_copy_can_target_macos_without_windows_leakage(self):
        view = gui._final_status_view(
            running=True,
            enabled=True,
            pending=False,
            orphaned_pac=False,
            stale_proxy=False,
            platform_label="macOS",
        )
        self.assertIn("macOS", view["hint"])
        self.assertNotIn("Windows", view["hint"])

    def test_platform_label_reports_macos_for_darwin(self):
        with mock.patch.object(gui.sys, "platform", "darwin"):
            self.assertEqual(gui._platform_label(), "macOS")
            self.assertIn("macOS", gui._autostart_label())


if __name__ == "__main__":
    unittest.main()
