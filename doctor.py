# -*- coding: utf-8 -*-
"""Read-only automated self-diagnostics for Arvectum Proxy Launcher.

support-bundle diagnostics evaluates the redacted platform diagnostics snapshot and turns it into a
stable PASS/WARN/FAIL health report. The Doctor never changes proxy, WinINET,
environment, recovery, autostart, or network state. It performs no external
network requests; localhost listener observations come from the diagnostics
collector.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
import sys

from secret_redaction import REDACTED, redact_text, redact_value
import windows_diagnostics as diagnostics


SCHEMA = "arvectum.proxy.doctor.v1"
DOCTOR_VERSION = 1

PASS = "PASS"
WARN = "WARN"
FAIL = "FAIL"
_STATUS_RANK = {PASS: 0, WARN: 1, FAIL: 2}
EXIT_CODES = {PASS: 0, WARN: 1, FAIL: 2}

REQUIRED_SECTIONS = (
    "system", "application", "proxy_state", "wininet", "environment_proxy",
    "listeners", "network_interfaces", "recovery",
)
ESSENTIAL_SECTIONS = {"system", "application", "proxy_state", "listeners", "recovery"}


def _utc_timestamp():
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _safe_dict(value):
    return value if isinstance(value, dict) else {}


def _safe_list(value):
    return value if isinstance(value, list) else []


def _section(snapshot, name):
    section = _safe_dict(_safe_dict(snapshot).get("sections", {})).get(name)
    if not isinstance(section, dict):
        return False, {}, "section is missing"
    if not section.get("ok"):
        return False, {}, str(section.get("error") or "section collection failed")
    return True, _safe_dict(section.get("data")), ""


def _check(check_id, status, summary, details=None, remediation=None):
    status = status if status in _STATUS_RANK else FAIL
    result = {"id": str(check_id), "status": status, "summary": str(summary)}
    if details not in (None, {}, [], ""):
        result["details"] = details
    if remediation:
        result["remediation"] = str(remediation)
    return result


def _valid_port(value):
    try:
        port = int(value)
    except (TypeError, ValueError):
        return None
    return port if 1 <= port <= 65535 else None


def _collector_integrity(snapshot):
    source_schema = _safe_dict(snapshot).get("schema")
    if source_schema != diagnostics.SCHEMA:
        return _check(
            "collector.integrity", FAIL, "Diagnostics snapshot schema is unsupported",
            {"expected_schema": diagnostics.SCHEMA, "source_schema": source_schema},
            "Run Doctor with the matching platform diagnostics collector version.",
        )
    sections = _safe_dict(_safe_dict(snapshot).get("sections", {}))
    failed = []
    for required in REQUIRED_SECTIONS:
        section = sections.get(required)
        if not isinstance(section, dict) or not section.get("ok"):
            failed.append(required)
    if not failed:
        return _check("collector.integrity", PASS, "All diagnostics sections were collected")
    essential_failed = sorted(set(failed) & ESSENTIAL_SECTIONS)
    return _check(
        "collector.integrity",
        FAIL if essential_failed else WARN,
        "Diagnostics snapshot is incomplete",
        {"failed_sections": sorted(set(failed)), "essential_failed": essential_failed},
        "Run Doctor again; if the same section fails, create an platform diagnostics support bundle for support.",
    )


def _redaction_self_test():
    password = "apl-doctor-password-sentinel-94f1"
    token = "apl-doctor-token-sentinel-8f24c7c6"
    raw = (
        "proxy=http://doctor:%s@proxy.example.test:8080 "
        "Authorization: Bearer %s password=%s"
    ) % (password, token, password)
    clean = redact_text(raw)
    ok = password not in clean and token not in clean and REDACTED in clean and "proxy.example.test:8080" in clean
    if ok:
        return _check("redaction.self_test", PASS, "Secret redaction self-test passed")
    return _check(
        "redaction.self_test", FAIL, "Secret redaction self-test failed",
        remediation="Do not share diagnostics until the redaction layer is repaired.",
    )


def _snapshot_platform(snapshot):
    ok, system, _error = _section(snapshot, "system")
    if not ok:
        return ""
    return str(system.get("platform") or "").strip()


def _platform_check(snapshot):
    ok, system, error = _section(snapshot, "system")
    if not ok:
        return _check("platform.supported", FAIL, "Platform state is unavailable", error)

    platform_name = str(system.get("platform") or "").strip()
    lowered = platform_name.lower()
    if system.get("windows") is True or lowered == "windows":
        return _check("platform.windows", PASS, "Windows platform detected")
    if lowered in ("darwin", "macos", "mac"):
        return _check("platform.macos", PASS, "macOS platform detected")
    if lowered == "linux":
        return _check("platform.linux", PASS, "Linux platform detected")
    return _check(
        "platform.supported", FAIL, "Unsupported desktop platform",
        {"platform": platform_name or None},
        "Use a supported Windows, macOS or Linux build of Arvectum Proxy Launcher.",
    )


def _ports_check(snapshot):
    app_ok, application, app_error = _section(snapshot, "application")
    proxy_ok, proxy_state, proxy_error = _section(snapshot, "proxy_state")
    if not app_ok or not proxy_ok:
        return _check(
            "configuration.ports", FAIL, "Configured listener ports are unavailable",
            {"application": app_error or "ok", "proxy_state": proxy_error or "ok"},
        )
    settings = _safe_dict(application.get("settings"))
    listeners = _safe_dict(proxy_state.get("configured_listeners"))
    values = {
        "http": settings.get("local_http_port", _safe_dict(listeners.get("http")).get("port")),
        "socks5": settings.get("local_socks_port", _safe_dict(listeners.get("socks5")).get("port")),
        "pac": settings.get("local_pac_port", _safe_dict(listeners.get("pac")).get("port")),
    }
    normalized = {name: _valid_port(value) for name, value in values.items()}
    invalid = sorted(name for name, value in normalized.items() if value is None)
    valid_values = [value for value in normalized.values() if value is not None]
    collisions = len(valid_values) != len(set(valid_values))
    if invalid or collisions:
        return _check(
            "configuration.ports", FAIL, "Local listener port configuration is invalid",
            {"ports": normalized, "invalid": invalid, "collisions": collisions},
            "Use three distinct TCP ports in range 1..65535 for HTTP, SOCKS5 and PAC.",
        )
    return _check("configuration.ports", PASS, "Local listener ports are valid and distinct", normalized)


def _upstream_check(snapshot):
    ok, application, error = _section(snapshot, "application")
    if not ok:
        return _check("configuration.upstream", FAIL, "Proxy settings are unavailable", error)
    settings = _safe_dict(application.get("settings"))
    upstreams = settings.get("upstream")
    if not isinstance(upstreams, list):
        upstreams = []
    usable = []
    invalid = []
    for index, item in enumerate(upstreams):
        item = _safe_dict(item)
        host = str(item.get("host") or "").strip()
        if not host:
            continue
        port = _valid_port(item.get("port"))
        if port is None:
            invalid.append(index)
        else:
            usable.append({"index": index, "host": host, "port": port})
    if invalid:
        return _check(
            "configuration.upstream", FAIL, "One or more upstream proxies have an invalid port",
            {"invalid_indexes": invalid},
            "Correct the upstream host/port settings before enabling the proxy.",
        )
    if not usable:
        return _check(
            "configuration.upstream", WARN, "No usable upstream proxy is configured",
            remediation="Configure at least one upstream proxy before enabling Proxy Launcher.",
        )
    return _check(
        "configuration.upstream", PASS, "At least one upstream proxy is configured",
        {"configured": len(usable), "endpoints": usable},
    )


def _migration_check(snapshot):
    ok, proxy_state, error = _section(snapshot, "proxy_state")
    if not ok:
        return _check("state.migration", FAIL, "Migration state is unavailable", error)
    if proxy_state.get("state_migration_blocked"):
        return _check(
            "state.migration", FAIL, "Runtime state migration is blocked by a conflict",
            remediation="Resolve the state migration conflict before starting the proxy.",
        )
    return _check("state.migration", PASS, "Runtime state migration is not blocked")


def _recovery_check(snapshot):
    recovery_ok, recovery, recovery_error = _section(snapshot, "recovery")
    proxy_ok, proxy_state, proxy_error = _section(snapshot, "proxy_state")
    if not recovery_ok or not proxy_ok:
        return _check(
            "state.recovery", FAIL, "Recovery state is unavailable",
            {"recovery": recovery_error or "ok", "proxy_state": proxy_error or "ok"},
        )
    pending = bool(recovery.get("network_restore_pending"))
    running = bool(proxy_state.get("engine_running"))
    backups = {
        "internet_backup": bool(_safe_dict(recovery.get("internet_backup")).get("exists")),
        "environment_backup": bool(_safe_dict(recovery.get("environment_backup")).get("exists")),
        "engine_running": running,
    }
    if pending and not running:
        return _check(
            "state.recovery", FAIL, "Network rollback is pending from a previous proxy session",
            backups,
            "Use “Восстановить настройки сети” and confirm Doctor no longer reports pending recovery before starting the proxy.",
        )
    if pending and running:
        return _check(
            "state.recovery", PASS,
            "Rollback backups are present for the active proxy session", backups,
        )
    return _check("state.recovery", PASS, "No pending network rollback", backups)


def _engine_proxy_check(snapshot):
    ok, proxy_state, error = _section(snapshot, "proxy_state")
    if not ok:
        return _check("state.engine_proxy", FAIL, "Engine/system-proxy state is unavailable", error)
    running = bool(proxy_state.get("engine_running"))
    enabled = bool(proxy_state.get("system_proxy_enabled"))
    details = {"engine_running": running, "system_proxy_enabled": enabled}
    if enabled and not running:
        return _check(
            "state.engine_proxy", FAIL,
            "System proxy is enabled but the Proxy Launcher engine is not running",
            details, "Restore network settings before attempting a new start.",
        )
    if running and not enabled:
        return _check(
            "state.engine_proxy", WARN,
            "Proxy engine is running but the system PAC is not enabled",
            details, "Re-enable the proxy or stop the engine cleanly if this state is not intentional.",
        )
    return _check("state.engine_proxy", PASS, "Engine and system proxy state are consistent", details)


def _pac_ownership_check(snapshot):
    ok, proxy_state, error = _section(snapshot, "proxy_state")
    if not ok:
        return _check("state.pac_ownership", FAIL, "PAC ownership state is unavailable", error)
    stale = bool(proxy_state.get("stale_system_proxy"))
    orphaned = bool(proxy_state.get("orphaned_arvectum_pac"))
    if stale:
        return _check(
            "state.pac_ownership", FAIL,
            "The system still references an Arvectum PAC whose ownership cannot be proven",
            {"stale_system_proxy": stale, "orphaned_arvectum_pac": orphaned},
            "Do not reset unrelated system proxy settings automatically; inspect the support bundle or open the installed Launcher.",
        )
    if orphaned:
        return _check(
            "state.pac_ownership", FAIL,
            "An orphaned Arvectum PAC is active while the engine is stopped",
            {"stale_system_proxy": stale, "orphaned_arvectum_pac": orphaned},
            "Use “Удалить старый PAC и продолжить” in the Launcher after reviewing the ownership warning.",
        )
    return _check("state.pac_ownership", PASS, "No stale or orphaned Arvectum PAC is detected")


def _listeners_check(snapshot):
    proxy_ok, proxy_state, proxy_error = _section(snapshot, "proxy_state")
    listeners_ok, listeners, listeners_error = _section(snapshot, "listeners")
    if not proxy_ok or not listeners_ok:
        return _check(
            "listeners.health", FAIL, "Local listener health is unavailable",
            {"proxy_state": proxy_error or "ok", "listeners": listeners_error or "ok"},
        )
    running = bool(proxy_state.get("engine_running"))
    observed = {}
    listener_details = {}
    for name in ("http", "socks5", "pac"):
        raw = _safe_dict(listeners.get(name))
        observed[name] = bool(raw.get("listening"))
        listener_details[name] = {
            "listening": observed[name],
            "port": _valid_port(raw.get("port")),
            "owners": _safe_list(raw.get("owners")),
        }
    if running:
        missing = sorted(name for name, listening in observed.items() if not listening)
        protocol_ok = listeners.get("pac_protocol_compatible")
        if missing or protocol_ok is False:
            return _check(
                "listeners.health", FAIL,
                "Proxy engine is running but required localhost listeners are unhealthy",
                {
                    "listeners": observed,
                    "listener_details": listener_details,
                    "missing": missing,
                    "pac_protocol_compatible": protocol_ok,
                },
                "Restart Proxy Launcher; if listeners remain unhealthy, create a support bundle.",
            )
        return _check(
            "listeners.health", PASS, "All required localhost listeners are reachable",
            {"listeners": observed, "listener_details": listener_details},
        )

    occupied = sorted(name for name, listening in observed.items() if listening)
    if occupied:
        occupied_details = {name: listener_details[name] for name in occupied}
        occupied_ports = [
            item["port"] for item in occupied_details.values() if item.get("port") is not None
        ]
        platform_name = _snapshot_platform(snapshot).lower()
        if platform_name in ("darwin", "macos", "mac"):
            owner_labels = []
            for name in occupied:
                item = occupied_details[name]
                port = item.get("port")
                owners = item.get("owners") or []
                if owners:
                    owner = _safe_dict(owners[0])
                    process = str(owner.get("command") or "процесс")
                    pid = owner.get("pid")
                    label = "%s %s — %s%s" % (
                        name.upper(), port or "?", process,
                        " (PID %s)" % pid if pid is not None else "",
                    )
                else:
                    label = "%s %s" % (name.upper(), port or "?")
                owner_labels.append(label)
            remediation = (
                "На macOS локальные порты уже заняты: %s. Закройте конфликтующий процесс "
                "или в «Прокси…» → «Локальные порты» укажите свободные порты "
                "(например 18080 / 11080 / 18082), затем повторите диагностику."
            ) % "; ".join(owner_labels)
        else:
            remediation = (
                "Free the occupied local ports %s or choose different local listener ports "
                "before starting Proxy Launcher."
            ) % ", ".join(str(p) for p in occupied_ports)
        summary = (
            "Локальные порты заняты, пока Proxy Launcher выключен"
            if platform_name in ("darwin", "macos", "mac")
            else "Configured localhost ports are already listening while the engine is stopped"
        )
        return _check(
            "listeners.health", WARN,
            summary,
            {
                "listeners": observed,
                "occupied": occupied,
                "occupied_details": occupied_details,
            },
            remediation,
        )
    return _check(
        "listeners.health", PASS, "Configured localhost ports are free while the engine is stopped",
        {"listeners": observed, "listener_details": listener_details},
    )


def _recovery_autostart_check(snapshot):
    ok, recovery, error = _section(snapshot, "recovery")
    if not ok:
        return _check("recovery.autostart", WARN, "Recovery autostart state is unavailable", error)
    run = recovery.get("recovery_run")
    if not isinstance(run, dict):
        return _check("recovery.autostart", PASS, "No recovery autostart anomaly was reported")
    if run.get("readable") is False:
        return _check(
            "recovery.autostart", WARN, "Recovery autostart registry value could not be read",
            remediation="Check the Windows Run entry if recovery behavior is unexpected.",
        )
    exists = bool(run.get("exists"))
    classification = str(run.get("classification") or "")
    lowered = classification.lower()
    if not exists:
        return _check(
            "recovery.autostart", PASS, "No legacy recovery-autostart entry is present",
            {"exists": False, "classification": classification},
        )
    if any(word in lowered for word in ("foreign", "conflict", "unsafe", "unverified")):
        return _check(
            "recovery.autostart", WARN,
            "A foreign recovery-autostart entry is present and was left untouched",
            {"classification": classification},
            "Do not delete or overwrite a foreign Run entry automatically; inspect ownership only if startup behavior is unexpected.",
        )
    return _check(
        "recovery.autostart", WARN,
        "A legacy or owned recovery-autostart entry remains and should no longer be required",
        {"classification": classification},
        "Restart the Launcher and review the recovery Run entry if it persists; never remove an entry whose ownership is uncertain.",
    )


def evaluate_snapshot(snapshot):
    """Evaluate one platform diagnostics snapshot without accessing OS/network state."""
    checks = [
        _collector_integrity(snapshot),
        _redaction_self_test(),
        _platform_check(snapshot),
        _ports_check(snapshot),
        _upstream_check(snapshot),
        _migration_check(snapshot),
        _recovery_check(snapshot),
        _engine_proxy_check(snapshot),
        _pac_ownership_check(snapshot),
        _listeners_check(snapshot),
        _recovery_autostart_check(snapshot),
    ]
    overall = max((item["status"] for item in checks), key=lambda value: _STATUS_RANK[value])
    counts = {status: sum(1 for item in checks if item["status"] == status) for status in (PASS, WARN, FAIL)}
    actions = []
    for item in checks:
        remediation = item.get("remediation")
        if item["status"] != PASS and remediation and remediation not in actions:
            actions.append(remediation)
    app_ok, app, _ = _section(snapshot, "application")
    report = {
        "schema": SCHEMA,
        "doctor_version": DOCTOR_VERSION,
        "created_utc": _utc_timestamp(),
        "source_schema": _safe_dict(snapshot).get("schema"),
        "overall": overall,
        "exit_code": EXIT_CODES[overall],
        "counts": counts,
        "application": {
            "app_version": app.get("app_version") if app_ok else None,
            "engineering_milestone": app.get("engineering_milestone") if app_ok else None,
        },
        "checks": checks,
        "recommended_actions": actions,
    }
    # Defense in depth: the platform diagnostics snapshot is already redacted, but all
    # Doctor output passes the same centralized diagnostic secret redaction layer again.
    return redact_value(report, max_depth=16, max_items=500, string_limit=8192)


def run_doctor(snapshot=None):
    """Collect current read-only diagnostics and return a Doctor report."""
    return evaluate_snapshot(diagnostics.collect_snapshot() if snapshot is None else snapshot)


def format_report(report, include_pass=True, max_checks=None):
    report = _safe_dict(report)
    counts = _safe_dict(report.get("counts"))
    lines = [
        "Arvectum Proxy Launcher Doctor",
        "Overall: %s (PASS %s / WARN %s / FAIL %s)" % (
            report.get("overall", FAIL), counts.get(PASS, 0), counts.get(WARN, 0), counts.get(FAIL, 0)
        ),
    ]
    checks = _safe_list(report.get("checks"))
    if not include_pass:
        checks = [item for item in checks if _safe_dict(item).get("status") != PASS]
    if max_checks is not None:
        checks = checks[:max(0, int(max_checks))]
    for item in checks:
        item = _safe_dict(item)
        lines.append("[%s] %s — %s" % (
            item.get("status", FAIL), item.get("id", "unknown"), item.get("summary", "")
        ))
    actions = _safe_list(report.get("recommended_actions"))
    if actions:
        lines.extend(["", "Recommended actions:"])
        lines.extend("- %s" % action for action in actions)
    return "\n".join(lines)


def write_json_report(path, report):
    """Atomically write a user-requested Doctor JSON report without app-state changes."""
    target = os.path.abspath(os.fspath(path))
    parent = os.path.dirname(target)
    if parent:
        os.makedirs(parent, exist_ok=True)
    temporary = "%s.tmp-%d" % (target, os.getpid())
    payload = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    try:
        with open(temporary, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(payload)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            try:
                os.remove(temporary)
            except OSError:
                pass
    return target


def main(argv=None):
    parser = argparse.ArgumentParser(description="Arvectum Proxy Launcher read-only Doctor")
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    parser.add_argument("--output", metavar="PATH", help="atomically write the JSON report to PATH")
    args = parser.parse_args(argv)
    report = run_doctor()
    if args.output:
        write_json_report(args.output, report)
    stdout = getattr(sys, "stdout", None)
    if args.json and stdout is not None:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True), file=stdout)
    elif not args.output and stdout is not None:
        print(format_report(report), file=stdout)
    return int(report.get("exit_code", 2))


if __name__ == "__main__":
    sys.exit(main())
