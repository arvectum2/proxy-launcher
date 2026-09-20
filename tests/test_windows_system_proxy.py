import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import proxy_core as core
import system_proxy_runtime
import windows_system_proxy


class WindowsSystemProxyOwnershipTests(unittest.TestCase):
    def _internet_snapshot(self):
        return {
            "AutoConfigURL": {"exists": True, "value": "http://corp/pac"},
            "ProxyEnable": {"exists": True, "value": 1},
            "ProxyServer": {"exists": True, "value": "corp:3128"},
            "ProxyOverride": {"exists": False, "value": None},
            "AutoDetect": {"exists": True, "value": 1},
        }

    def _env_snapshot(self):
        return {
            "HTTP_PROXY": {"exists": False, "value": ""},
            "HTTPS_PROXY": {"exists": True, "value": "http://old:8080"},
            "ALL_PROXY": {"exists": False, "value": ""},
            "NO_PROXY": {"exists": True, "value": "corp.local,localhost"},
        }

    def test_persistence_helpers_are_owned_by_canonical_module(self):
        for name in (
            "_env_backup_path",
            "_internet_backup_path",
            "_read_internet_settings",
            "_valid_internet_backup",
            "_known_internet_backup_paths",
            "_valid_internet_backup_at",
            "_exact_arvectum_pac_url",
            "_save_internet_backup",
            "_restore_internet_backup",
            "_read_user_env",
            "_write_user_env",
            "_delete_user_env",
            "_broadcast_environment_change",
            "_combined_no_proxy",
            "_enable_client_proxy_env",
            "_disable_client_proxy_env",
            "pac_url",
            "_reg_set",
            "_reg_del",
            "_refresh_internet",
        ):
            self.assertEqual(getattr(core, name).__module__, "windows_system_proxy")

    def test_system_proxy_runtime_captures_canonical_windows_implementation(self):
        adapter = system_proxy_runtime._WINDOWS_CORE
        self.assertIsNotNone(adapter)
        self.assertEqual(adapter.enable.__module__, "windows_system_proxy")
        self.assertEqual(adapter.disable.__module__, "windows_system_proxy")
        self.assertEqual(adapter.enabled.__module__, "windows_system_proxy")
        self.assertEqual(adapter.restore_pending.__module__, "windows_system_proxy")
        self.assertEqual(adapter.sync_no_proxy.__module__, "windows_system_proxy")
        # Public application seams remain owned by the composition layer.
        self.assertEqual(core.enable_system_proxy.__module__, "system_proxy_runtime")
        self.assertEqual(core.disable_system_proxy.__module__, "system_proxy_runtime")
        self.assertEqual(core.system_proxy_enabled.__module__, "system_proxy_runtime")
        self.assertEqual(core.network_restore_pending.__module__, "system_proxy_runtime")
        self.assertEqual(core.sync_client_no_proxy.__module__, "system_proxy_runtime")

    def test_pac_url_and_ownership_comparison_are_structural(self):
        settings = dict(core.DEFAULT_SETTINGS)
        settings["local_pac_port"] = 9092
        settings["pac_path"] = "custom.pac"
        expected = "http://127.0.0.1:9092/custom.pac"
        self.assertEqual(core.pac_url(settings), expected)
        self.assertTrue(core._exact_arvectum_pac_url(expected, settings))
        for foreign in (
            expected + ".evil",
            "http://127.0.0.1.evil:9092/custom.pac",
            "http://127.0.0.1:9092/custom.pac?x=1",
            "http://user@127.0.0.1:9092/custom.pac",
        ):
            self.assertFalse(core._exact_arvectum_pac_url(foreign, settings))

    def test_existing_invalid_internet_backup_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_internet_backup.json"
            path.write_text("not-json", encoding="utf-8")
            with mock.patch.object(core, "_internet_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_read_internet_settings") as read, \
                 mock.patch.object(core, "_log"):
                self.assertFalse(core._save_internet_backup())
            read.assert_not_called()
            self.assertEqual(path.read_text(encoding="utf-8"), "not-json")

    def test_internet_backup_is_created_before_mutation_and_restored_exactly(self):
        snapshot = self._internet_snapshot()
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_internet_backup.json"
            with mock.patch.object(core, "_internet_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_read_internet_settings", return_value=snapshot), \
                 mock.patch.object(core, "_log"):
                self.assertTrue(core._save_internet_backup())
            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), snapshot)

            with mock.patch.object(core, "_internet_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_read_internet_settings", return_value=snapshot), \
                 mock.patch.object(core, "_reg_set", return_value=True) as set_value, \
                 mock.patch.object(core, "_reg_del", return_value=True) as delete_value, \
                 mock.patch.object(core, "_log"):
                self.assertTrue(core._restore_internet_backup())

            self.assertFalse(path.exists())
            delete_value.assert_called_once_with("ProxyOverride")
            set_value.assert_any_call("ProxyEnable", "1", "REG_DWORD")
            set_value.assert_any_call("AutoDetect", "1", "REG_DWORD")
            set_value.assert_any_call("ProxyServer", "corp:3128", "REG_SZ")
            set_value.assert_any_call("AutoConfigURL", "http://corp/pac", "REG_SZ")

    def test_missing_or_invalid_internet_backup_never_guesses_foreign_state(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "missing.json"
            with mock.patch.object(core, "_internet_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_reg_set") as set_value, \
                 mock.patch.object(core, "_reg_del") as delete_value, \
                 mock.patch.object(core, "_log"):
                self.assertTrue(core._restore_internet_backup())
            set_value.assert_not_called()
            delete_value.assert_not_called()

    def test_proxy_environment_snapshot_preserves_original_no_proxy(self):
        original = self._env_snapshot()
        reads = {
            name: (item["exists"], item["value"])
            for name, item in original.items()
        }
        writes = {}

        def read_env(name):
            return reads[name]

        def write_env(name, value):
            writes[name] = value
            return True

        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_env_backup.json"
            with mock.patch.object(core, "_env_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_read_user_env", side_effect=read_env), \
                 mock.patch.object(core, "_write_user_env", side_effect=write_env), \
                 mock.patch.object(core, "load_no_proxy", return_value=["example.test"]), \
                 mock.patch.object(core, "_broadcast_environment_change"), \
                 mock.patch.object(core, "_log"):
                self.assertTrue(core._enable_client_proxy_env(8181))

            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), original)
            for name in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"):
                self.assertEqual(writes[name], "http://127.0.0.1:8181")
            direct = writes["NO_PROXY"].split(",")
            self.assertIn("corp.local", direct)
            self.assertIn("localhost", direct)
            self.assertIn("example.test", direct)

    def test_invalid_proxy_environment_backup_blocks_mutation(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_env_backup.json"
            path.write_text("{}", encoding="utf-8")
            with mock.patch.object(core, "_env_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_write_user_env") as write_env, \
                 mock.patch.object(core, "_log"):
                self.assertFalse(core._enable_client_proxy_env(8080))
            write_env.assert_not_called()
            self.assertEqual(path.read_text(encoding="utf-8"), "{}")

    def test_incomplete_proxy_environment_restore_keeps_backup_for_retry(self):
        snapshot = self._env_snapshot()
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_env_backup.json"
            path.write_text(json.dumps(snapshot), encoding="utf-8")

            def write_env(name, value):
                return name != "HTTPS_PROXY"

            applied = {
                "HTTP_PROXY": (True, "http://127.0.0.1:8080"),
                "HTTPS_PROXY": (True, "http://127.0.0.1:8080"),
                "ALL_PROXY": (True, "http://127.0.0.1:8080"),
                "NO_PROXY": (True, "corp.local,localhost"),
            }
            with mock.patch.object(core, "_env_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_read_user_env", side_effect=lambda name: applied[name]), \
                 mock.patch.object(core, "load_settings", return_value={"local_http_port": 8080}), \
                 mock.patch.object(core, "load_no_proxy", return_value=[]), \
                 mock.patch.object(core, "DEFAULT_NO_PROXY", ("localhost",)), \
                 mock.patch.object(core, "_write_user_env", side_effect=write_env), \
                 mock.patch.object(core, "_delete_user_env", return_value=True), \
                 mock.patch.object(core, "_broadcast_environment_change") as broadcast, \
                 mock.patch.object(core, "_log"):
                self.assertFalse(core._disable_client_proxy_env())
            self.assertTrue(path.exists())
            broadcast.assert_not_called()

    def test_internet_mixed_saved_and_arvectum_fields_restore_safely(self):
        snapshot = self._internet_snapshot()
        current = dict(snapshot)
        current["AutoConfigURL"] = {"exists": True, "value": "http://127.0.0.1:8082/proxy.pac"}
        current["ProxyEnable"] = {"exists": True, "value": 0}
        current["AutoDetect"] = {"exists": True, "value": 0}
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_internet_backup.json"
            path.write_text(json.dumps(snapshot), encoding="utf-8")
            with mock.patch.object(core, "_internet_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_read_internet_settings", return_value=current), \
                 mock.patch.object(core, "load_settings", return_value=dict(core.DEFAULT_SETTINGS)), \
                 mock.patch.object(core, "_reg_set", return_value=True), \
                 mock.patch.object(core, "_reg_del", return_value=True), \
                 mock.patch.object(core, "_log"):
                self.assertTrue(core._restore_internet_backup())
            self.assertFalse(path.exists())

    def test_manual_arvectum_pac_disable_to_saved_state_is_recoverable(self):
        snapshot = self._internet_snapshot()
        snapshot["AutoConfigURL"] = {"exists": False, "value": None}
        snapshot["ProxyEnable"] = {"exists": True, "value": 0}
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_internet_backup.json"
            path.write_text(json.dumps(snapshot), encoding="utf-8")
            with mock.patch.object(core, "_internet_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_read_internet_settings", return_value=snapshot), \
                 mock.patch.object(core, "_reg_set", return_value=True), \
                 mock.patch.object(core, "_reg_del", return_value=True), \
                 mock.patch.object(core, "_log"):
                self.assertTrue(core._restore_internet_backup())
            self.assertFalse(path.exists())

    def test_foreign_wininet_change_refuses_restore_and_keeps_backup(self):
        snapshot = self._internet_snapshot()
        current = dict(snapshot)
        current["AutoConfigURL"] = {"exists": True, "value": "https://corp-new.example/proxy.pac"}
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_internet_backup.json"
            path.write_text(json.dumps(snapshot), encoding="utf-8")
            with mock.patch.object(core, "_internet_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_read_internet_settings", return_value=current), \
                 mock.patch.object(core, "_reg_set") as set_value, \
                 mock.patch.object(core, "_reg_del") as delete_value, \
                 mock.patch.object(core, "_log"):
                self.assertFalse(core._restore_internet_backup())
            self.assertTrue(path.exists())
            set_value.assert_not_called()
            delete_value.assert_not_called()

    def test_foreign_manual_proxy_field_refuses_restore(self):
        snapshot = self._internet_snapshot()
        current = dict(snapshot)
        current["ProxyServer"] = {"exists": True, "value": "new-corp:8443"}
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_internet_backup.json"
            path.write_text(json.dumps(snapshot), encoding="utf-8")
            with mock.patch.object(core, "_internet_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_read_internet_settings", return_value=current), \
                 mock.patch.object(core, "_reg_set") as set_value, \
                 mock.patch.object(core, "_reg_del") as delete_value, \
                 mock.patch.object(core, "_log"):
                self.assertFalse(core._restore_internet_backup())
            self.assertTrue(path.exists())
            set_value.assert_not_called()
            delete_value.assert_not_called()

    def test_foreign_proxy_environment_change_refuses_restore(self):
        snapshot = self._env_snapshot()
        current = {
            "HTTP_PROXY": (True, "http://127.0.0.1:8080"),
            "HTTPS_PROXY": (True, "http://foreign.example:3128"),
            "ALL_PROXY": (True, "http://127.0.0.1:8080"),
            "NO_PROXY": (True, "corp.local,localhost"),
        }
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "proxy_env_backup.json"
            path.write_text(json.dumps(snapshot), encoding="utf-8")
            with mock.patch.object(core, "_env_backup_path", return_value=str(path)), \
                 mock.patch.object(core, "_read_user_env", side_effect=lambda name: current[name]), \
                 mock.patch.object(core, "load_settings", return_value={"local_http_port": 8080}), \
                 mock.patch.object(core, "load_no_proxy", return_value=[]), \
                 mock.patch.object(core, "DEFAULT_NO_PROXY", ("localhost",)), \
                 mock.patch.object(core, "_write_user_env") as write_env, \
                 mock.patch.object(core, "_delete_user_env") as delete_env, \
                 mock.patch.object(core, "_log"):
                self.assertFalse(core._disable_client_proxy_env())
            self.assertTrue(path.exists())
            write_env.assert_not_called()
            delete_env.assert_not_called()

    def test_enable_publishes_pac_to_wininet_and_refreshes_consumers(self):
        settings = dict(core.DEFAULT_SETTINGS)
        settings["local_pac_port"] = 9092
        settings["pac_path"] = "/custom.pac"
        settings["local_http_port"] = 8181
        with mock.patch.object(core, "load_settings", return_value=settings), \
             mock.patch.object(core, "is_windows", return_value=True), \
             mock.patch.object(core, "_save_internet_backup", return_value=True), \
             mock.patch.object(core, "_reg_set", return_value=True) as set_value, \
             mock.patch.object(core, "_enable_client_proxy_env", return_value=True) as env_enable, \
             mock.patch.object(core, "_enable_recovery_autostart", return_value=True) as recovery, \
             mock.patch.object(core, "_refresh_internet") as refresh, \
             mock.patch.object(core, "_log"):
            self.assertTrue(windows_system_proxy.enable_system_proxy())

        set_value.assert_any_call(
            "AutoConfigURL",
            "http://127.0.0.1:9092/custom.pac",
            "REG_SZ",
        )
        set_value.assert_any_call("ProxyEnable", "0", "REG_DWORD")
        set_value.assert_any_call("AutoDetect", "0", "REG_DWORD")
        env_enable.assert_called_once_with(8181)
        recovery.assert_called_once_with()
        refresh.assert_called_once_with()

    def test_system_proxy_enabled_requires_exclusive_apl_pac_route(self):
        settings = dict(core.DEFAULT_SETTINGS)
        apl_url = windows_system_proxy.pac_url(settings)
        base = self._internet_snapshot()
        base["AutoConfigURL"] = {"exists": True, "value": apl_url}
        base["ProxyEnable"] = {"exists": True, "value": 0}
        base["AutoDetect"] = {"exists": True, "value": 0}

        with mock.patch.object(core, "is_windows", return_value=True),              mock.patch.object(core, "load_settings", return_value=settings),              mock.patch.object(core, "_read_internet_settings", return_value=base):
            self.assertTrue(windows_system_proxy.system_proxy_enabled())

        for name, value in (("ProxyEnable", 1), ("AutoDetect", 1)):
            variant = {key: dict(item) for key, item in base.items()}
            variant[name] = {"exists": True, "value": value}
            with self.subTest(name=name),                  mock.patch.object(core, "is_windows", return_value=True),                  mock.patch.object(core, "load_settings", return_value=settings),                  mock.patch.object(core, "_read_internet_settings", return_value=variant):
                self.assertFalse(windows_system_proxy.system_proxy_enabled())

    def test_enable_aborts_before_registry_mutation_when_backup_cannot_be_proven(self):
        settings = dict(core.DEFAULT_SETTINGS)
        with mock.patch.object(core, "load_settings", return_value=settings), \
             mock.patch.object(core, "is_windows", return_value=True), \
             mock.patch.object(core, "_save_internet_backup", return_value=False), \
             mock.patch.object(core, "_reg_set") as set_value, \
             mock.patch.object(core, "_enable_client_proxy_env") as env_enable, \
             mock.patch.object(core, "_enable_recovery_autostart") as recovery, \
             mock.patch.object(core, "_log"):
            self.assertFalse(windows_system_proxy.enable_system_proxy())
        set_value.assert_not_called()
        env_enable.assert_not_called()
        recovery.assert_not_called()

    def test_enable_failure_rolls_back_internet_env_and_recovery_state(self):
        settings = dict(core.DEFAULT_SETTINGS)
        with mock.patch.object(core, "load_settings", return_value=settings), \
             mock.patch.object(core, "is_windows", return_value=True), \
             mock.patch.object(core, "_save_internet_backup", return_value=True), \
             mock.patch.object(core, "_reg_set", return_value=True), \
             mock.patch.object(core, "_enable_client_proxy_env", return_value=False), \
             mock.patch.object(core, "_enable_recovery_autostart", return_value=True), \
             mock.patch.object(core, "_restore_internet_backup", return_value=True) as restore, \
             mock.patch.object(core, "_disable_client_proxy_env", return_value=True) as env_restore, \
             mock.patch.object(core, "_disable_recovery_autostart", return_value=True) as recovery_restore, \
             mock.patch.object(core, "_refresh_internet") as refresh, \
             mock.patch.object(core, "_log"):
            self.assertFalse(windows_system_proxy.enable_system_proxy())
        restore.assert_called_once_with()
        env_restore.assert_called_once_with()
        recovery_restore.assert_called_once_with()
        refresh.assert_called_once_with()

    def test_disable_keeps_recovery_owner_until_network_state_is_safe(self):
        with mock.patch.object(core, "is_windows", return_value=True), \
             mock.patch.object(core, "system_proxy_enabled", side_effect=[True, True, True]), \
             mock.patch.object(core, "_valid_internet_backup_at", return_value=True), \
             mock.patch.object(core, "_restore_internet_backup", return_value=False), \
             mock.patch.object(core, "_disable_client_proxy_env", return_value=False), \
             mock.patch.object(core, "_internet_backup_path", return_value="internet.json"), \
             mock.patch.object(core, "_env_backup_path", return_value="proxy_env_backup.json"), \
             mock.patch.object(os.path, "exists", return_value=True), \
             mock.patch.object(core, "_disable_recovery_autostart") as recovery_disable, \
             mock.patch.object(core, "_refresh_internet"), \
             mock.patch.object(core, "_log"):
            self.assertFalse(windows_system_proxy.disable_system_proxy())
        recovery_disable.assert_not_called()

    def test_network_restore_pending_tracks_only_backup_evidence(self):
        with mock.patch.object(core, "is_windows", return_value=True), \
             mock.patch.object(core, "_internet_backup_path", return_value="internet.json"), \
             mock.patch.object(core, "_env_backup_path", return_value="env.json"), \
             mock.patch.object(os.path, "exists", side_effect=lambda value: value == "env.json"):
            self.assertTrue(windows_system_proxy.network_restore_pending())
        with mock.patch.object(core, "is_windows", return_value=False):
            self.assertFalse(windows_system_proxy.network_restore_pending())


if __name__ == "__main__":
    unittest.main()