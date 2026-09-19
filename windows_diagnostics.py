# -*- coding: utf-8 -*-
"""Windows support-bundle collector for Arvectum Proxy Launcher.

platform diagnostics collects read-only operating-system/application/network state into
one redacted ZIP.  Collection is deliberately best-effort: one broken data
source is recorded as a failed section and never prevents the remaining bundle
from being produced.
"""

from collections import deque
from datetime import datetime, timezone
import json
import os
import platform
import shutil
import socket
import subprocess
import sys
import zipfile

import proxy_core as core
from secret_redaction import redact_text, redact_value


SCHEMA = "arvectum.proxy.windows_diagnostics.v1"
COLLECTOR_VERSION = 1
LOG_ROTATIONS = 3
LOG_MAX_LINES = 2000
SECTION_MAX_DEPTH = 12
SECTION_MAX_ITEMS = 250
SECTION_STRING_LIMIT = 8192


def _utc_timestamp():
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _safe_filename_timestamp():
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%SZ")


def _sanitize(value):
    return redact_value(
        value,
        max_depth=SECTION_MAX_DEPTH,
        max_items=SECTION_MAX_ITEMS,
        string_limit=SECTION_STRING_LIMIT,
    )


def _error_text(exc):
    return redact_text("%s: %s" % (type(exc).__name__, exc), limit=2048)


def _safe_section(collector):
    try:
        return {"ok": True, "data": collector()}
    except Exception as exc:
        return {"ok": False, "error": _error_text(exc)}


def _path_state(path):
    value = os.fspath(path)
    result = {
        "path": value,
        "exists": os.path.exists(value),
        "is_file": os.path.isfile(value),
        "is_dir": os.path.isdir(value),
    }
    if result["is_file"]:
        try:
            stat = os.stat(value)
            result["size_bytes"] = stat.st_size
            result["mtime_utc"] = datetime.fromtimestamp(
                stat.st_mtime, timezone.utc
            ).isoformat(timespec="seconds").replace("+00:00", "Z")
        except OSError as exc:
            result["stat_error"] = _error_text(exc)
    return result


def _collect_system():
    return {
        "platform": platform.system(),
        "release": platform.release(),
        "version": platform.version(),
        "machine": platform.machine(),
        "architecture": platform.architecture()[0],
        "hostname": socket.gethostname(),
        "python_version": platform.python_version(),
        "python_executable": sys.executable,
        "frozen": bool(getattr(sys, "frozen", False)),
        "windows": bool(core.is_windows()),
    }


def _collect_application():
    settings = core.load_settings(migrate_legacy=False)
    return {
        "app_version": core.APP_VERSION,
        "engineering_milestone": core.ENGINEERING_MILESTONE,
        "settings": settings,
        "no_proxy": core.load_no_proxy(),
        "paths": {
            "install_dir": _path_state(core.install_dir()),
            "data_dir": _path_state(core.data_dir()),
            "stable_app_dir": _path_state(core.stable_app_dir()),
            "stable_app_exe": _path_state(core.stable_app_exe()),
            "settings": _path_state(core.settings_path()),
            "settings_lastgood": _path_state(core.settings_backup_path()) if hasattr(core, "settings_backup_path") else {"available": False},
            "config_recovery": _path_state(core.config_recovery_path()) if hasattr(core, "config_recovery_path") else {"available": False},
            "config_quarantine": _path_state(core.config_quarantine_dir()) if hasattr(core, "config_quarantine_dir") else {"available": False},
            "no_proxy": _path_state(core.no_proxy_path()),
            "pid": _path_state(core.pid_path()),
            "log": _path_state(core.log_path()),
        },
    }


def _collect_proxy_state():
    settings = core.load_settings(migrate_legacy=False)
    return {
        "engine_running": bool(core.is_running()),
        "system_proxy_enabled": bool(core.system_proxy_enabled()),
        "network_restore_pending": bool(core.network_restore_pending()),
        "state_migration_blocked": bool(core.state_migration_blocked()),
        "stale_system_proxy": bool(core.stale_system_proxy()),
        "orphaned_arvectum_pac": bool(core.orphaned_arvectum_pac()),
        "pac_url": core.pac_url(settings),
        "configured_listeners": {
            "http": {"host": "127.0.0.1", "port": int(settings.get("local_http_port", 8080))},
            "socks5": {"host": "127.0.0.1", "port": int(settings.get("local_socks_port", 1080))},
            "pac": {"host": "127.0.0.1", "port": int(settings.get("local_pac_port", 8082))},
        },
    }


def _collect_wininet():
    if not core.is_windows():
        return {"available": False, "reason": "not_windows", "values": {}}
    return {"available": True, "values": core._read_internet_settings()}


def _collect_environment_proxy():
    names = tuple(getattr(core, "_PROXY_ENV_NAMES", (
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY"
    )))
    result = {}
    for name in names:
        item = {
            "process": {
                "exists": name in os.environ,
                "value": os.environ.get(name, ""),
            }
        }
        if core.is_windows():
            try:
                exists, value = core._read_user_env(name)
                item["user"] = {"exists": bool(exists), "value": value}
            except Exception as exc:
                item["user"] = {"ok": False, "error": _error_text(exc)}
        result[name] = item
    return result


def _macos_listener_owners(port):
    """Best-effort read-only owner lookup for a listening localhost TCP port."""
    if sys.platform != "darwin":
        return []
    lsof = "/usr/sbin/lsof"
    if not os.path.isfile(lsof):
        return []
    try:
        result = subprocess.run(
            [lsof, "-nP", "-iTCP:%d" % int(port), "-sTCP:LISTEN", "-Fpc"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=3,
            check=False,
        )
    except Exception:
        return []
    if result.returncode not in (0, 1):
        return []

    owners = []
    current = None
    for raw in (result.stdout or "").splitlines():
        if not raw:
            continue
        tag, value = raw[:1], raw[1:]
        if tag == "p":
            if current and current.get("pid") is not None:
                owners.append(current)
            try:
                pid = int(value)
            except (TypeError, ValueError):
                pid = None
            current = {"pid": pid}
        elif tag == "c" and current is not None:
            current["command"] = redact_text(value, limit=256)
    if current and current.get("pid") is not None:
        owners.append(current)

    deduped = []
    seen = set()
    for item in owners:
        key = (item.get("pid"), item.get("command"))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(item)
    return deduped[:8]


def _probe_listener(port, timeout=0.25):
    try:
        port = int(port)
    except (TypeError, ValueError):
        return {"listening": False, "error": "invalid_port", "port": port}
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.settimeout(timeout)
        listening = sock.connect_ex(("127.0.0.1", port)) == 0
        result = {
            "host": "127.0.0.1",
            "port": port,
            "listening": listening,
        }
        if listening:
            owners = _macos_listener_owners(port)
            if owners:
                result["owners"] = owners
        return result
    except OSError as exc:
        return {
            "host": "127.0.0.1",
            "port": port,
            "listening": False,
            "error": _error_text(exc),
        }
    finally:
        try:
            sock.close()
        except Exception:
            pass


def _collect_listeners():
    settings = core.load_settings(migrate_legacy=False)
    ports = {
        "http": settings.get("local_http_port", 8080),
        "socks5": settings.get("local_socks_port", 1080),
        "pac": settings.get("local_pac_port", 8082),
    }
    result = {name: _probe_listener(port) for name, port in ports.items()}
    try:
        result["pac_protocol_compatible"] = bool(core.proxy_listener_active())
    except Exception as exc:
        result["pac_protocol_compatible_error"] = _error_text(exc)
    return result


def _interface_fallback(reason=None):
    result = {
        "source": "unavailable",
        "hostname": socket.gethostname(),
        "interfaces": [],
    }
    if reason:
        result["fallback_reason"] = redact_text(reason, limit=2048)
    return result


def _powershell_executable():
    for candidate in ("powershell.exe", "pwsh.exe"):
        path = shutil.which(candidate)
        if path:
            return path
    return None


def _collect_network_interfaces():
    if not core.is_windows():
        return _interface_fallback("not_windows")
    powershell = _powershell_executable()
    if not powershell:
        return _interface_fallback("PowerShell executable not found")
    script = (
        "$ErrorActionPreference='Stop';"
        "[Console]::OutputEncoding=[Text.Encoding]::UTF8;"
        "$items=@(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter \"IPEnabled=True\" | "
        "Select-Object Description,InterfaceIndex,IPAddress,IPSubnet,DefaultIPGateway,"
        "DNSServerSearchOrder,DHCPEnabled,DHCPServer);"
        "ConvertTo-Json -InputObject $items -Depth 4 -Compress"
    )
    try:
        proc = subprocess.run(
            [powershell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=8,
            check=False,
        )
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr.strip() or "PowerShell interface query failed")
        text = proc.stdout.strip()
        items = json.loads(text or "[]")
        if isinstance(items, dict):
            items = [items]
        return {"source": "win32_cim", "interfaces": items}
    except Exception as exc:
        return _interface_fallback(_error_text(exc))


def _collect_recovery_state():
    result = {
        "network_restore_pending": bool(core.network_restore_pending()),
        "state_migration_blocked": bool(core.state_migration_blocked()),
        "migration_error": _path_state(core.migration_error_path()),
        "config_recovery": _path_state(core.config_recovery_path()) if hasattr(core, "config_recovery_path") else {"available": False},
        "settings_lastgood": _path_state(core.settings_backup_path()) if hasattr(core, "settings_backup_path") else {"available": False},
        "config_quarantine": _path_state(core.config_quarantine_dir()) if hasattr(core, "config_quarantine_dir") else {"available": False},
        "internet_backup": _path_state(core._internet_backup_path()),
        "environment_backup": _path_state(core._env_backup_path()),
    }
    if core.is_windows():
        try:
            run_value = core._get_recovery_run_value()
            if run_value is False:
                result["recovery_run"] = {"readable": False}
            else:
                result["recovery_run"] = {
                    "readable": True,
                    "exists": run_value is not None,
                    "value": run_value or "",
                    "classification": core.classify_recovery_autostart(run_value),
                }
        except Exception as exc:
            result["recovery_run"] = {"readable": False, "error": _error_text(exc)}
    return result


_SECTION_COLLECTORS = (
    ("system", _collect_system),
    ("application", _collect_application),
    ("proxy_state", _collect_proxy_state),
    ("wininet", _collect_wininet),
    ("environment_proxy", _collect_environment_proxy),
    ("listeners", _collect_listeners),
    ("network_interfaces", _collect_network_interfaces),
    ("recovery", _collect_recovery_state),
)


def collect_snapshot():
    """Collect a redacted in-memory diagnostics snapshot without writing files."""
    sections = {name: _safe_section(collector) for name, collector in _SECTION_COLLECTORS}
    return _sanitize({
        "schema": SCHEMA,
        "collector_version": COLLECTOR_VERSION,
        "created_utc": _utc_timestamp(),
        "sections": sections,
    })


def _sanitized_log_text(path, max_lines=LOG_MAX_LINES):
    lines = deque(maxlen=max(1, int(max_lines)))
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as stream:
            for raw in stream:
                raw = raw.rstrip("\r\n")
                if not raw:
                    continue
                try:
                    value = json.loads(raw)
                except Exception:
                    lines.append(redact_text(raw, limit=SECTION_STRING_LIMIT))
                else:
                    lines.append(json.dumps(
                        _sanitize(value), ensure_ascii=False, separators=(",", ":")
                    ))
    except Exception as exc:
        return json.dumps({"log_read_error": _error_text(exc)}, ensure_ascii=False) + "\n"
    if not lines:
        return ""
    # Final whole-tail redaction catches secret syntax that spans physical
    # lines, notably PEM private-key BEGIN/END blocks.
    return redact_text("\n".join(lines) + "\n")


def _log_candidates():
    base = core.log_path()
    result = [(base, "logs/proxy_core.log")]
    for index in range(1, LOG_ROTATIONS + 1):
        result.append(("%s.%d" % (base, index), "logs/proxy_core.log.%d" % index))
    return result


def _default_output_path():
    folder = os.path.join(core.data_dir(), "diagnostics")
    return os.path.join(
        folder,
        "ArvectumProxyDiagnostics-%s.zip" % _safe_filename_timestamp(),
    )


def create_support_bundle(output_path=None):
    """Create an atomic redacted Windows diagnostics ZIP and return its path."""
    if not core.is_windows():
        raise RuntimeError("platform diagnostics support bundle is available on Windows only")

    target = os.path.abspath(os.fspath(output_path or _default_output_path()))
    if not target.lower().endswith(".zip"):
        target += ".zip"
    parent = os.path.dirname(target)
    if parent:
        os.makedirs(parent, exist_ok=True)
    temporary = target + ".tmp-%d" % os.getpid()

    snapshot = collect_snapshot()
    diagnostics_json = json.dumps(snapshot, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    try:
        with zipfile.ZipFile(
            temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
        ) as archive:
            archive.writestr("diagnostics.json", diagnostics_json.encode("utf-8"))
            for source, arcname in _log_candidates():
                if os.path.isfile(source):
                    archive.writestr(arcname, _sanitized_log_text(source).encode("utf-8"))
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            try:
                os.remove(temporary)
            except OSError:
                pass

    try:
        core.structured_log(
            "windows diagnostics bundle created",
            event="diagnostics.bundle_created",
            path=target,
            bundle_schema=SCHEMA,
        )
    except Exception:
        pass
    return target


if __name__ == "__main__":
    try:
        print(create_support_bundle(sys.argv[1] if len(sys.argv) > 1 else None))
    except Exception as exc:
        print(_error_text(exc), file=sys.stderr)
        raise SystemExit(1)
