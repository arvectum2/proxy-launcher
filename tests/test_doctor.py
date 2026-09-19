import io
import json
import os
import tempfile
import unittest
from unittest.mock import patch

import doctor


def healthy_snapshot():
    sections = {
        "system": {"ok": True, "data": {"platform": "Windows", "windows": True}},
        "application": {
            "ok": True,
            "data": {
                "app_version": "0.2.3",
                "engineering_milestone": "P0.2",
                "settings": {
                    "local_http_port": 8080,
                    "local_socks_port": 1080,
                    "local_pac_port": 8082,
                    "upstream": [{
                        "host": "proxy.example.test",
                        "port": 8000,
                        "username": "[REDACTED]",
                        "password": "[REDACTED]",
                    }],
                },
            },
        },
        "proxy_state": {
            "ok": True,
            "data": {
                "engine_running": True,
                "system_proxy_enabled": True,
                "network_restore_pending": True,
                "state_migration_blocked": False,
                "stale_system_proxy": False,
                "orphaned_arvectum_pac": False,
                "configured_listeners": {
                    "http": {"host": "127.0.0.1", "port": 8080},
                    "socks5": {"host": "127.0.0.1", "port": 1080},
                    "pac": {"host": "127.0.0.1", "port": 8082},
                },
            },
        },
        "wininet": {"ok": True, "data": {"available": True, "values": {}}},
        "environment_proxy": {"ok": True, "data": {}},
        "listeners": {
            "ok": True,
            "data": {
                "http": {"listening": True, "port": 8080},
                "socks5": {"listening": True, "port": 1080},
                "pac": {"listening": True, "port": 8082},
                "pac_protocol_compatible": True,
            },
        },
        "network_interfaces": {"ok": True, "data": {"source": "win32_cim", "interfaces": []}},
        "recovery": {
            "ok": True,
            "data": {
                "network_restore_pending": True,
                "state_migration_blocked": False,
                "internet_backup": {"exists": True},
                "environment_backup": {"exists": True},
                "recovery_run": {
                    "readable": True,
                    "exists": False,
                    "value": "",
                    "classification": "absent",
                },
            },
        },
    }
    return {
        "schema": "arvectum.proxy.windows_diagnostics.v1",
        "collector_version": 1,
        "created_utc": "2026-08-16T00:00:00Z",
        "sections": sections,
    }


def check_map(report):
    return {item["id"]: item for item in report["checks"]}


class DoctorEvaluationTests(unittest.TestCase):
    def test_healthy_snapshot_is_pass_with_stable_schema_and_exit_code(self):
        report = doctor.evaluate_snapshot(healthy_snapshot())
        self.assertEqual(report["schema"], doctor.SCHEMA)
        self.assertEqual(report["overall"], doctor.PASS)
        self.assertEqual(report["exit_code"], 0)
        self.assertEqual(report["counts"][doctor.FAIL], 0)
        self.assertEqual(report["counts"][doctor.WARN], 0)
        self.assertEqual(len(report["checks"]), 11)
        self.assertEqual(check_map(report)["listeners.health"]["status"], doctor.PASS)

    def test_pending_recovery_is_fail_and_actionable_only_when_engine_is_stopped(self):
        snapshot = healthy_snapshot()
        snapshot["sections"]["proxy_state"]["data"]["engine_running"] = False
        snapshot["sections"]["proxy_state"]["data"]["system_proxy_enabled"] = False
        snapshot["sections"]["listeners"]["data"] = {
            "http": {"listening": False},
            "socks5": {"listening": False},
            "pac": {"listening": False},
            "pac_protocol_compatible": False,
        }
        report = doctor.evaluate_snapshot(snapshot)
        self.assertEqual(report["overall"], doctor.FAIL)
        self.assertEqual(report["exit_code"], 2)
        recovery = check_map(report)["state.recovery"]
        self.assertEqual(recovery["status"], doctor.FAIL)
        self.assertIn("Восстановить настройки сети", recovery["remediation"])

    def test_active_session_with_rollback_backups_is_healthy(self):
        report = doctor.evaluate_snapshot(healthy_snapshot())
        recovery = check_map(report)["state.recovery"]
        self.assertEqual(recovery["status"], doctor.PASS)
        self.assertIn("active proxy session", recovery["summary"])

    def test_engine_stopped_with_windows_proxy_enabled_is_fail(self):
        snapshot = healthy_snapshot()
        snapshot["sections"]["proxy_state"]["data"]["engine_running"] = False
        snapshot["sections"]["listeners"]["data"] = {
            "http": {"listening": False},
            "socks5": {"listening": False},
            "pac": {"listening": False},
            "pac_protocol_compatible": False,
        }
        report = doctor.evaluate_snapshot(snapshot)
        state = check_map(report)["state.engine_proxy"]
        self.assertEqual(state["status"], doctor.FAIL)
        self.assertEqual(report["overall"], doctor.FAIL)

    def test_stopped_engine_with_occupied_local_port_is_warn(self):
        snapshot = healthy_snapshot()
        snapshot["sections"]["proxy_state"]["data"]["engine_running"] = False
        snapshot["sections"]["proxy_state"]["data"]["system_proxy_enabled"] = False
        snapshot["sections"]["proxy_state"]["data"]["network_restore_pending"] = False
        snapshot["sections"]["recovery"]["data"]["network_restore_pending"] = False
        snapshot["sections"]["recovery"]["data"]["internet_backup"]["exists"] = False
        snapshot["sections"]["recovery"]["data"]["environment_backup"]["exists"] = False
        snapshot["sections"]["listeners"]["data"] = {
            "http": {"listening": True},
            "socks5": {"listening": False},
            "pac": {"listening": False},
            "pac_protocol_compatible": False,
        }
        report = doctor.evaluate_snapshot(snapshot)
        listener = check_map(report)["listeners.health"]
        self.assertEqual(listener["status"], doctor.WARN)
        self.assertEqual(report["overall"], doctor.WARN)
        self.assertEqual(report["exit_code"], 1)

    def test_macos_occupied_listener_reports_port_owner_and_action(self):
        snapshot = healthy_snapshot()
        snapshot["sections"]["system"]["data"] = {"platform": "Darwin", "windows": False}
        snapshot["sections"]["proxy_state"]["data"]["engine_running"] = False
        snapshot["sections"]["proxy_state"]["data"]["system_proxy_enabled"] = False
        snapshot["sections"]["proxy_state"]["data"]["network_restore_pending"] = False
        snapshot["sections"]["recovery"]["data"]["network_restore_pending"] = False
        snapshot["sections"]["recovery"]["data"]["internet_backup"]["exists"] = False
        snapshot["sections"]["recovery"]["data"]["environment_backup"]["exists"] = False
        snapshot["sections"]["listeners"]["data"] = {
            "http": {
                "listening": True,
                "port": 8080,
                "owners": [{"pid": 1139, "command": "Python"}],
            },
            "socks5": {"listening": False, "port": 1080},
            "pac": {"listening": False, "port": 8082},
            "pac_protocol_compatible": False,
        }
        report = doctor.evaluate_snapshot(snapshot)
        listener = check_map(report)["listeners.health"]
        self.assertEqual(listener["status"], doctor.WARN)
        self.assertIn("8080", listener["remediation"])
        self.assertIn("Python", listener["remediation"])
        self.assertIn("PID 1139", listener["remediation"])
        self.assertIn("18080 / 11080 / 18082", listener["remediation"])
        self.assertEqual(check_map(report)["platform.macos"]["status"], doctor.PASS)
        self.assertEqual(report["overall"], doctor.WARN)

    def test_invalid_or_colliding_ports_are_fail(self):
        snapshot = healthy_snapshot()
        settings = snapshot["sections"]["application"]["data"]["settings"]
        settings["local_socks_port"] = 8080
        settings["local_pac_port"] = 70000
        report = doctor.evaluate_snapshot(snapshot)
        ports = check_map(report)["configuration.ports"]
        self.assertEqual(ports["status"], doctor.FAIL)
        self.assertTrue(ports["details"]["collisions"])
        self.assertIn("pac", ports["details"]["invalid"])

    def test_missing_upstream_is_warn_not_fail(self):
        snapshot = healthy_snapshot()
        snapshot["sections"]["application"]["data"]["settings"]["upstream"] = []
        report = doctor.evaluate_snapshot(snapshot)
        self.assertEqual(check_map(report)["configuration.upstream"]["status"], doctor.WARN)
        self.assertEqual(report["overall"], doctor.WARN)

    def test_optional_collector_failure_is_warn_and_error_secret_is_redacted_again(self):
        snapshot = healthy_snapshot()
        secret = "doctor-collector-leak-secret"
        snapshot["sections"]["network_interfaces"] = {
            "ok": False,
            "error": "RuntimeError: password=%s" % secret,
        }
        report = doctor.evaluate_snapshot(snapshot)
        self.assertEqual(check_map(report)["collector.integrity"]["status"], doctor.WARN)
        raw = json.dumps(report, ensure_ascii=False)
        self.assertNotIn(secret, raw)

    def test_essential_collector_failure_is_fail_and_propagated_error_is_redacted(self):
        snapshot = healthy_snapshot()
        secret = "doctor-essential-leak-secret"
        snapshot["sections"]["listeners"] = {
            "ok": False,
            "error": "RuntimeError: password=%s" % secret,
        }
        report = doctor.evaluate_snapshot(snapshot)
        integrity = check_map(report)["collector.integrity"]
        self.assertEqual(integrity["status"], doctor.FAIL)
        self.assertIn("listeners", integrity["details"]["essential_failed"])
        raw = json.dumps(report, ensure_ascii=False)
        self.assertNotIn(secret, raw)
        self.assertIn("[REDACTED]", raw)

    def test_supported_non_windows_platforms_are_pass(self):
        for platform_name, check_id in (("Darwin", "platform.macos"), ("Linux", "platform.linux")):
            with self.subTest(platform_name=platform_name):
                snapshot = healthy_snapshot()
                snapshot["sections"]["system"]["data"] = {
                    "platform": platform_name,
                    "windows": False,
                }
                report = doctor.evaluate_snapshot(snapshot)
                self.assertEqual(check_map(report)[check_id]["status"], doctor.PASS)
                self.assertEqual(report["overall"], doctor.PASS)

    def test_unknown_platform_is_fail(self):
        snapshot = healthy_snapshot()
        snapshot["sections"]["system"]["data"] = {"platform": "Plan9", "windows": False}
        report = doctor.evaluate_snapshot(snapshot)
        self.assertEqual(check_map(report)["platform.supported"]["status"], doctor.FAIL)
        self.assertEqual(report["overall"], doctor.FAIL)

    def test_source_schema_mismatch_is_fail(self):
        snapshot = healthy_snapshot()
        snapshot["schema"] = "arvectum.proxy.windows_diagnostics.v0"
        report = doctor.evaluate_snapshot(snapshot)
        integrity = check_map(report)["collector.integrity"]
        self.assertEqual(integrity["status"], doctor.FAIL)
        self.assertEqual(integrity["details"]["expected_schema"], doctor.diagnostics.SCHEMA)
        self.assertEqual(integrity["details"]["source_schema"], "arvectum.proxy.windows_diagnostics.v0")

    def test_foreign_recovery_autostart_is_warn_and_never_treated_as_ours(self):
        snapshot = healthy_snapshot()
        snapshot["sections"]["recovery"]["data"]["recovery_run"] = {
            "readable": True,
            "exists": True,
            "value": "[REDACTED]",
            "classification": "FOREIGN",
        }
        report = doctor.evaluate_snapshot(snapshot)
        recovery_run = check_map(report)["recovery.autostart"]
        self.assertEqual(recovery_run["status"], doctor.WARN)
        self.assertIn("left untouched", recovery_run["summary"])
        self.assertEqual(report["overall"], doctor.WARN)

    def test_legacy_recovery_autostart_is_warn_even_during_active_session(self):
        snapshot = healthy_snapshot()
        snapshot["sections"]["recovery"]["data"]["recovery_run"] = {
            "readable": True,
            "exists": True,
            "value": "[REDACTED]",
            "classification": "LEGACY_ARVECTUM",
        }
        report = doctor.evaluate_snapshot(snapshot)
        recovery_run = check_map(report)["recovery.autostart"]
        self.assertEqual(recovery_run["status"], doctor.WARN)
        self.assertIn("no longer be required", recovery_run["summary"])
        self.assertEqual(report["overall"], doctor.WARN)

    def test_stale_or_orphaned_pac_is_fail(self):
        for field in ("stale_system_proxy", "orphaned_arvectum_pac"):
            with self.subTest(field=field):
                snapshot = healthy_snapshot()
                snapshot["sections"]["proxy_state"]["data"][field] = True
                report = doctor.evaluate_snapshot(snapshot)
                self.assertEqual(check_map(report)["state.pac_ownership"]["status"], doctor.FAIL)

    def test_run_doctor_uses_read_only_snapshot_collector(self):
        snapshot = healthy_snapshot()
        with patch.object(doctor.diagnostics, "collect_snapshot", return_value=snapshot) as collect:
            report = doctor.run_doctor()
        collect.assert_called_once_with()
        self.assertEqual(report["overall"], doctor.PASS)

    def test_json_report_is_atomic_and_machine_readable(self):
        report = doctor.evaluate_snapshot(healthy_snapshot())
        with tempfile.TemporaryDirectory() as td:
            target = os.path.join(td, "nested", "doctor.json")
            result = doctor.write_json_report(target, report)
            self.assertEqual(result, os.path.abspath(target))
            self.assertFalse(os.path.exists(target + ".tmp-%d" % os.getpid()))
            with open(target, "r", encoding="utf-8") as stream:
                loaded = json.load(stream)
            self.assertEqual(loaded["schema"], doctor.SCHEMA)
            self.assertEqual(loaded["overall"], doctor.PASS)

    def test_cli_exit_codes_and_json_output(self):
        report = doctor.evaluate_snapshot(healthy_snapshot())
        output = io.StringIO()
        with patch.object(doctor, "run_doctor", return_value=report), patch("sys.stdout", output):
            code = doctor.main(["--json"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(output.getvalue())["overall"], doctor.PASS)

    def test_windowed_packaged_mode_can_write_json_when_stdout_is_none(self):
        report = doctor.evaluate_snapshot(healthy_snapshot())
        with tempfile.TemporaryDirectory() as td:
            target = os.path.join(td, "doctor.json")
            with patch.object(doctor, "run_doctor", return_value=report), patch("sys.stdout", None):
                code = doctor.main(["--json", "--output", target])
            self.assertEqual(code, 0)
            with open(target, "r", encoding="utf-8") as stream:
                loaded = json.load(stream)
            self.assertEqual(loaded["schema"], doctor.SCHEMA)
            self.assertEqual(loaded["overall"], doctor.PASS)


if __name__ == "__main__":
    unittest.main()
