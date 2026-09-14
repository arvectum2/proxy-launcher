# -*- coding: utf-8 -*-
"""Linux/Astra support-bundle collector for Arvectum Proxy Launcher.

Linux diagnostics collects read-only runtime, NetworkManager, application and recovery
state into one redacted ZIP. Collection is deliberately best-effort: a failed
source is represented as a failed section and never authorizes a network change.
Raw configuration, rollback evidence and XDG autostart files are never copied
into the bundle.
"""

from collections import deque
from datetime import datetime, timezone
import json
import os
import platform
import socket
import sys
import zipfile

import linux_autostart
import linux_backend
from linux_backend import NetworkManagerClient
from linux_networkmanager_preflight import detect_networkmanager_preflight
from linux_policykit_ux import policykit_interaction_requested
from linux_runtime import detect_linux_runtime
import proxy_core as core
from secret_redaction import redact_text, redact_value


SCHEMA = "arvectum.proxy.linux_diagnostics.v1"
COLLECTOR_VERSION = 1
LOG_ROTATIONS = 3
LOG_MAX_LINES = 2000
SECTION_MAX_DEPTH = 12
SECTION_MAX_ITEMS = 250
SECTION_STRING_LIMIT = 8192
_IGNORED_ACTIVE_TYPES = frozenset({"vpn", "loopback"})


def _is_linux():
    return str(sys.platform or "").lower().startswith("linux")


def _utc_timestamp():
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _safe_filename_timestamp():
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%SZ")


def default_bundle_filename():
    return "ArvectumProxyDiagnostics-Linux-%s.zip" % _safe_filename_timestamp()


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


def _collapse_home_text(text):
    """Collapse literal home prefixes, including JSON-escaped Windows paths."""
    value = str(text)
    try:
        home = os.path.abspath(os.path.expanduser("~"))
        if home and home != os.sep:
            # Structured log lines are serialized before this final privacy pass.
            # On Windows that means backslashes in the home prefix may already be
            # JSON-escaped, so cover both raw and escaped path representations.
            roots = {home, home.replace("\\", "\\\\")}
            separators = {os.sep, "/", "\\", "\\\\"}
            for root in roots:
                if value == root:
                    value = "~"
                    continue
                for separator in separators:
                    value = value.replace(root + separator, "~" + separator)
    except (OSError, TypeError, ValueError):
        pass
    return value


def _display_path(path):
    """Keep path shape useful while avoiding a literal home-directory prefix."""
    value = os.path.abspath(os.path.expanduser(os.fspath(path)))
    try:
        home = os.path.abspath(os.path.expanduser("~"))
        if value == home:
            return "~"
        if os.path.commonpath((value, home)) == home:
            return "~" + os.sep + os.path.relpath(value, home)
    except (OSError, TypeError, ValueError):
        pass
    return value


def _path_state(path):
    value = os.path.abspath(os.path.expanduser(os.fspath(path)))
    result = {
        "path": _display_path(value),
        "exists": os.path.exists(value),
        "is_file": os.path.isfile(value),
        "is_dir": os.path.isdir(value),
        "is_symlink": os.path.islink(value),
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
        "python_version": platform.python_version(),
        "python_executable": _display_path(sys.executable),
        "frozen": bool(getattr(sys, "frozen", False)),
        "linux": _is_linux(),
    }


def _runtime_to_dict(runtime):
    return {
        "runtime_id": runtime.runtime_id,
        "distro_id": runtime.distro_id,
        "id_like": list(runtime.id_like),
        "name": runtime.name,
        "pretty_name": runtime.pretty_name,
        "version_id": runtime.version_id,
        "version_codename": runtime.version_codename,
        "variant": runtime.variant,
        "variant_id": runtime.variant_id,
        "astra_version": runtime.astra_version,
        "kernel_release": runtime.kernel_release,
        "architecture": runtime.architecture,
        "desktop_environment": runtime.desktop_environment,
        "session_type": runtime.session_type,
        "nmcli_path": _display_path(runtime.nmcli_path) if runtime.nmcli_path else "",
        "is_astra": bool(runtime.is_astra),
        "is_debian_family": bool(runtime.is_debian_family),
        "network_manager_client_available": bool(runtime.network_manager_client_available),
    }


def _collect_runtime():
    return _runtime_to_dict(detect_linux_runtime())


def _settings_summary(settings):
    upstream = []
    for item in settings.get("upstream") or []:
        if not isinstance(item, dict):
            continue
        upstream.append({
            "host": str(item.get("host", "") or ""),
            "port": item.get("port"),
            "username_configured": bool(str(item.get("username", "") or "")),
            "password_configured": bool(str(item.get("password", "") or "")),
        })
    return {
        "config_version": settings.get("config_version"),
        "local_http_port": settings.get("local_http_port", 8080),
        "local_socks_port": settings.get("local_socks_port", 1080),
        "local_pac_port": settings.get("local_pac_port", 8082),
        "pac_path": settings.get("pac_path", "/proxy.pac"),
        "upstream": upstream,
    }


def _collect_application():
    settings = core.load_settings(migrate_legacy=False)
    paths = {
        "install_dir": _path_state(core.install_dir()),
        "data_dir": _path_state(core.data_dir()),
        "settings": _path_state(core.settings_path()),
        "settings_lastgood": _path_state(core.settings_backup_path())
        if hasattr(core, "settings_backup_path") else {"available": False},
        "config_recovery": _path_state(core.config_recovery_path())
        if hasattr(core, "config_recovery_path") else {"available": False},
        "config_quarantine": _path_state(core.config_quarantine_dir())
        if hasattr(core, "config_quarantine_dir") else {"available": False},
        "no_proxy": _path_state(core.no_proxy_path()),
        "pid": _path_state(core.pid_path()),
        "log": _path_state(core.log_path()),
        "linux_rollback": _path_state(linux_backend._default_backup_path()),
        "xdg_autostart": _path_state(linux_autostart.autostart_path()),
    }
    return {
        "app_version": core.APP_VERSION,
        "engineering_milestone": core.ENGINEERING_MILESTONE,
        "settings_summary": _settings_summary(settings),
        "no_proxy": core.load_no_proxy(),
        "paths": paths,
    }


def _collect_proxy_state():
    settings = core.load_settings(migrate_legacy=False)
    operational = core.backend_operational_view()
    config = core.resolved_backend_config(settings)
    return {
        "engine_running": bool(core.is_running()),
        "system_proxy_enabled": bool(core.system_proxy_enabled()),
        "network_restore_pending": bool(core.network_restore_pending()),
        "backend_operational": operational,
        "resolved_backend_config": {
            "pac_url": config.pac_url,
            "http_proxy_url": config.http_proxy_url,
            "no_proxy": list(config.no_proxy),
        },
        "configured_listeners": {
            "http": {"host": "127.0.0.1", "port": int(settings.get("local_http_port", 8080))},
            "socks5": {"host": "127.0.0.1", "port": int(settings.get("local_socks_port", 1080))},
            "pac": {"host": "127.0.0.1", "port": int(settings.get("local_pac_port", 8082))},
        },
    }


def _preflight_to_dict(preflight):
    return {
        "status": getattr(preflight.status, "value", str(preflight.status)),
        "nmcli_version": preflight.nmcli_version,
        "networkmanager_state": preflight.networkmanager_state,
        "connectivity": preflight.connectivity,
        "active_connection_uuids": list(preflight.active_connection_uuids),
        "supported_active_connection_uuids": list(preflight.supported_active_connection_uuids),
        "proxy_setting_supported": bool(preflight.proxy_setting_supported),
        "modify_system_permission": preflight.modify_system_permission,
        "modify_own_permission": preflight.modify_own_permission,
        "reasons": list(preflight.reasons),
    }


def _collect_networkmanager_preflight():
    return _preflight_to_dict(detect_networkmanager_preflight())


def _proxy_state_to_dict(state):
    return {
        "method": state.method,
        "browser_only": bool(state.browser_only),
        "pac_url": state.pac_url,
        "pac_script": state.pac_script,
    }


def _collect_networkmanager_profiles():
    runtime = detect_linux_runtime()
    if not runtime.nmcli_path:
        return {"available": False, "reason": "nmcli_not_found", "active": []}
    client = NetworkManagerClient(binary=runtime.nmcli_path)
    active = client.list_active_connections()
    rows = []
    for connection in active:
        item = {
            "uuid": connection.uuid,
            "type": connection.connection_type,
            "device": connection.device,
            "supported": bool(
                connection.uuid
                and connection.device
                and connection.device != "--"
                and connection.connection_type not in _IGNORED_ACTIVE_TYPES
            ),
        }
        if item["supported"]:
            try:
                item["proxy"] = _proxy_state_to_dict(client.get_proxy(connection.uuid))
            except Exception as exc:
                item["proxy_error"] = _error_text(exc)
        rows.append(item)
    return {"available": True, "active": rows}


def _collect_environment_proxy():
    names = tuple(getattr(core, "_PROXY_ENV_NAMES", (
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
        "http_proxy", "https_proxy", "all_proxy", "no_proxy",
    )))
    return {
        name: {
            "exists": name in os.environ,
            "value": os.environ.get(name, ""),
        }
        for name in names
    }


def _probe_listener(port, timeout=0.25):
    try:
        port = int(port)
    except (TypeError, ValueError):
        return {"host": "127.0.0.1", "port": port, "listening": False, "error": "invalid_port"}
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.settimeout(timeout)
        return {
            "host": "127.0.0.1",
            "port": port,
            "listening": sock.connect_ex(("127.0.0.1", port)) == 0,
        }
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
    return {name: _probe_listener(port) for name, port in ports.items()}


def _collect_network_interfaces():
    try:
        interfaces = [name for _, name in socket.if_nameindex()]
    except Exception as exc:
        return {"available": False, "interfaces": [], "error": _error_text(exc)}
    return {"available": True, "interfaces": sorted(set(interfaces))}


def _collect_recovery():
    rollback_path = linux_backend._default_backup_path()
    return {
        "network_restore_pending": bool(core.network_restore_pending()),
        "rollback_evidence": _path_state(rollback_path),
        "raw_rollback_included": False,
    }


def _collect_autostart():
    status = linux_autostart.status()
    return {
        "enabled": bool(status.enabled),
        "managed": bool(status.managed),
        "conflict": bool(status.conflict),
        "path": _display_path(status.path),
        "message": status.message,
        "raw_desktop_entry_included": False,
    }


def _collect_policykit():
    return {
        "interactive_context_requested": bool(
            policykit_interaction_requested(sys.platform)
        ),
        "credentials_collected_by_arvectum": False,
    }


_SECTION_COLLECTORS = (
    ("system", _collect_system),
    ("runtime", _collect_runtime),
    ("application", _collect_application),
    ("proxy_state", _collect_proxy_state),
    ("networkmanager_preflight", _collect_networkmanager_preflight),
    ("networkmanager_profiles", _collect_networkmanager_profiles),
    ("environment_proxy", _collect_environment_proxy),
    ("listeners", _collect_listeners),
    ("network_interfaces", _collect_network_interfaces),
    ("recovery", _collect_recovery),
    ("autostart", _collect_autostart),
    ("policykit", _collect_policykit),
)


def collect_snapshot():
    """Collect one redacted in-memory Linux diagnostics snapshot."""
    if not _is_linux():
        raise RuntimeError("Linux diagnostics diagnostics require a Linux host")
    sections = {name: _safe_section(collector) for name, collector in _SECTION_COLLECTORS}
    return _sanitize({
        "schema": SCHEMA,
        "collector_version": COLLECTOR_VERSION,
        "created_utc": _utc_timestamp(),
        "read_only": True,
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
    return _collapse_home_text(redact_text("\n".join(lines) + "\n"))


def _log_candidates():
    base = core.log_path()
    result = [(base, "logs/proxy_core.log")]
    for index in range(1, LOG_ROTATIONS + 1):
        result.append(("%s.%d" % (base, index), "logs/proxy_core.log.%d" % index))
    return result


def _linux_state_root():
    state_root = str(os.environ.get("XDG_STATE_HOME", "") or "").strip()
    if state_root and os.path.isabs(state_root):
        return os.path.abspath(os.path.expanduser(state_root))
    return os.path.join(os.path.expanduser("~"), ".local", "state")


def _default_output_path():
    folder = os.path.join(_linux_state_root(), "Arvectum", "ProxyLauncher", "diagnostics")
    return os.path.join(folder, default_bundle_filename())


def create_support_bundle(output_path=None):
    """Create an atomic redacted Linux/Astra diagnostics ZIP and return its path."""
    if not _is_linux():
        raise RuntimeError("Linux diagnostics support bundle is available on Linux only")

    target = os.path.abspath(os.path.expanduser(os.fspath(output_path or _default_output_path())))
    if not target.lower().endswith(".zip"):
        target += ".zip"
    parent = os.path.dirname(target)
    if parent:
        os.makedirs(parent, mode=0o700, exist_ok=True)
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
            "linux diagnostics bundle created",
            event="diagnostics.linux_bundle_created",
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
