# -*- coding: utf-8 -*-
"""NetworkManager implementation of the ProxyBackend contract for Linux/Astra.

the Linux backend adapter targets Linux desktops whose active network connections are
managed by NetworkManager. The backend mutates per-connection WWW proxy state
through ``nmcli`` and reapplies changed active profiles without restarting
NetworkManager or cycling network interfaces.

Only profiles active when ``enable`` is called are owned. Durable rollback
evidence is persisted before the first profile mutation. Linux installations
using ifupdown/networking or another network manager deliberately fail closed;
automatic fallback policy belongs to a later integration task.
"""

from dataclasses import dataclass
import json
import os
import subprocess
from typing import Any, Callable, Dict, Iterable, Mapping, Optional, Sequence, Tuple

from proxy_backend import ProxyBackend, ProxyBackendConfig
from linux_desktop_proxy import DesktopProxyState


_BACKUP_SCHEMA_VERSION = 2
_SUPPORTED_BACKUP_SCHEMA_VERSIONS = frozenset({1, 2})
_BACKEND_ID = "linux"
_BACKUP_FILENAME = "linux_proxy_backup.json"
_IGNORED_ACTIVE_TYPES = frozenset({"vpn", "loopback"})


class LinuxBackendError(RuntimeError):
    """Base error for Linux backend integration failures."""


class NetworkManagerError(LinuxBackendError):
    """Raised when nmcli cannot inspect or change NetworkManager state."""


class RollbackStateError(LinuxBackendError):
    """Raised when durable Linux rollback evidence is missing or unsafe."""


@dataclass(frozen=True)
class ActiveConnection:
    uuid: str
    connection_type: str
    device: str


@dataclass(frozen=True)
class NetworkManagerProxyState:
    method: str
    browser_only: bool
    pac_url: str
    pac_script: str


def _normalize_no_proxy(values: Iterable[Any]) -> Tuple[str, ...]:
    normalized = []
    seen = set()
    for raw in values or ():
        value = str(raw or "").strip()
        key = value.lower()
        if not value or key in seen:
            continue
        seen.add(key)
        normalized.append(key)
    return tuple(normalized)


def _no_proxy_equal(first: Iterable[Any], second: Iterable[Any]) -> bool:
    return set(_normalize_no_proxy(first)) == set(_normalize_no_proxy(second))


def _canonical_config(config: ProxyBackendConfig) -> Optional[Dict[str, Any]]:
    if not isinstance(config, ProxyBackendConfig):
        return None
    pac_url = str(config.pac_url or "").strip()
    http_proxy_url = str(config.http_proxy_url or "").strip()
    if not pac_url or not http_proxy_url:
        return None
    return {
        "pac_url": pac_url,
        "http_proxy_url": http_proxy_url,
        "no_proxy": list(_normalize_no_proxy(config.no_proxy)),
    }


def _desired_proxy_state(applied: Mapping[str, Any]) -> NetworkManagerProxyState:
    return NetworkManagerProxyState(
        method="auto",
        browser_only=False,
        pac_url=str(applied.get("pac_url", "")),
        pac_script="",
    )


def _state_to_dict(state: NetworkManagerProxyState) -> Dict[str, Any]:
    return {
        "method": state.method,
        "browser_only": state.browser_only,
        "pac_url": state.pac_url,
        "pac_script": state.pac_script,
    }


def _state_from_dict(payload: Mapping[str, Any]) -> NetworkManagerProxyState:
    method = payload.get("method")
    browser_only = payload.get("browser_only")
    pac_url = payload.get("pac_url")
    pac_script = payload.get("pac_script")
    if method not in {"none", "auto"}:
        raise RollbackStateError("invalid NetworkManager proxy method in rollback state")
    if not isinstance(browser_only, bool):
        raise RollbackStateError("invalid NetworkManager browser-only value")
    if not isinstance(pac_url, str) or not isinstance(pac_script, str):
        raise RollbackStateError("invalid NetworkManager PAC values")
    return NetworkManagerProxyState(
        method=method,
        browser_only=browser_only,
        pac_url=pac_url,
        pac_script=pac_script,
    )


def _desktop_state_to_dict(state: DesktopProxyState) -> Dict[str, Any]:
    return {
        "mode": state.mode,
        "autoconfig_url": state.autoconfig_url,
    }


def _desktop_state_from_dict(payload: Mapping[str, Any]) -> DesktopProxyState:
    mode = payload.get("mode")
    autoconfig_url = payload.get("autoconfig_url")
    if mode not in {"none", "manual", "auto"}:
        raise RollbackStateError("invalid desktop proxy mode in rollback state")
    if not isinstance(autoconfig_url, str):
        raise RollbackStateError("invalid desktop PAC URL in rollback state")
    return DesktopProxyState(mode=mode, autoconfig_url=autoconfig_url)


def _desired_desktop_state(applied: Mapping[str, Any]) -> DesktopProxyState:
    return DesktopProxyState(
        mode="auto",
        autoconfig_url=str(applied.get("pac_url", "")),
    )


def _default_backup_path() -> str:
    state_root = os.environ.get("XDG_STATE_HOME")
    if not state_root:
        state_root = os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(
        os.path.abspath(os.path.expanduser(state_root)),
        "Arvectum",
        "ProxyLauncher",
        _BACKUP_FILENAME,
    )


class JsonRollbackStore:
    """Atomic JSON store for Linux rollback evidence."""

    def __init__(self, path: Optional[str] = None):
        self.path = os.path.abspath(os.path.expanduser(path or _default_backup_path()))

    def exists(self) -> bool:
        return os.path.exists(self.path)

    def load(self) -> Dict[str, Any]:
        try:
            with open(self.path, "r", encoding="utf-8") as stream:
                payload = json.load(stream)
        except Exception as exc:
            raise RollbackStateError("Linux rollback state is unreadable") from exc
        if not isinstance(payload, dict):
            raise RollbackStateError("Linux rollback state must be a JSON object")
        return payload

    def save(self, payload: Mapping[str, Any]) -> None:
        parent = os.path.dirname(self.path)
        os.makedirs(parent, mode=0o700, exist_ok=True)
        temporary = "%s.%s.tmp" % (self.path, os.getpid())
        try:
            descriptor = os.open(
                temporary,
                os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
                0o600,
            )
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                json.dump(payload, stream, ensure_ascii=False, sort_keys=True, indent=2)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, self.path)
            try:
                os.chmod(self.path, 0o600)
            except OSError:
                pass
        except Exception as exc:
            try:
                if os.path.exists(temporary):
                    os.remove(temporary)
            except OSError:
                pass
            raise RollbackStateError(
                "Linux rollback state could not be persisted"
            ) from exc

    def clear(self) -> None:
        try:
            os.remove(self.path)
        except FileNotFoundError:
            return
        except Exception as exc:
            raise RollbackStateError(
                "Linux rollback state could not be cleared"
            ) from exc


def _split_nmcli_terse(line: str) -> Tuple[str, ...]:
    """Split one nmcli terse row while respecting backslash escaping."""
    fields = []
    current = []
    escaped = False
    for char in str(line):
        if escaped:
            current.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == ":":
            fields.append("".join(current))
            current = []
        else:
            current.append(char)
    if escaped:
        current.append("\\")
    fields.append("".join(current))
    return tuple(fields)


class NetworkManagerClient:
    """Typed, injectable nmcli adapter. Shell invocation is never used."""

    def __init__(
        self,
        binary: str = "/usr/bin/nmcli",
        runner: Optional[Callable[..., Any]] = None,
        timeout: int = 15,
    ):
        self.binary = binary
        self._runner = runner or subprocess.run
        self.timeout = int(timeout)

    def _run(self, *arguments: str) -> str:
        environment = dict(os.environ)
        environment["LC_ALL"] = "C"
        try:
            completed = self._runner(
                [self.binary] + [str(argument) for argument in arguments],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                timeout=self.timeout,
                env=environment,
            )
        except Exception as exc:
            raise NetworkManagerError("nmcli could not be executed") from exc

        stdout = str(getattr(completed, "stdout", "") or "")
        stderr = str(getattr(completed, "stderr", "") or "")
        returncode = int(getattr(completed, "returncode", 1))
        if returncode != 0:
            detail = stderr.strip() or stdout.strip()
            raise NetworkManagerError(
                "nmcli failed%s" % (": %s" % detail if detail else "")
            )
        return stdout.rstrip("\n")

    def list_active_connections(self) -> Tuple[ActiveConnection, ...]:
        output = self._run(
            "--terse", "--escape", "yes", "--fields", "UUID,TYPE,DEVICE",
            "connection", "show", "--active",
        )
        result = []
        seen = set()
        for raw_line in output.splitlines():
            if not raw_line.strip():
                continue
            fields = _split_nmcli_terse(raw_line)
            if len(fields) != 3:
                raise NetworkManagerError("unexpected nmcli active-connection row")
            uuid, connection_type, device = (value.strip() for value in fields)
            if not uuid or uuid in seen:
                continue
            seen.add(uuid)
            result.append(
                ActiveConnection(uuid, connection_type.lower(), device)
            )
        return tuple(result)

    def list_connection_profiles(self) -> Dict[str, str]:
        output = self._run(
            "--terse", "--escape", "yes", "--fields", "UUID,TYPE",
            "connection", "show",
        )
        result = {}
        for raw_line in output.splitlines():
            if not raw_line.strip():
                continue
            fields = _split_nmcli_terse(raw_line)
            if len(fields) != 2:
                raise NetworkManagerError("unexpected nmcli connection-profile row")
            uuid, connection_type = (value.strip() for value in fields)
            if uuid:
                result[uuid] = connection_type.lower()
        return result

    def _get_value(self, uuid: str, property_name: str) -> str:
        return self._run(
            "--escape", "no", "--get-values", property_name,
            "connection", "show", "uuid", uuid,
        )

    def get_proxy(self, uuid: str) -> NetworkManagerProxyState:
        method = self._get_value(uuid, "proxy.method").strip().lower()
        browser_raw = self._get_value(uuid, "proxy.browser-only").strip().lower()
        pac_url = self._get_value(uuid, "proxy.pac-url")
        pac_script = self._get_value(uuid, "proxy.pac-script")
        if method not in {"none", "auto"}:
            raise NetworkManagerError("unsupported NetworkManager proxy method")
        if browser_raw in {"yes", "true", "on", "1"}:
            browser_only = True
        elif browser_raw in {"no", "false", "off", "0"}:
            browser_only = False
        else:
            raise NetworkManagerError("invalid NetworkManager browser-only value")
        return NetworkManagerProxyState(method, browser_only, pac_url, pac_script)

    def set_proxy(self, uuid: str, state: NetworkManagerProxyState) -> None:
        if state.method not in {"none", "auto"}:
            raise NetworkManagerError("refusing unsupported NetworkManager proxy method")
        self._run(
            "connection", "modify", "uuid", uuid,
            "proxy.method", state.method,
            "proxy.browser-only", "yes" if state.browser_only else "no",
            "proxy.pac-url", state.pac_url,
            "proxy.pac-script", state.pac_script,
        )

    def reapply(self, device: str) -> None:
        device = str(device or "").strip()
        if not device or device == "--":
            raise NetworkManagerError("cannot reapply connection without a device")
        self._run("device", "reapply", device)


class LinuxBackend(ProxyBackend):
    """Ownership-aware NetworkManager backend for Linux and Astra Linux."""

    def __init__(
        self,
        client: Optional[NetworkManagerClient] = None,
        state_path: Optional[str] = None,
        store: Optional[JsonRollbackStore] = None,
        logger: Optional[Callable[[str], None]] = None,
        desktop_client: Optional[object] = None,
    ):
        if state_path is not None and store is not None:
            raise ValueError("pass either state_path or store, not both")
        self._client = client or NetworkManagerClient()
        self._store = store or JsonRollbackStore(state_path)
        self._logger = logger
        self._desktop_client = desktop_client

    @property
    def backend_id(self) -> str:
        return _BACKEND_ID

    def _log(self, message: str) -> None:
        if self._logger is not None:
            try:
                self._logger(message)
            except Exception:
                pass

    def restore_pending(self) -> bool:
        # Existence itself is rollback evidence; corrupt evidence remains visible.
        return bool(self._store.exists())

    @staticmethod
    def _target_connections(
        connections: Sequence[ActiveConnection],
    ) -> Tuple[ActiveConnection, ...]:
        result = []
        seen = set()
        for connection in connections:
            uuid = str(connection.uuid or "").strip()
            connection_type = str(connection.connection_type or "").strip().lower()
            device = str(connection.device or "").strip()
            if (
                not uuid or uuid in seen or not device or device == "--"
                or connection_type in _IGNORED_ACTIVE_TYPES
            ):
                continue
            seen.add(uuid)
            result.append(ActiveConnection(uuid, connection_type, device))
        return tuple(result)

    def _snapshot_active_connections(self) -> Dict[str, Any]:
        snapshots = {}
        for connection in self._target_connections(
            self._client.list_active_connections()
        ):
            snapshots[connection.uuid] = {
                "connection_type": connection.connection_type,
                "device": connection.device,
                "proxy": _state_to_dict(self._client.get_proxy(connection.uuid)),
            }
        if not snapshots:
            raise NetworkManagerError(
                "no supported active NetworkManager connection profiles found"
            )
        return snapshots

    def _load_backup(self) -> Dict[str, Any]:
        payload = self._store.load()
        if payload.get("schema_version") not in _SUPPORTED_BACKUP_SCHEMA_VERSIONS:
            raise RollbackStateError("unsupported Linux rollback schema")
        if payload.get("backend") != _BACKEND_ID:
            raise RollbackStateError("rollback state belongs to another backend")
        if not isinstance(payload.get("connections"), dict) or not payload["connections"]:
            raise RollbackStateError("rollback state has no connection profiles")
        if not isinstance(payload.get("applied_config"), dict):
            raise RollbackStateError("rollback state has no applied configuration")
        for uuid, snapshot in payload["connections"].items():
            if not isinstance(uuid, str) or not uuid or not isinstance(snapshot, dict):
                raise RollbackStateError("invalid NetworkManager connection snapshot")
            if not isinstance(snapshot.get("connection_type"), str):
                raise RollbackStateError("invalid NetworkManager connection type")
            if not isinstance(snapshot.get("device"), str):
                raise RollbackStateError("invalid NetworkManager device snapshot")
            proxy = snapshot.get("proxy")
            if not isinstance(proxy, dict):
                raise RollbackStateError("invalid NetworkManager proxy snapshot")
            _state_from_dict(proxy)
        desktop_proxy = payload.get("desktop_proxy")
        if desktop_proxy is not None:
            if not isinstance(desktop_proxy, dict):
                raise RollbackStateError("invalid desktop proxy snapshot")
            if desktop_proxy.get("backend") != "gsettings":
                raise RollbackStateError("unsupported desktop proxy rollback backend")
            state = desktop_proxy.get("state")
            if not isinstance(state, dict):
                raise RollbackStateError("invalid desktop proxy rollback state")
            _desktop_state_from_dict(state)
        return payload

    def _payload_matches_config(
        self,
        payload: Mapping[str, Any],
        config: ProxyBackendConfig,
        allow_no_proxy_change: bool = False,
    ) -> bool:
        canonical = _canonical_config(config)
        if canonical is None:
            return False
        applied = payload.get("applied_config", {})
        if str(applied.get("pac_url", "")) != canonical["pac_url"]:
            return False
        if str(applied.get("http_proxy_url", "")) != canonical["http_proxy_url"]:
            return False
        return bool(
            allow_no_proxy_change
            or _no_proxy_equal(applied.get("no_proxy", ()), canonical["no_proxy"])
        )

    def _profile_matches_owned_state(
        self,
        uuid: str,
        snapshot: Mapping[str, Any],
        applied: Mapping[str, Any],
        current_profiles: Mapping[str, str],
        allow_restored: bool = False,
    ) -> bool:
        if uuid not in current_profiles:
            return True
        if current_profiles[uuid] != str(snapshot.get("connection_type", "")).lower():
            return False
        try:
            current = self._client.get_proxy(uuid)
        except Exception:
            return False
        if current == _desired_proxy_state(applied):
            return True
        return bool(allow_restored and current == _state_from_dict(snapshot["proxy"]))

    def _desktop_snapshot_from_payload(
        self, payload: Mapping[str, Any]
    ) -> Optional[DesktopProxyState]:
        desktop_proxy = payload.get("desktop_proxy")
        if desktop_proxy is None:
            return None
        return _desktop_state_from_dict(desktop_proxy["state"])

    def _desktop_matches_owned_state(
        self, payload: Mapping[str, Any], allow_restored: bool = False
    ) -> bool:
        original = self._desktop_snapshot_from_payload(payload)
        if original is None:
            return True
        if self._desktop_client is None:
            return False
        try:
            current = self._desktop_client.get_state()
        except Exception:
            return False
        if current == _desired_desktop_state(payload["applied_config"]):
            return True
        return bool(allow_restored and current == original)

    def _restore_desktop(self, payload: Mapping[str, Any]) -> bool:
        original = self._desktop_snapshot_from_payload(payload)
        if original is None:
            return True
        if self._desktop_client is None:
            self._log("Linux desktop rollback unavailable: GSettings client missing")
            return False
        try:
            self._desktop_client.set_state(original)
            return True
        except Exception as exc:
            self._log("Linux desktop rollback failed: %s" % exc)
            return False

    def _payload_is_owned_and_active(self, payload: Mapping[str, Any]) -> bool:
        try:
            current_profiles = self._client.list_connection_profiles()
            active = self._target_connections(self._client.list_active_connections())
        except Exception:
            return False
        for uuid, snapshot in payload["connections"].items():
            if not self._profile_matches_owned_state(
                uuid, snapshot, payload["applied_config"], current_profiles
            ):
                return False
        if not self._desktop_matches_owned_state(payload):
            return False
        if not active:
            return False
        stored = payload["connections"]
        desired = _desired_proxy_state(payload["applied_config"])
        for connection in active:
            if connection.uuid not in stored:
                return False
            snapshot = stored[connection.uuid]
            if str(snapshot.get("connection_type", "")).lower() != connection.connection_type:
                return False
            try:
                if self._client.get_proxy(connection.uuid) != desired:
                    return False
            except Exception:
                return False
        return True

    def _restore_profiles(
        self,
        snapshots: Mapping[str, Any],
        uuids: Iterable[str],
        active_devices: Mapping[str, str],
    ) -> bool:
        ok = True
        for uuid in reversed(tuple(uuids)):
            snapshot = snapshots.get(uuid)
            if snapshot is None:
                continue
            try:
                self._client.set_proxy(uuid, _state_from_dict(snapshot["proxy"]))
                device = active_devices.get(uuid)
                if device:
                    self._client.reapply(device)
            except Exception as exc:
                ok = False
                self._log("Linux rollback failed for %s: %s" % (uuid, exc))
        return ok

    def enable(self, config: ProxyBackendConfig) -> bool:
        canonical = _canonical_config(config)
        if canonical is None:
            return False
        if self._store.exists():
            try:
                payload = self._load_backup()
            except Exception as exc:
                self._log("Linux enable refused: rollback state is unreadable: %s" % exc)
                return False
            return bool(
                self._payload_matches_config(payload, config)
                and self._payload_is_owned_and_active(payload)
            )

        try:
            snapshots = self._snapshot_active_connections()
            desktop_snapshot = (
                self._desktop_client.get_state()
                if self._desktop_client is not None
                else None
            )
            payload = {
                "schema_version": _BACKUP_SCHEMA_VERSION,
                "backend": _BACKEND_ID,
                "applied_config": canonical,
                "connections": snapshots,
                "desktop_proxy": (
                    {
                        "backend": "gsettings",
                        "state": _desktop_state_to_dict(desktop_snapshot),
                    }
                    if desktop_snapshot is not None
                    else None
                ),
            }
            # Durable rollback evidence precedes every persistent system-proxy mutation.
            self._store.save(payload)
        except Exception as exc:
            self._log("Linux enable refused before mutation: %s" % exc)
            return False

        desired = _desired_proxy_state(canonical)
        active_devices = {
            uuid: str(snapshot["device"]) for uuid, snapshot in snapshots.items()
        }
        touched = []
        desktop_touched = False
        try:
            for uuid, snapshot in snapshots.items():
                touched.append(uuid)
                self._client.set_proxy(uuid, desired)
                self._client.reapply(str(snapshot["device"]))
            if desktop_snapshot is not None:
                desktop_touched = True
                self._desktop_client.set_state(_desired_desktop_state(canonical))
            return True
        except Exception as exc:
            self._log("Linux enable failed; restoring system proxy state: %s" % exc)
            desktop_restored = True
            if desktop_touched:
                desktop_restored = self._restore_desktop(payload)
            profiles_restored = self._restore_profiles(
                snapshots, touched, active_devices
            )
            if desktop_restored and profiles_restored:
                try:
                    self._store.clear()
                except Exception as clear_exc:
                    self._log(
                        "rollback succeeded but Linux backup cleanup failed: %s"
                        % clear_exc
                    )
            return False

    def is_enabled(self, config: ProxyBackendConfig) -> bool:
        if not self._store.exists():
            return False
        try:
            payload = self._load_backup()
        except Exception:
            return False
        return bool(
            self._payload_matches_config(payload, config)
            and self._payload_is_owned_and_active(payload)
        )

    def disable(self) -> bool:
        if not self._store.exists():
            # Without ownership evidence, a generic NetworkManager reset is forbidden.
            return True
        try:
            payload = self._load_backup()
            current_profiles = self._client.list_connection_profiles()
            active_connections = self._client.list_active_connections()
        except Exception as exc:
            self._log("Linux disable refused: state unavailable: %s" % exc)
            return False

        existing = {
            uuid: snapshot
            for uuid, snapshot in payload["connections"].items()
            if uuid in current_profiles
        }
        for uuid, snapshot in existing.items():
            if not self._profile_matches_owned_state(
                uuid,
                snapshot,
                payload["applied_config"],
                current_profiles,
                allow_restored=True,
            ):
                self._log(
                    "Linux disable refused: %s no longer matches Arvectum-owned or saved state"
                    % uuid
                )
                return False
        if not self._desktop_matches_owned_state(payload, allow_restored=True):
            self._log(
                "Linux disable refused: desktop proxy no longer matches Arvectum-owned or saved state"
            )
            return False

        active_devices = {
            connection.uuid: connection.device
            for connection in active_connections
            if connection.device and connection.device != "--"
        }
        # Both restorers are retry-safe: already-restored saved state remains an
        # accepted ownership state while rollback evidence exists.
        desktop_restored = self._restore_desktop(payload)
        profiles_restored = self._restore_profiles(
            existing, tuple(existing), active_devices
        )
        if not (desktop_restored and profiles_restored):
            return False
        try:
            self._store.clear()
            return True
        except Exception as exc:
            self._log("settings restored but Linux rollback evidence remains: %s" % exc)
            return False

    def sync_no_proxy(self, config: ProxyBackendConfig) -> bool:
        canonical = _canonical_config(config)
        if canonical is None or not self._store.exists():
            return False
        try:
            payload = self._load_backup()
        except Exception:
            return False

        # NetworkManager's bypass policy is the PAC document itself. ProxyCore owns
        # PAC generation; this backend owns the NetworkManager pointer to that PAC.
        if not self._payload_matches_config(
            payload, config, allow_no_proxy_change=True
        ):
            return False
        if not self._payload_is_owned_and_active(payload):
            return False

        updated = dict(payload)
        updated["applied_config"] = canonical
        try:
            self._store.save(updated)
            return True
        except Exception as exc:
            self._log("Linux no-proxy metadata update failed: %s" % exc)
            return False
