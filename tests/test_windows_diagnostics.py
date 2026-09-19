import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

import windows_diagnostics as diag


class FakeCore:
    APP_VERSION = "0.2.3"
    ENGINEERING_MILESTONE = "P0.2"
    _PROXY_ENV_NAMES = ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY")

    def __init__(self, root, windows=True):
        self.root = Path(root)
        self.windows = windows
        self.events = []
        self.load_settings_migrate_flags = []
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / "proxy_internet_backup.json").write_text("{}", encoding="utf-8")
        (self.root / "proxy_env_backup.json").write_text("{}", encoding="utf-8")
        (self.root / "proxy_core.log").write_text("", encoding="utf-8")

    def is_windows(self):
        return self.windows

    def install_dir(self):
        return str(self.root / "install")

    def data_dir(self):
        return str(self.root)

    def stable_app_dir(self):
        return str(self.root / "Documents" / "ArvectumProxyLauncher")

    def stable_app_exe(self):
        return str(Path(self.stable_app_dir()) / "Arvectum Proxy Launcher.exe")

    def settings_path(self):
        return str(self.root / "proxy_settings.json")

    def no_proxy_path(self):
        return str(self.root / "no_proxy.txt")

    def pid_path(self):
        return str(self.root / "proxy_core.pid")

    def log_path(self):
        return str(self.root / "proxy_core.log")

    def migration_error_path(self):
        return str(self.root / "state_migration_conflict.json")

    def _internet_backup_path(self):
        return str(self.root / "proxy_internet_backup.json")

    def _env_backup_path(self):
        return str(self.root / "proxy_env_backup.json")

    def load_settings(self, migrate_legacy=True):
        self.load_settings_migrate_flags.append(migrate_legacy)
        return {
            "local_http_port": 8080,
            "local_socks_port": 1080,
            "local_pac_port": 8082,
            "pac_path": "/proxy.pac",
            "upstream": [{
                "host": "proxy.example.test",
                "port": 8000,
                "username": "alice",
                "password": "settings-secret-123",
            }],
        }

    def load_no_proxy(self):
        return ["127.0.0.1", "zakupki.gov.ru"]

    def is_running(self):
        return False

    def system_proxy_enabled(self):
        return False

    def network_restore_pending(self):
        return True

    def state_migration_blocked(self):
        return False

    def stale_system_proxy(self):
        return False

    def orphaned_arvectum_pac(self):
        return False

    def pac_url(self, settings):
        return "http://127.0.0.1:%d/proxy.pac" % settings["local_pac_port"]

    def _read_internet_settings(self):
        return {
            "ProxyEnable": {"exists": True, "value": 0, "type": 4},
            "AutoConfigURL": {"exists": True, "value": "http://127.0.0.1:8082/proxy.pac", "type": 1},
            "ProxyServer": {
                "exists": True,
                "value": "http://bob:registry-secret-789@corp-proxy.example.test:3128",
                "type": 1,
            },
        }

    def _read_user_env(self, name):
        if name == "HTTP_PROXY":
            return True, "http://carol:registry-env-secret@env-proxy.example.test:8080"
        if name == "NO_PROXY":
            return True, "localhost,127.0.0.1"
        return False, ""

    def proxy_listener_active(self):
        return False

    def _get_recovery_run_value(self):
        return '"Arvectum Proxy Launcher.exe" --token run-secret-123 --start'

    def classify_recovery_autostart(self, command):
        return "legacy_arvectum"

    def structured_log(self, message, **fields):
        self.events.append((message, fields))
        return {"message": message, "fields": fields}


class WindowsDiagnosticsTests(unittest.TestCase):
    def _fake(self, td, windows=True):
        return FakeCore(td, windows=windows)

    def test_snapshot_collects_required_sections_and_redacts_every_source(self):
        with tempfile.TemporaryDirectory() as td:
            fake = self._fake(td)
            with patch.object(diag, "core", fake), patch.dict(
                os.environ,
                {"HTTP_PROXY": "http://dan:env-secret-456@process-proxy.example.test:9000"},
                clear=True,
            ):
                snapshot = diag.collect_snapshot()

            self.assertEqual(snapshot["schema"], diag.SCHEMA)
            self.assertTrue(snapshot["sections"]["system"]["data"]["windows"])
            self.assertEqual(
                set(snapshot["sections"]),
                {"system", "application", "proxy_state", "wininet", "environment_proxy",
                 "listeners", "network_interfaces", "recovery"},
            )
            raw = json.dumps(snapshot, ensure_ascii=False)
            for secret in (
                "settings-secret-123",
                "registry-secret-789",
                "registry-env-secret",
                "env-secret-456",
                "run-secret-123",
            ):
                self.assertNotIn(secret, raw)
            self.assertIn("[REDACTED]", raw)
            self.assertIn("proxy.example.test", raw)
            self.assertTrue(snapshot["sections"]["recovery"]["data"]["network_restore_pending"])
            self.assertEqual(fake.load_settings_migrate_flags, [False, False, False])

    def test_partial_collector_failure_is_recorded_and_does_not_abort_snapshot(self):
        def broken():
            raise RuntimeError("password=partial-error-secret")

        with patch.object(diag, "_SECTION_COLLECTORS", (
            ("good", lambda: {"value": 42}),
            ("broken", broken),
        )):
            snapshot = diag.collect_snapshot()

        self.assertTrue(snapshot["sections"]["good"]["ok"])
        self.assertEqual(snapshot["sections"]["good"]["data"]["value"], 42)
        self.assertFalse(snapshot["sections"]["broken"]["ok"])
        self.assertNotIn("partial-error-secret", snapshot["sections"]["broken"]["error"])
        self.assertIn("[REDACTED]", snapshot["sections"]["broken"]["error"])

    def test_support_bundle_contains_only_redacted_json_and_logs(self):
        with tempfile.TemporaryDirectory() as td:
            fake = self._fake(td)
            log_path = Path(fake.log_path())
            log_path.write_text(
                json.dumps({
                    "schema": "arvectum.proxy.log.v1",
                    "message": "Authorization: Bearer abcdefghijklmnopqrstuvwxyz",
                    "fields": {
                        "password": "log-secret-321",
                        "host": "proxy.example.test",
                    },
                }) + "\n" + "password=legacy-log-secret\n",
                encoding="utf-8",
            )
            output = Path(td) / "bundle" / "support.zip"
            with patch.object(diag, "core", fake), patch.object(
                diag, "_collect_network_interfaces", return_value={"source": "test", "interfaces": []}
            ):
                result = Path(diag.create_support_bundle(str(output)))

            self.assertEqual(result, output)
            self.assertTrue(result.is_file())
            self.assertFalse(any(result.parent.glob("*.tmp-*")))
            with zipfile.ZipFile(result, "r") as archive:
                names = set(archive.namelist())
                self.assertIn("diagnostics.json", names)
                self.assertIn("logs/proxy_core.log", names)
                self.assertNotIn("proxy_settings.json", names)
                self.assertNotIn("proxy_internet_backup.json", names)
                payload = "\n".join(
                    archive.read(name).decode("utf-8", errors="replace") for name in sorted(names)
                )
            for secret in (
                "settings-secret-123",
                "registry-secret-789",
                "registry-env-secret",
                "log-secret-321",
                "legacy-log-secret",
                "abcdefghijklmnopqrstuvwxyz",
            ):
                self.assertNotIn(secret, payload)
            self.assertIn("[REDACTED]", payload)
            self.assertTrue(any(fields.get("event") == "diagnostics.bundle_created" for _, fields in fake.events))

    def test_collector_refuses_non_windows_bundle_creation(self):
        with tempfile.TemporaryDirectory() as td:
            fake = self._fake(td, windows=False)
            with patch.object(diag, "core", fake):
                with self.assertRaises(RuntimeError):
                    diag.create_support_bundle(str(Path(td) / "should-not-exist.zip"))

    def test_listener_probe_is_localhost_only(self):
        sock = Mock()
        sock.connect_ex.return_value = 0
        with patch.object(diag.socket, "socket", return_value=sock):
            result = diag._probe_listener(8080)
        self.assertTrue(result["listening"])
        sock.connect_ex.assert_called_once_with(("127.0.0.1", 8080))

    def test_macos_listener_probe_reports_owner_process(self):
        sock = Mock()
        sock.connect_ex.return_value = 0
        completed = Mock(
            returncode=0,
            stdout="p1139\ncPython\n",
            stderr="",
        )
        with patch.object(diag.socket, "socket", return_value=sock), \
             patch.object(diag.sys, "platform", "darwin"), \
             patch.object(diag.os.path, "isfile", return_value=True), \
             patch.object(diag.subprocess, "run", return_value=completed) as run:
            result = diag._probe_listener(8080)
        self.assertTrue(result["listening"])
        self.assertEqual(result["owners"], [{"pid": 1139, "command": "Python"}])
        self.assertIn("-iTCP:8080", run.call_args.args[0])

    def test_crash_recovery_state_is_collectible_without_engine_running(self):
        with tempfile.TemporaryDirectory() as td:
            fake = self._fake(td)
            with patch.object(diag, "core", fake):
                section = diag._collect_recovery_state()
            self.assertTrue(section["network_restore_pending"])
            self.assertTrue(section["internet_backup"]["exists"])
            self.assertTrue(section["environment_backup"]["exists"])
            self.assertEqual(section["recovery_run"]["classification"], "legacy_arvectum")


if __name__ == "__main__":
    unittest.main()
