"""Regression coverage for safe Windows PAC self-repair."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import application_runtime
import proxy_core as core
import windows_system_proxy


class WindowsPacSelfHealingTests(unittest.TestCase):
    def setUp(self):
        self.context = tempfile.TemporaryDirectory()
        self.addCleanup(self.context.cleanup)
        self.backup = Path(self.context.name) / "proxy_internet_backup.json"
        self.saved = {
            "AutoConfigURL": {"exists": False, "value": None},
            "ProxyEnable": {"exists": True, "value": 0},
            "ProxyServer": {"exists": True, "value": "corp:3128"},
            "ProxyOverride": {"exists": False, "value": None},
            "AutoDetect": {"exists": True, "value": 0},
        }
        self.backup.write_text(json.dumps(self.saved), encoding="utf-8")
        self.current = {name: dict(value) for name, value in self.saved.items()}
        self.settings = dict(core.DEFAULT_SETTINGS)
        self.pac_url = core.pac_url(self.settings)

    def run_check(self, registry=None, read_side_effect=None, backup_exists=True):
        registry = registry if registry is not None else self.current
        with mock.patch.object(core, "is_windows", return_value=True), \
             mock.patch.object(core, "is_running", return_value=True), \
             mock.patch.object(core, "_internet_backup_path", return_value=str(self.backup)), \
             mock.patch.object(core, "_valid_internet_backup_at", return_value=backup_exists), \
             mock.patch.object(core, "load_settings", return_value=self.settings), \
             mock.patch.object(core, "_read_internet_settings", side_effect=read_side_effect if read_side_effect is not None else lambda: registry), \
             mock.patch.object(core, "_reg_set", return_value=True) as reg_set, \
             mock.patch.object(core, "_refresh_internet") as refresh, \
             mock.patch.object(core, "system_proxy_enabled", return_value=True):
            outcome = windows_system_proxy.reconcile_owned_pac()
        return outcome, reg_set, refresh

    def test_recovers_only_missing_pac_with_valid_owned_backup(self):
        outcome, reg_set, refresh = self.run_check()
        self.assertEqual(outcome, "restored")
        reg_set.assert_called_once_with("AutoConfigURL", self.pac_url, "REG_SZ")
        refresh.assert_called_once_with()
        self.assertEqual(json.loads(self.backup.read_text()), self.saved)

    def test_healthy_pac_does_not_write_again(self):
        self.current["AutoConfigURL"] = {"exists": True, "value": self.pac_url}
        outcome, reg_set, refresh = self.run_check()
        self.assertEqual(outcome, "healthy")
        reg_set.assert_not_called()
        refresh.assert_not_called()

    def test_foreign_pac_not_overwritten(self):
        self.current["AutoConfigURL"] = {"exists": True, "value": "http://foreign/pac"}
        outcome, reg_set, _ = self.run_check()
        self.assertEqual(outcome, "foreign")
        reg_set.assert_not_called()

    def test_manual_proxy_enable_not_overwritten(self):
        self.current["ProxyEnable"]["value"] = 1
        outcome, reg_set, _ = self.run_check()
        self.assertEqual(outcome, "foreign")
        reg_set.assert_not_called()

    def test_autodetect_and_foreign_proxy_server_not_overwritten(self):
        for field, value in (("AutoDetect", 1), ("ProxyServer", "different:80")):
            with self.subTest(field=field):
                self.current[field]["value"] = value
                outcome, reg_set, _ = self.run_check()
                self.assertEqual(outcome, "foreign")
                reg_set.assert_not_called()
                self.current[field]["value"] = self.saved[field]["value"]

    def test_missing_rollback_evidence_never_triggers_mutation(self):
        outcome, reg_set, _ = self.run_check(backup_exists=False)
        self.assertEqual(outcome, "unverified")
        reg_set.assert_not_called()

    def test_changed_registry_between_reads_skips_repair(self):
        modified = {key: dict(value) for key, value in self.current.items()}
        modified["AutoConfigURL"] = {"exists": True, "value": "http://other/pac"}
        outcome, reg_set, _ = self.run_check(read_side_effect=[self.current, modified])
        self.assertEqual(outcome, "raced")
        reg_set.assert_not_called()

    def test_stopped_worker_never_changes_wininet(self):
        with mock.patch.object(core, "is_windows", return_value=True), \
             mock.patch.object(core, "is_running", return_value=False), \
             mock.patch.object(core, "_reg_set") as reg_set:
            self.assertEqual(windows_system_proxy.reconcile_owned_pac(), "inactive")
        reg_set.assert_not_called()

    def test_background_loop_rechecks_and_quits_when_stopped(self):
        stop = mock.Mock()
        stop.wait.side_effect = [False, False, True]
        stop.is_set.return_value = False
        proxy = mock.Mock(_stop=stop)
        with mock.patch.object(application_runtime.sys, "platform", "win32"), \
             mock.patch.object(core, "reconcile_owned_pac", side_effect=["restored", "healthy"]) as recovery, \
             mock.patch.object(core, "structured_log") as log:
            application_runtime._run_proxy_loop(proxy)
        self.assertEqual(recovery.call_count, 2)
        self.assertEqual(stop.wait.call_count, 3)
        log.assert_called_once()
        self.assertEqual(log.call_args.kwargs["outcome"], "restored")


if __name__ == "__main__":
    unittest.main()
