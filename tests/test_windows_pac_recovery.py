import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import proxy_core as core
import windows_pac_recovery


class WindowsPacRecoveryOwnershipTests(unittest.TestCase):
    def _owned_values(self, url="http://127.0.0.1:8082/proxy.pac"):
        return {"AutoConfigURL": {"exists": True, "value": url}}

    def _orphan_context(self, values=None):
        return (
            mock.patch.object(core, "is_windows", return_value=True),
            mock.patch.object(core, "state_migration_blocked", return_value=False),
            mock.patch.object(
                core,
                "_read_internet_settings",
                return_value=values if values is not None else self._owned_values(),
            ),
            mock.patch.object(core, "proxy_listener_active", return_value=False),
            mock.patch.object(core, "is_running", return_value=False),
            mock.patch.object(core, "_any_known_internet_backup_exists", return_value=False),
            mock.patch.object(core, "canonical_install_exe", return_value=None),
        )

    def test_functions_are_owned_by_canonical_module(self):
        for name in (
            "_any_known_internet_backup_exists",
            "stale_system_proxy",
            "orphaned_arvectum_pac",
            "_write_orphaned_pac_snapshot",
            "clear_orphaned_arvectum_pac",
        ):
            with self.subTest(name=name):
                self.assertEqual(getattr(core, name).__module__, "windows_pac_recovery")

    def test_any_backup_file_is_ambiguity_evidence_even_if_invalid(self):
        with tempfile.TemporaryDirectory() as td:
            missing = os.path.join(td, "missing.json")
            invalid = os.path.join(td, "invalid.json")
            Path(invalid).write_text("not-json", encoding="utf-8")
            with mock.patch.object(
                core,
                "_known_internet_backup_paths",
                return_value=[missing, invalid],
            ):
                self.assertTrue(core._any_known_internet_backup_exists())
            os.remove(invalid)
            with mock.patch.object(
                core,
                "_known_internet_backup_paths",
                return_value=[missing, invalid],
            ):
                self.assertFalse(core._any_known_internet_backup_exists())

    def test_stale_system_proxy_is_diagnostic_only_when_all_blockers_are_absent(self):
        with mock.patch.object(core, "system_proxy_enabled", return_value=True), \
             mock.patch.object(core, "is_running", return_value=False), \
             mock.patch.object(core, "network_restore_pending", return_value=False), \
             mock.patch.object(core, "state_migration_blocked", return_value=False):
            self.assertTrue(core.stale_system_proxy())

        for running, pending, blocked in (
            (True, False, False),
            (False, True, False),
            (False, False, True),
        ):
            with self.subTest(running=running, pending=pending, blocked=blocked), \
                 mock.patch.object(core, "system_proxy_enabled", return_value=True), \
                 mock.patch.object(core, "is_running", return_value=running), \
                 mock.patch.object(core, "network_restore_pending", return_value=pending), \
                 mock.patch.object(core, "state_migration_blocked", return_value=blocked):
                self.assertFalse(core.stale_system_proxy())

    def test_exact_dead_owned_pac_is_orphan_candidate(self):
        patches = self._orphan_context()
        with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5], patches[6]:
            self.assertTrue(core.orphaned_arvectum_pac())

    def test_orphan_detection_is_fail_closed_for_every_ownership_blocker(self):
        cases = (
            ("non_windows", {"is_windows": False}),
            ("migration", {"blocked": True}),
            ("listener", {"listener": True}),
            ("process", {"running": True}),
            ("backup", {"backup": True}),
            ("canonical", {"canonical": "C:/Docs/Arvectum Proxy Launcher.exe"}),
        )
        for name, overrides in cases:
            with self.subTest(name=name), \
                 mock.patch.object(core, "is_windows", return_value=overrides.get("is_windows", True)), \
                 mock.patch.object(core, "state_migration_blocked", return_value=overrides.get("blocked", False)), \
                 mock.patch.object(core, "_read_internet_settings", return_value=self._owned_values()), \
                 mock.patch.object(core, "proxy_listener_active", return_value=overrides.get("listener", False)), \
                 mock.patch.object(core, "is_running", return_value=overrides.get("running", False)), \
                 mock.patch.object(core, "_any_known_internet_backup_exists", return_value=overrides.get("backup", False)), \
                 mock.patch.object(core, "canonical_install_exe", return_value=overrides.get("canonical")):
                self.assertFalse(core.orphaned_arvectum_pac())

    def test_foreign_or_similar_pac_is_never_orphan_candidate(self):
        for url in (
            "http://127.0.0.1:9090/company-proxy.pac",
            "http://127.0.0.1:8082/proxy.pac.evil",
            "http://127.0.0.1.evil:8082/proxy.pac",
            "http://127.0.0.1:8082/proxy.pac?owner=foreign",
        ):
            patches = self._orphan_context(self._owned_values(url))
            with self.subTest(url=url), patches[0], patches[1], patches[2], patches[3], patches[4], patches[5], patches[6]:
                self.assertFalse(core.orphaned_arvectum_pac())

    def test_cleanup_deletes_only_autoconfigurl_after_snapshot_and_refreshes(self):
        values = {
            "AutoConfigURL": {"exists": True, "value": "http://127.0.0.1:8082/proxy.pac"},
            "ProxyEnable": {"exists": True, "value": 1},
            "ProxyServer": {"exists": True, "value": "corp:3128"},
            "ProxyOverride": {"exists": True, "value": "<local>"},
            "AutoDetect": {"exists": True, "value": 1},
        }
        calls = []
        with mock.patch.object(core, "orphaned_arvectum_pac", return_value=True), \
             mock.patch.object(core, "load_settings", return_value={"local_pac_port": 8082, "pac_path": "/proxy.pac"}), \
             mock.patch.object(core, "_read_internet_settings", return_value=values), \
             mock.patch.object(core, "_write_orphaned_pac_snapshot", side_effect=lambda data: calls.append("snapshot") or "snapshot.json"), \
             mock.patch.object(core, "_reg_del", side_effect=lambda name: calls.append("delete:%s" % name) or True) as delete, \
             mock.patch.object(core, "_refresh_internet", side_effect=lambda: calls.append("refresh")) as refresh, \
             mock.patch.object(core, "system_proxy_enabled", return_value=False):
            self.assertTrue(core.clear_orphaned_arvectum_pac())
        self.assertEqual(calls, ["snapshot", "delete:AutoConfigURL", "refresh"])
        delete.assert_called_once_with("AutoConfigURL")
        refresh.assert_called_once_with()
        self.assertEqual(values["ProxyEnable"]["value"], 1)
        self.assertEqual(values["ProxyServer"]["value"], "corp:3128")
        self.assertEqual(values["ProxyOverride"]["value"], "<local>")
        self.assertEqual(values["AutoDetect"]["value"], 1)

    def test_cleanup_revalidates_registry_and_aborts_on_race(self):
        foreign = self._owned_values("http://foreign.example/proxy.pac")
        with mock.patch.object(core, "orphaned_arvectum_pac", return_value=True), \
             mock.patch.object(core, "_read_internet_settings", return_value=foreign), \
             mock.patch.object(core, "_write_orphaned_pac_snapshot") as snapshot, \
             mock.patch.object(core, "_reg_del") as delete, \
             mock.patch.object(core, "_refresh_internet") as refresh:
            self.assertFalse(core.clear_orphaned_arvectum_pac())
        snapshot.assert_not_called()
        delete.assert_not_called()
        refresh.assert_not_called()

    def test_cleanup_requires_durable_snapshot_before_mutation(self):
        with mock.patch.object(core, "orphaned_arvectum_pac", return_value=True), \
             mock.patch.object(core, "_read_internet_settings", return_value=self._owned_values()), \
             mock.patch.object(core, "_write_orphaned_pac_snapshot", return_value=None), \
             mock.patch.object(core, "_reg_del") as delete, \
             mock.patch.object(core, "_refresh_internet") as refresh:
            self.assertFalse(core.clear_orphaned_arvectum_pac())
        delete.assert_not_called()
        refresh.assert_not_called()

    def test_cleanup_failure_does_not_claim_success(self):
        with mock.patch.object(core, "orphaned_arvectum_pac", return_value=True), \
             mock.patch.object(core, "_read_internet_settings", return_value=self._owned_values()), \
             mock.patch.object(core, "_write_orphaned_pac_snapshot", return_value="snapshot.json"), \
             mock.patch.object(core, "_reg_del", return_value=False), \
             mock.patch.object(core, "_refresh_internet") as refresh:
            self.assertFalse(core.clear_orphaned_arvectum_pac())
        refresh.assert_not_called()

        with mock.patch.object(core, "orphaned_arvectum_pac", return_value=True), \
             mock.patch.object(core, "_read_internet_settings", return_value=self._owned_values()), \
             mock.patch.object(core, "_write_orphaned_pac_snapshot", return_value="snapshot.json"), \
             mock.patch.object(core, "_reg_del", return_value=True), \
             mock.patch.object(core, "_refresh_internet"), \
             mock.patch.object(core, "system_proxy_enabled", return_value=True):
            self.assertFalse(core.clear_orphaned_arvectum_pac())

    def test_snapshot_is_stable_and_records_exact_pre_cleanup_state(self):
        values = self._owned_values()
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(core, "data_dir", return_value=td), \
             mock.patch.object(core, "load_settings", return_value=core.DEFAULT_SETTINGS):
            path = core._write_orphaned_pac_snapshot(values)
            self.assertTrue(path and os.path.exists(path))
            payload = json.loads(Path(path).read_text(encoding="utf-8"))
            self.assertEqual(payload["reason"], "orphaned_arvectum_pac")
            self.assertEqual(payload["internet_settings"], values)
            self.assertEqual(payload["expected_pac_url"], core.pac_url(core.DEFAULT_SETTINGS))


if __name__ == "__main__":
    unittest.main()
