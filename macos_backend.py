# -*- coding: utf-8 -*-
"""macOS implementation of the ProxyBackend contract.

The backend uses macOS' built-in ``networksetup`` command. It routes macOS traffic directly through the configured upstream HTTP proxy while the app
is active, disables SOCKS and PAC for the owned session, and preserves proxy-bypass domains. Every
pre-mutation value is durably snapshotted before the first system setting is
changed. Pre-existing authenticated manual proxies are refused before mutation
because ``networksetup`` cannot safely disclose credentials for exact rollback.

the macOS backend adapter intentionally does not wire backend selection into ProxyCore/GUI;
it establishes the concrete macOS safety boundary only.
"""

import json
import os
import socket
import subprocess
from dataclasses import dataclass
from typing import Any, Callable, Dict, Iterable, Mapping, Optional, Sequence, Tuple
from urllib.parse import urlsplit

from proxy_backend import ProxyBackend, ProxyBackendConfig

_BACKUP_SCHEMA_VERSION = 2
_BACKEND_ID = "macos"
_BACKUP_FILENAME = "macos_proxy_backup.json"


class MacOSBackendError(RuntimeError):
    """Base error for macOS backend integration failures."""


class NetworkSetupError(MacOSBackendError):
    """Raised when ``networksetup`` cannot read or change a requested value."""


class RollbackStateError(MacOSBackendError):
    """Raised when durable rollback evidence is missing, corrupt, or unsafe."""


@dataclass(frozen=True)
class NetworkService:
    name: str
    enabled: bool


@dataclass(frozen=True)
class AutoProxyState:
    enabled: bool
    url: str


@dataclass(frozen=True)
class ManualProxyState:
    enabled: bool
    server: str
    port: int
    authenticated: bool = False


def _normalize_domains(values: Iterable[Any]) -> Tuple[str, ...]:
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


def _merge_domains(original: Iterable[Any], additions: Iterable[Any]) -> Tuple[str, ...]:
    merged = []
    seen = set()
    for raw in tuple(original or ()) + tuple(additions or ()):
        value = str(raw or "").strip()
        key = value.lower()
        if not value or key in seen:
            continue
        seen.add(key)
        merged.append(value)
    return tuple(merged)


def _domains_equal(first: Iterable[Any], second: Iterable[Any]) -> bool:
    return set(_normalize_domains(first)) == set(_normalize_domains(second))


def _canonical_config(config: ProxyBackendConfig) -> Optional[Dict[str, Any]]:
    if not isinstance(config, ProxyBackendConfig):
        return None
    pac_url = str(config.pac_url or "").strip()
    http_proxy_url = str(config.http_proxy_url or "").strip()
    socks_proxy_url = str(config.socks_proxy_url or "").strip()
    if not pac_url or not http_proxy_url or not socks_proxy_url:
        return None

    http_parsed = urlsplit(http_proxy_url)
    if (
        http_parsed.scheme != "http"
        or not http_parsed.hostname
        or http_parsed.port is None
    ):
        return None

    socks_parsed = urlsplit(socks_proxy_url)
    if (
        socks_parsed.scheme not in {"socks", "socks5"}
        or not socks_parsed.hostname
        or socks_parsed.port is None
    ):
        return None

    upstream_proxy_url = str(config.upstream_http_proxy_url or "").strip()
    upstream_parsed = urlsplit(upstream_proxy_url)
    if (
        upstream_parsed.scheme != "http"
        or not upstream_parsed.hostname
        or upstream_parsed.port is None
    ):
        return None
    username = str(config.upstream_username or "")
    password = str(config.upstream_password or "")
    if bool(username) != bool(password):
        return None

    return {
        "pac_url": pac_url,
        "http_proxy_url": http_proxy_url,
        "http_proxy_host": http_parsed.hostname,
        "http_proxy_port": int(http_parsed.port),
        "socks_proxy_url": socks_proxy_url,
        "socks_proxy_host": socks_parsed.hostname,
        "socks_proxy_port": int(socks_parsed.port),
        "direct_proxy_url": upstream_proxy_url,
        "direct_proxy_host": upstream_parsed.hostname,
        "direct_proxy_port": int(upstream_parsed.port),
        "direct_proxy_authenticated": bool(username and password),
        "no_proxy": list(_normalize_domains(config.no_proxy)),
    }


def _default_backup_path() -> str:
    return os.path.join(
        os.path.expanduser("~"),
        "Library", "Application Support", "Arvectum", "ProxyLauncher",
        _BACKUP_FILENAME,
    )


class JsonRollbackStore:
    """Atomic JSON store for macOS rollback evidence."""

    def __init__(self, path: Optional[str] = None):
        self.path = os.path.abspath(os.path.expanduser(path or _default_backup_path()))

    def exists(self) -> bool:
        return os.path.exists(self.path)

    def load(self) -> Dict[str, Any]:
        try:
            with open(self.path, "r", encoding="utf-8") as stream:
                payload = json.load(stream)
        except Exception as exc:
            raise RollbackStateError("macOS rollback state is unreadable") from exc
        if not isinstance(payload, dict):
            raise RollbackStateError("macOS rollback state must be a JSON object")
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
            raise RollbackStateError("macOS rollback state could not be persisted") from exc

    def clear(self) -> None:
        try:
            os.remove(self.path)
        except FileNotFoundError:
            return
        except Exception as exc:
            raise RollbackStateError("macOS rollback state could not be cleared") from exc


class NetworkSetupClient:
    """Typed adapter over ``/usr/sbin/networksetup`` without shell invocation."""

    def __init__(
        self,
        binary: str = "/usr/sbin/networksetup",
        runner: Optional[Callable[..., Any]] = None,
    ):
        self.binary = binary
        self._runner = runner or subprocess.run

    def _run(self, *arguments: str) -> str:
        completed = self._runner(
            [self.binary] + [str(arg) for arg in arguments],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        stdout = str(getattr(completed, "stdout", "") or "")
        stderr = str(getattr(completed, "stderr", "") or "")
        returncode = int(getattr(completed, "returncode", 1))
        combined = "\n".join(part for part in (stdout.strip(), stderr.strip()) if part)
        if returncode != 0 or combined.lstrip().startswith("** Error:"):
            raise NetworkSetupError(
                "networksetup failed for %s%s" % (
                    arguments[0] if arguments else "command",
                    ": %s" % combined if combined else "",
                )
            )
        return stdout.strip()

    def list_services(self) -> Tuple[NetworkService, ...]:
        output = self._run("-listallnetworkservices")
        services = []
        seen = set()
        for raw_line in output.splitlines():
            line = raw_line.strip()
            if not line or "denotes that a network service is disabled" in line.lower():
                continue
            enabled = not line.startswith("*")
            name = line[1:].strip() if not enabled else line
            if name and name not in seen:
                seen.add(name)
                services.append(NetworkService(name=name, enabled=enabled))
        return tuple(services)

    def get_auto_proxy(self, service: str) -> AutoProxyState:
        output = self._run("-getautoproxyurl", service)
        values = {}
        for line in output.splitlines():
            key, separator, value = line.partition(":")
            if separator:
                values[key.strip().lower()] = value.strip()
        enabled_raw = values.get("enabled", "").lower()
        if enabled_raw not in {"yes", "no"}:
            raise NetworkSetupError(
                "invalid automatic-proxy state returned for %s" % service
            )
        url = values.get("url", "")
        if url.lower() in {"(null)", "null", "none"}:
            url = ""
        return AutoProxyState(enabled=enabled_raw == "yes", url=url)

    def set_auto_proxy_url(self, service: str, url: str) -> None:
        self._run("-setautoproxyurl", service, str(url))

    def set_auto_proxy_state(self, service: str, enabled: bool) -> None:
        self._run("-setautoproxystate", service, "on" if enabled else "off")

    def _get_manual_proxy(self, command: str, service: str) -> ManualProxyState:
        output = self._run(command, service)
        values = {}
        for line in output.splitlines():
            key, separator, value = line.partition(":")
            if separator:
                values[key.strip().lower()] = value.strip()
        enabled_raw = values.get("enabled", "").lower()
        if enabled_raw not in {"yes", "no"}:
            raise NetworkSetupError(
                "invalid manual-proxy state returned for %s" % service
            )
        server = values.get("server", "")
        try:
            port = int(values.get("port", "0") or 0)
        except (TypeError, ValueError):
            raise NetworkSetupError(
                "invalid manual-proxy port returned for %s" % service
            )
        authenticated_raw = values.get("authenticated proxy enabled", "0").lower()
        authenticated = authenticated_raw in {"1", "yes", "true", "on"}
        return ManualProxyState(
            enabled=enabled_raw == "yes",
            server=server,
            port=port,
            authenticated=authenticated,
        )

    def get_web_proxy(self, service: str) -> ManualProxyState:
        return self._get_manual_proxy("-getwebproxy", service)

    def set_web_proxy(
        self,
        service: str,
        server: str,
        port: int,
        username: str = "",
        password: str = "",
    ) -> None:
        auth = bool(username and password)
        args = [
            "-setwebproxy", service, str(server), str(int(port)),
            "on" if auth else "off",
        ]
        if auth:
            args.extend([str(username), str(password)])
        self._run(*args)

    def set_web_proxy_state(self, service: str, enabled: bool) -> None:
        self._run("-setwebproxystate", service, "on" if enabled else "off")

    def get_secure_web_proxy(self, service: str) -> ManualProxyState:
        return self._get_manual_proxy("-getsecurewebproxy", service)

    def set_secure_web_proxy(
        self,
        service: str,
        server: str,
        port: int,
        username: str = "",
        password: str = "",
    ) -> None:
        auth = bool(username and password)
        args = [
            "-setsecurewebproxy", service, str(server), str(int(port)),
            "on" if auth else "off",
        ]
        if auth:
            args.extend([str(username), str(password)])
        self._run(*args)

    def set_secure_web_proxy_state(self, service: str, enabled: bool) -> None:
        self._run("-setsecurewebproxystate", service, "on" if enabled else "off")

    def get_socks_proxy(self, service: str) -> ManualProxyState:
        return self._get_manual_proxy("-getsocksfirewallproxy", service)

    def set_socks_proxy(self, service: str, server: str, port: int) -> None:
        self._run(
            "-setsocksfirewallproxy",
            service,
            str(server),
            str(int(port)),
            "off",
        )

    def set_socks_proxy_state(self, service: str, enabled: bool) -> None:
        self._run(
            "-setsocksfirewallproxystate",
            service,
            "on" if enabled else "off",
        )

    def get_bypass_domains(self, service: str) -> Tuple[str, ...]:
        output = self._run("-getproxybypassdomains", service)
        if not output:
            return ()
        lowered = output.lower()
        if "aren't any bypass domains" in lowered or "are no bypass domains" in lowered:
            return ()
        return tuple(line.strip() for line in output.splitlines() if line.strip())

    def set_bypass_domains(self, service: str, domains: Sequence[str]) -> None:
        values = [str(value).strip() for value in domains if str(value).strip()]
        self._run("-setproxybypassdomains", service, *(values or ["Empty"]))


class MacOSBackend(ProxyBackend):
    """Ownership-aware macOS system-proxy backend."""

    def __init__(
        self,
        client: Optional[NetworkSetupClient] = None,
        state_path: Optional[str] = None,
        store: Optional[JsonRollbackStore] = None,
        logger: Optional[Callable[[str], None]] = None,
        local_pac_probe: Optional[Callable[[str], bool]] = None,
    ):
        if state_path is not None and store is not None:
            raise ValueError("pass either state_path or store, not both")
        self._client = client or NetworkSetupClient()
        self._store = store or JsonRollbackStore(state_path)
        self._logger = logger
        self._local_pac_probe = local_pac_probe or self._probe_local_pac

    @property
    def backend_id(self) -> str:
        return _BACKEND_ID

    def _log(self, message: str) -> None:
        if self._logger is not None:
            try:
                self._logger(message)
            except Exception:
                pass

    @staticmethod
    def _local_pac_endpoint(url: str):
        try:
            parsed = urlsplit(str(url or "").strip())
        except Exception:
            return None
        host = (parsed.hostname or "").lower()
        if host not in {"127.0.0.1", "localhost", "::1"}:
            return None
        if parsed.scheme not in {"http", "https"}:
            return None
        try:
            port = parsed.port or (443 if parsed.scheme == "https" else 80)
        except ValueError:
            return None
        return host, int(port), parsed.path or "/"

    @classmethod
    def _probe_local_pac(cls, url: str) -> bool:
        endpoint = cls._local_pac_endpoint(url)
        if endpoint is None:
            return True
        host, port, path = endpoint
        parsed = urlsplit(str(url or "").strip())
        if parsed.scheme != "http":
            # Fail closed for localhost HTTPS PAC: proving the exact TLS-backed
            # endpoint safely belongs outside this lightweight rollback probe.
            return False
        try:
            with socket.create_connection((host, port), timeout=0.75) as conn:
                request = (
                    "GET %s HTTP/1.1\r\n"
                    "Host: %s:%d\r\n"
                    "Connection: close\r\n\r\n"
                ) % (path, host, port)
                conn.sendall(request.encode("ascii", "strict"))
                conn.settimeout(0.75)
                head = conn.recv(128)
        except Exception:
            return False
        return bool(
            head.startswith(b"HTTP/1.1 200")
            or head.startswith(b"HTTP/1.0 200")
        )

    def _snapshot_local_pac_urls(self, snapshots: Mapping[str, Any]):
        urls = []
        for service_name, snapshot in snapshots.items():
            auto = snapshot.get("auto_proxy") or {}
            if not bool(auto.get("enabled")):
                continue
            url = str(auto.get("url") or "").strip()
            if self._local_pac_endpoint(url) is not None:
                urls.append((service_name, url))
        return tuple(urls)

    def _restore_plan(self, payload: Mapping[str, Any], phase: str = "disable"):
        try:
            current_names = {service.name for service in self._client.list_services()}
        except Exception as exc:
            self._log("macOS %s refused: network services unavailable: %s" % (phase, exc))
            return None

        applied = payload["applied_config"]
        snapshots = dict(payload["services"])
        missing_names = set(snapshots) - current_names
        if missing_names:
            self._log(
                "macOS %s refused: saved network services are unavailable: %s"
                % (phase, ", ".join(sorted(missing_names)))
            )
            return None

        to_restore = []
        for service_name, snapshot in snapshots.items():
            if self._service_matches_owned_state(service_name, snapshot, applied):
                to_restore.append(service_name)
                continue
            if self._service_matches_snapshot(service_name, snapshot):
                continue
            if self._service_matches_recoverable_state(
                service_name, snapshot, applied
            ):
                to_restore.append(service_name)
                continue
            self._log(
                "macOS %s refused: %s matches neither Arvectum-owned nor saved state"
                % (phase, service_name)
            )
            return None
        return snapshots, tuple(to_restore)

    def disable_preflight(self) -> bool:
        """Prove rollback is safe before the worker can be stopped."""
        if not self._store.exists():
            return True
        try:
            payload = self._load_backup()
        except Exception as exc:
            self._log("macOS disable preflight refused: state unavailable: %s" % exc)
            return False
        for service_name, url in self._snapshot_local_pac_urls(payload["services"]):
            if not self._local_pac_probe(url):
                self._log(
                    "macOS disable preflight refused: saved localhost PAC is unavailable "
                    "for %s: %s" % (service_name, url)
                )
                return False
        return self._restore_plan(payload, phase="disable preflight") is not None

    def restore_pending(self) -> bool:
        # Existence alone is durable evidence. Corrupt evidence is never hidden.
        return bool(self._store.exists())

    def _load_backup(self) -> Dict[str, Any]:
        payload = self._store.load()
        if payload.get("schema_version") != _BACKUP_SCHEMA_VERSION:
            raise RollbackStateError("unsupported macOS rollback schema")
        if payload.get("backend") != _BACKEND_ID:
            raise RollbackStateError("rollback state belongs to another backend")
        if not isinstance(payload.get("services"), dict) or not payload["services"]:
            raise RollbackStateError("rollback state has no network services")
        if not isinstance(payload.get("applied_config"), dict):
            raise RollbackStateError("rollback state has no applied configuration")
        for service, snapshot in payload["services"].items():
            if not isinstance(service, str) or not isinstance(snapshot, dict):
                raise RollbackStateError("invalid network-service snapshot")
            auto = snapshot.get("auto_proxy")
            bypass = snapshot.get("bypass_domains")
            if not isinstance(auto, dict) or not isinstance(auto.get("enabled"), bool):
                raise RollbackStateError("invalid automatic-proxy snapshot")
            if not isinstance(auto.get("url"), str) or not isinstance(bypass, list):
                raise RollbackStateError("invalid rollback snapshot values")
            if auto.get("enabled") and not str(auto.get("url") or "").strip():
                raise RollbackStateError("enabled automatic-proxy snapshot has no URL")
            for key in ("web_proxy", "secure_web_proxy", "socks_proxy"):
                manual = snapshot.get(key)
                if manual is None:
                    continue
                if (
                    not isinstance(manual, dict)
                    or not isinstance(manual.get("enabled"), bool)
                    or not isinstance(manual.get("server"), str)
                    or not isinstance(manual.get("port"), int)
                    or not isinstance(manual.get("authenticated", False), bool)
                ):
                    raise RollbackStateError("invalid manual-proxy snapshot")
        return payload

    def _snapshot_enabled_services(self) -> Dict[str, Any]:
        snapshots = {}
        for service in self._client.list_services():
            if not service.enabled:
                continue
            auto = self._client.get_auto_proxy(service.name)
            web = self._client.get_web_proxy(service.name)
            secure_web = self._client.get_secure_web_proxy(service.name)
            socks = self._client.get_socks_proxy(service.name)
            if web.authenticated or secure_web.authenticated or socks.authenticated:
                raise NetworkSetupError(
                    "authenticated proxy already configured on %s" % service.name
                )
            bypass = self._client.get_bypass_domains(service.name)
            snapshots[service.name] = {
                "auto_proxy": {"enabled": auto.enabled, "url": auto.url},
                "web_proxy": {
                    "enabled": web.enabled,
                    "server": web.server,
                    "port": web.port,
                    "authenticated": web.authenticated,
                },
                "secure_web_proxy": {
                    "enabled": secure_web.enabled,
                    "server": secure_web.server,
                    "port": secure_web.port,
                    "authenticated": secure_web.authenticated,
                },
                "socks_proxy": {
                    "enabled": socks.enabled,
                    "server": socks.server,
                    "port": socks.port,
                    "authenticated": socks.authenticated,
                },
                "bypass_domains": list(bypass),
            }
        if not snapshots:
            raise NetworkSetupError("no enabled macOS network services found")
        return snapshots

    @staticmethod
    def _expected_bypass(snapshot: Mapping[str, Any], applied: Mapping[str, Any]) -> Tuple[str, ...]:
        return _merge_domains(
            snapshot.get("bypass_domains", ()),
            applied.get("no_proxy", ()),
        )

    @staticmethod
    def _manual_proxy_matches(current: ManualProxyState, expected: Mapping[str, Any], enabled: Optional[bool] = None) -> bool:
        expected_enabled = bool(expected.get("enabled"))
        expected_server = str(expected.get("server", ""))
        expected_port = int(expected.get("port", 0))
        effective_enabled = expected_enabled if enabled is None else bool(enabled)
        if current.enabled != effective_enabled:
            return False
        # networksetup cannot clear a remembered manual endpoint. A saved
        # disabled+empty proxy is functionally restored when it is disabled.
        if not expected_server and expected_port == 0 and not expected_enabled:
            return True
        return bool(
            current.server == expected_server
            and current.port == expected_port
            and current.authenticated == bool(expected.get("authenticated", False))
        )

    @staticmethod
    def _owned_direct_proxy_matches(
        current: ManualProxyState,
        applied: Mapping[str, Any],
    ) -> bool:
        return bool(
            current.enabled
            and current.server == str(applied.get("direct_proxy_host", ""))
            and current.port == int(applied.get("direct_proxy_port", 0))
        )

    def _manual_proxy_states(self, service_name: str):
        return (
            self._client.get_web_proxy(service_name),
            self._client.get_secure_web_proxy(service_name),
            self._client.get_socks_proxy(service_name),
        )

    def _manual_proxies_match_owned_state(
        self,
        service_name: str,
        snapshot: Mapping[str, Any],
        applied: Mapping[str, Any],
    ) -> bool:
        try:
            web, secure_web, socks = self._manual_proxy_states(service_name)
        except Exception:
            return False
        return bool(
            self._owned_direct_proxy_matches(web, applied)
            and self._owned_direct_proxy_matches(secure_web, applied)
            and not socks.enabled
        )

    def _manual_proxies_match_snapshot(
        self,
        service_name: str,
        snapshot: Mapping[str, Any],
    ) -> bool:
        web_expected = snapshot.get("web_proxy")
        secure_expected = snapshot.get("secure_web_proxy")
        socks_expected = snapshot.get("socks_proxy")
        try:
            web, secure_web, socks = self._manual_proxy_states(service_name)
        except Exception:
            return False
        return bool(
            (web_expected is None or self._manual_proxy_matches(web, web_expected))
            and (
                secure_expected is None
                or self._manual_proxy_matches(secure_web, secure_expected)
            )
            and (
                socks_expected is None
                or self._manual_proxy_matches(socks, socks_expected)
            )
        )

    def _manual_proxies_recoverable(
        self,
        service_name: str,
        snapshot: Mapping[str, Any],
        applied: Mapping[str, Any],
    ) -> bool:
        try:
            web, secure_web, socks = self._manual_proxy_states(service_name)
        except Exception:
            return False

        web_expected = snapshot.get("web_proxy")
        secure_expected = snapshot.get("secure_web_proxy")
        socks_expected = snapshot.get("socks_proxy")

        web_ok = bool(
            self._owned_direct_proxy_matches(web, applied)
            or (
                web_expected is not None
                and self._manual_proxy_matches(web, web_expected)
            )
        )
        secure_ok = bool(
            self._owned_direct_proxy_matches(secure_web, applied)
            or (
                secure_expected is not None
                and self._manual_proxy_matches(secure_web, secure_expected)
            )
        )
        socks_ok = bool(
            not socks.enabled
            or (
                socks_expected is not None
                and self._manual_proxy_matches(socks, socks_expected)
            )
        )
        return bool(web_ok and secure_ok and socks_ok)

    def _service_matches_owned_state(
        self,
        service_name: str,
        snapshot: Mapping[str, Any],
        applied: Mapping[str, Any],
    ) -> bool:
        try:
            auto = self._client.get_auto_proxy(service_name)
            bypass = self._client.get_bypass_domains(service_name)
        except Exception:
            return False
        return bool(
            not auto.enabled
            and _domains_equal(bypass, self._expected_bypass(snapshot, applied))
            and self._manual_proxies_match_owned_state(
                service_name, snapshot, applied
            )
        )

    def _service_matches_snapshot(
        self,
        service_name: str,
        snapshot: Mapping[str, Any],
    ) -> bool:
        """Return True when the live service is functionally back at its saved state."""
        try:
            auto = self._client.get_auto_proxy(service_name)
            bypass = self._client.get_bypass_domains(service_name)
        except Exception:
            return False
        expected = snapshot["auto_proxy"]
        expected_enabled = bool(expected["enabled"])
        expected_url = str(expected["url"] or "").strip()
        if auto.enabled != expected_enabled:
            return False
        if expected_enabled:
            if not expected_url or auto.url != expected_url:
                return False
        return bool(
            _domains_equal(bypass, snapshot.get("bypass_domains", ()))
            and self._manual_proxies_match_snapshot(service_name, snapshot)
        )

    def _service_matches_recoverable_state(
        self,
        service_name: str,
        snapshot: Mapping[str, Any],
        applied: Mapping[str, Any],
    ) -> bool:
        try:
            auto = self._client.get_auto_proxy(service_name)
            bypass = self._client.get_bypass_domains(service_name)
        except Exception:
            return False
        expected = snapshot["auto_proxy"]
        expected_enabled = bool(expected["enabled"])
        expected_url = str(expected["url"] or "").strip()
        auto_owned = bool(not auto.enabled)
        auto_snapshot = bool(
            (not expected_enabled and not auto.enabled)
            or (
                expected_enabled
                and bool(expected_url)
                and auto.enabled
                and auto.url == expected_url
            )
        )
        bypass_owned = _domains_equal(
            bypass, self._expected_bypass(snapshot, applied)
        )
        bypass_snapshot = _domains_equal(
            bypass, snapshot.get("bypass_domains", ())
        )
        if not (auto_owned or auto_snapshot):
            return False
        if not (bypass_owned or bypass_snapshot):
            return False
        return self._manual_proxies_recoverable(
            service_name, snapshot, applied
        )

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
        if str(applied.get("socks_proxy_url", "")) != canonical["socks_proxy_url"]:
            return False
        if str(applied.get("direct_proxy_url", "")) != canonical["direct_proxy_url"]:
            return False
        return bool(
            allow_no_proxy_change
            or _domains_equal(applied.get("no_proxy", ()), canonical["no_proxy"])
        )

    def _payload_is_owned(self, payload: Mapping[str, Any]) -> bool:
        try:
            names = {service.name for service in self._client.list_services()}
        except Exception:
            return False
        if not set(payload["services"]).issubset(names):
            return False
        applied = payload["applied_config"]
        return all(
            self._service_matches_owned_state(name, snapshot, applied)
            for name, snapshot in payload["services"].items()
        )

    def enable(self, config: ProxyBackendConfig) -> bool:
        canonical = _canonical_config(config)
        if canonical is None:
            return False
        if self._store.exists():
            try:
                payload = self._load_backup()
            except Exception as exc:
                self._log("macOS enable refused: rollback state is unreadable: %s" % exc)
                return False
            return bool(
                self._payload_matches_config(payload, config)
                and self._payload_is_owned(payload)
            )

        try:
            snapshots = self._snapshot_enabled_services()
            for service_name, url in self._snapshot_local_pac_urls(snapshots):
                if url == canonical["pac_url"]:
                    continue
                if self._local_pac_probe(url):
                    reason = "conflicting localhost PAC is active"
                else:
                    reason = "saved localhost PAC backing is unavailable"
                self._log(
                    "macOS enable refused: %s for %s: %s"
                    % (reason, service_name, url)
                )
                return False
            payload = {
                "schema_version": _BACKUP_SCHEMA_VERSION,
                "backend": _BACKEND_ID,
                "applied_config": canonical,
                "services": snapshots,
            }
            # Rollback evidence is durable before the first network mutation.
            self._store.save(payload)
        except Exception as exc:
            self._log("macOS enable refused before mutation: %s" % exc)
            return False

        touched = []
        try:
            for service_name, snapshot in snapshots.items():
                touched.append(service_name)
                self._client.set_auto_proxy_state(service_name, False)
                self._client.set_socks_proxy_state(service_name, False)
                self._client.set_web_proxy(
                    service_name,
                    canonical["direct_proxy_host"],
                    canonical["direct_proxy_port"],
                    str(config.upstream_username or ""),
                    str(config.upstream_password or ""),
                )
                self._client.set_secure_web_proxy(
                    service_name,
                    canonical["direct_proxy_host"],
                    canonical["direct_proxy_port"],
                    str(config.upstream_username or ""),
                    str(config.upstream_password or ""),
                )
                self._client.set_web_proxy_state(service_name, True)
                self._client.set_secure_web_proxy_state(service_name, True)
                self._client.set_bypass_domains(
                    service_name,
                    self._expected_bypass(snapshot, canonical),
                )
            return True
        except Exception as exc:
            self._log("macOS enable failed; restoring snapshots: %s" % exc)
            restored = self._restore_touched_services(snapshots, touched)
            if restored:
                try:
                    self._store.clear()
                except Exception as clear_exc:
                    self._log("rollback succeeded but backup cleanup failed: %s" % clear_exc)
            return False

    def refresh(self, config: ProxyBackendConfig) -> bool:
        """Verify the already-owned manual route without mutating system state."""
        canonical = _canonical_config(config)
        if canonical is None or not self._store.exists():
            return False
        try:
            payload = self._load_backup()
        except Exception as exc:
            self._log("macOS refresh refused: rollback state is unreadable: %s" % exc)
            return False
        return bool(
            self._payload_matches_config(payload, config)
            and self._payload_is_owned(payload)
        )

    def _restore_service(self, service_name: str, snapshot: Mapping[str, Any]) -> None:
        web = snapshot.get("web_proxy")
        secure_web = snapshot.get("secure_web_proxy")

        if web is not None:
            server = str(web.get("server", ""))
            port = int(web.get("port", 0))
            if server and port > 0:
                self._client.set_web_proxy(service_name, server, port)
            self._client.set_web_proxy_state(
                service_name, bool(web.get("enabled"))
            )

        if secure_web is not None:
            server = str(secure_web.get("server", ""))
            port = int(secure_web.get("port", 0))
            if server and port > 0:
                self._client.set_secure_web_proxy(service_name, server, port)
            self._client.set_secure_web_proxy_state(
                service_name, bool(secure_web.get("enabled"))
            )

        socks = snapshot.get("socks_proxy")
        if socks is not None:
            server = str(socks.get("server", ""))
            port = int(socks.get("port", 0))
            if server and port > 0:
                self._client.set_socks_proxy(service_name, server, port)
            self._client.set_socks_proxy_state(
                service_name, bool(socks.get("enabled"))
            )

        self._client.set_bypass_domains(service_name, snapshot["bypass_domains"])

        auto = snapshot["auto_proxy"]
        enabled = bool(auto["enabled"])
        url = str(auto["url"] or "").strip()
        if enabled and not url:
            raise RollbackStateError(
                "cannot restore enabled automatic proxy without a saved URL"
            )
        # networksetup cannot clear a remembered PAC URL. A disabled+empty
        # original state is functionally restored by leaving PAC disabled.
        if url:
            self._client.set_auto_proxy_url(service_name, url)
        if enabled:
            self._client.set_auto_proxy_state(service_name, False)
            self._client.set_auto_proxy_state(service_name, True)
        else:
            self._client.set_auto_proxy_state(service_name, False)

    def _restore_touched_services(
        self,
        snapshots: Mapping[str, Any],
        touched: Iterable[str],
    ) -> bool:
        ok = True
        for service_name in reversed(tuple(touched)):
            try:
                self._restore_service(service_name, snapshots[service_name])
            except Exception as exc:
                ok = False
                self._log("macOS rollback failed for %s: %s" % (service_name, exc))
        return ok

    def is_enabled(self, config: ProxyBackendConfig) -> bool:
        if not self._store.exists():
            return False
        try:
            payload = self._load_backup()
        except Exception:
            return False
        return bool(
            self._payload_matches_config(payload, config)
            and self._payload_is_owned(payload)
        )

    def disable(self) -> bool:
        if not self._store.exists():
            # No ownership evidence means no mutation, never a generic reset.
            return True
        try:
            payload = self._load_backup()
        except Exception as exc:
            self._log("macOS disable refused: state unavailable: %s" % exc)
            return False

        plan = self._restore_plan(payload, phase="disable")
        if plan is None:
            return False
        snapshots, to_restore = plan

        if not self._restore_touched_services(snapshots, to_restore):
            return False

        if not all(
            self._service_matches_snapshot(service_name, snapshot)
            for service_name, snapshot in snapshots.items()
        ):
            self._log("macOS disable incomplete: restored services failed verification")
            return False
        try:
            self._store.clear()
            return True
        except Exception as exc:
            self._log("settings restored but rollback evidence remains: %s" % exc)
            return False

    def sync_no_proxy(self, config: ProxyBackendConfig) -> bool:
        canonical = _canonical_config(config)
        if canonical is None or not self._store.exists():
            return False
        try:
            payload = self._load_backup()
        except Exception:
            return False
        # PAC/local-proxy identity cannot change through bypass synchronization.
        if not self._payload_matches_config(payload, config, allow_no_proxy_change=True):
            return False
        if not self._payload_is_owned(payload):
            return False

        old_applied = dict(payload["applied_config"])
        touched = []
        try:
            for service_name, snapshot in payload["services"].items():
                touched.append(service_name)
                self._client.set_bypass_domains(
                    service_name,
                    self._expected_bypass(snapshot, canonical),
                )
        except Exception as exc:
            self._log("macOS bypass sync failed; rolling back: %s" % exc)
            for service_name in reversed(touched):
                try:
                    snapshot = payload["services"][service_name]
                    self._client.set_bypass_domains(
                        service_name,
                        self._expected_bypass(snapshot, old_applied),
                    )
                except Exception as rollback_exc:
                    self._log(
                        "macOS bypass rollback failed for %s: %s"
                        % (service_name, rollback_exc)
                    )
            return False

        updated = dict(payload)
        updated["applied_config"] = canonical
        try:
            self._store.save(updated)
            return True
        except Exception as exc:
            self._log("macOS bypass metadata update failed: %s" % exc)
            for service_name in reversed(touched):
                try:
                    snapshot = payload["services"][service_name]
                    self._client.set_bypass_domains(
                        service_name,
                        self._expected_bypass(snapshot, old_applied),
                    )
                except Exception as rollback_exc:
                    self._log(
                        "macOS metadata rollback failed for %s: %s"
                        % (service_name, rollback_exc)
                    )
            # Existing disk metadata stays authoritative. Pending evidence remains.
            return False