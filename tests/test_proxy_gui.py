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
        with mock.patch.object(gui.core, "load_settings",
                               return_value={"upstream": [{"host": "test.invalid"}]}), \
             mock.patch.object(gui, "_portable_fallback_active", return_value=True), \
             mock.patch.object(gui.messagebox, "showwarning") as warning:
            self.assertFalse(launcher._enable_autostart())
        self.assertFalse(launcher.auto_var.get())
        warning.assert_called_once()

    def test_foreign_task_conflict_resets_checkbox(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.auto_var = _BoolVar(True)
        launcher._autostart_run_value = mock.Mock(return_value=None)
        launcher._autostart_run_is_ours = mock.Mock(return_value=False)
        launcher._autostart_task_xml = mock.Mock(return_value="foreign task xml")
        launcher._autostart_task_is_ours = mock.Mock(return_value=False)

        with mock.patch.object(gui.core, "load_settings", return_value={"upstream": [{"host": "test.invalid"}]}), \
             mock.patch.object(gui.messagebox, "showerror"):
            launcher._toggle_autostart()

        self.assertFalse(launcher.auto_var.get())

    def test_autostart_prefers_owned_per_user_run_value(self):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher._autostart_run_is_ours = mock.Mock(return_value=True)
        launcher._autostart_task_is_ours = mock.Mock(return_value=False)

        self.assertTrue(launcher._autostart_enabled())
        launcher._autostart_task_is_ours.assert_not_called()


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
