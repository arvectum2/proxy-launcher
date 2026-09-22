"""Canonical no-proxy routing policy for Arvectum Proxy Launcher.

Owns platform-neutral exclusion policy for PAC clients and the local HTTP/SOCKS engine: persistence, input normalization, host matching and PAC generation. Platform-specific system-proxy mutation remains outside this module.
"""

from __future__ import annotations

import io
import os
import re
from types import ModuleType

DEFAULT_NO_PROXY = [
    "localhost",
    "127.0.0.1",
    "::1",
    "*.local",
    "10.*",
    "172.16.*", "172.17.*", "172.18.*", "172.19.*",
    "172.20.*", "172.21.*", "172.22.*", "172.23.*",
    "172.24.*", "172.25.*", "172.26.*", "172.27.*",
    "172.28.*", "172.29.*", "172.30.*", "172.31.*",
    "192.168.*",
    "captive.apple.com",
    "gsp1.apple.com",
]

_CORE: ModuleType | None = None


def configure(core: ModuleType) -> None:
    """Bind the canonical composition module used for runtime collaborators."""
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("routing policy is not configured")
    return _CORE


def load_no_proxy() -> list[str]:
    """Read user bypass entries without changing their established semantics."""
    core = _core()
    domains: list[str] = []
    path = core.no_proxy_path()
    if os.path.exists(path):
        try:
            with io.open(path, "r", encoding="utf-8") as stream:
                for line in stream:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    domains.append(line)
        except Exception as error:
            core._log("no_proxy read error: %r" % error)
    return domains


def save_no_proxy(domains) -> bool:
    """Normalize, de-duplicate and atomically persist user bypass entries."""
    core = _core()
    try:
        normalized = []
        for raw in domains:
            domain = core.clean_domain(str(raw))
            if domain and domain not in normalized:
                normalized.append(domain)
        lines = [
            "# Список исключений (no_proxy). По одному домену на строку.",
            "# Сайты из списка открываются напрямую, минуя прокси.",
            "# Строки, начинающиеся с #, игнорируются.",
            "# Изменения применяются сразу, перезапуск не нужен.",
            "",
        ] + normalized
        core._atomic_write_text(core.no_proxy_path(), "\n".join(lines) + "\n")
        core._log("no_proxy saved atomically: %d domains" % len(normalized))
        return True
    except Exception as error:
        core._log("no_proxy save error: %r" % error)
        return False


def clean_domain(value) -> str:
    """Extract the historical clean host/pattern from URL or host:port input.

    IPv6 (including bracketed IPv6) and wildcard masks intentionally retain
    the exact 0.2.3 normalization contract.
    """
    domain = value.strip().lower()
    domain = domain.split("#")[0].strip()
    if "://" in domain:
        domain = domain.split("://", 1)[1]
    domain = domain.split("/")[0]
    domain = domain.strip()
    if not domain:
        return ""
    if domain.startswith("["):
        return domain.lstrip("[").split("]")[0]
    colon_count = domain.count(":")
    if colon_count == 1:
        host, _, port = domain.rpartition(":")
        if port.isdigit():
            return host
    # Zero colons means an ordinary host/mask; two or more means IPv6.
    return domain


def _normalize_host(host) -> str:
    """Normalize a destination host before bypass matching."""
    host = (host or "").strip().lower().rstrip(".")
    if host.startswith("[") and host.endswith("]"):
        host = host[1:-1]
    return host


def host_bypasses_proxy(host) -> bool:
    """Evaluate the common no-proxy policy for PAC, HTTP and SOCKS traffic."""
    core = _core()
    host = core._normalize_host(host)
    if not host:
        return False

    patterns = list(core.DEFAULT_NO_PROXY)
    for item in core.load_no_proxy():
        if item not in patterns:
            patterns.append(item)

    for raw in patterns:
        pattern = core._normalize_host(raw)
        if not pattern:
            continue
        if pattern.startswith("."):
            pattern = pattern[1:]
        if "*" in pattern or "?" in pattern:
            regex = "^" + re.escape(pattern).replace(r"\*", ".*").replace(r"\?", ".") + "$"
            if re.match(regex, host, flags=re.IGNORECASE):
                return True
        elif host == pattern or host.endswith("." + pattern):
            return True
    return False


def build_pac() -> str:
    """Generate the established PAC program from the current bypass policy."""
    core = _core()
    direct = list(core.DEFAULT_NO_PROXY)
    for domain in core.load_no_proxy():
        if domain not in direct:
            direct.append(domain)
    lines = "\n".join(
        '        "%s",' % domain.replace("\\", "\\\\").replace('"', '\\"')
        for domain in direct
    )
    port = int(core.load_settings().get("local_http_port", 8080))
    return (
        "function FindProxyForURL(url, host) {\n"
        "    // Исключения no_proxy — синтезируется автоматически (localhost и внутренние сети всегда в обход)\n"
        "    var direct = [\n"
        + lines
        + "\n    ];\n"
        "    for (var i = 0; i < direct.length; i++) {\n"
        "        var d = direct[i];\n"
        "        if (d.indexOf('*') !== -1) {\n"
        "            if (shExpMatch(host, d)) return 'DIRECT';\n"
        "        } else if (host === d || shExpMatch(host, '*.' + d)\n"
        "                   || (host.indexOf(':') !== -1 && host === '[' + d + ']')) {\n"
        "            return 'DIRECT';\n"
        "        }\n"
        "    }\n"
        "    return 'PROXY 127.0.0.1:%d';\n"
        "}\n" % port
    )


def install_into_core(core: ModuleType) -> ModuleType:
    """Expose canonical routing-policy ownership through the compatibility seam."""
    core.DEFAULT_NO_PROXY = list(DEFAULT_NO_PROXY)
    core.load_no_proxy = load_no_proxy
    core.save_no_proxy = save_no_proxy
    core.clean_domain = clean_domain
    core._normalize_host = _normalize_host
    core.host_bypasses_proxy = host_bypasses_proxy
    core.build_pac = build_pac
    return core
