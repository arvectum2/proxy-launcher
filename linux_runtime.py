# -*- coding: utf-8 -*-
"""Linux/Astra runtime environment detection for Arvectum Proxy Launcher.

Linux platform detection provides one deterministic, side-effect-free source of runtime facts
for Linux integration tasks. Detection never mutates the host and does not infer
support merely from a desktop name or from ``sys.platform``.
"""

from dataclasses import dataclass
import os
import platform as platform_module
import shlex
import shutil
import sys
from typing import Callable, Mapping, Optional, Sequence, Tuple


_DEFAULT_OS_RELEASE_PATHS = ("/etc/os-release", "/usr/lib/os-release")
_DEFAULT_ASTRA_VERSION_PATH = "/etc/astra_version"


class LinuxRuntimeDetectionError(RuntimeError):
    """Raised when Linux runtime detection is requested on a non-Linux host."""


@dataclass(frozen=True)
class LinuxRuntimeEnvironment:
    distro_id: str
    id_like: Tuple[str, ...]
    name: str
    pretty_name: str
    version_id: str
    version_codename: str
    variant: str
    variant_id: str
    astra_version: str
    kernel_release: str
    architecture: str
    desktop_environment: str
    session_type: str
    nmcli_path: str
    is_astra: bool
    is_redos: bool
    is_debian_family: bool
    network_manager_client_available: bool

    @property
    def runtime_id(self) -> str:
        """Stable product-facing runtime id used by later Linux gates."""
        if self.is_astra:
            return "astra"
        if self.is_redos:
            return "redos"
        return self.distro_id or "linux"

    @property
    def platform_label(self) -> str:
        """Product-facing platform signature for the detected Linux distribution."""
        if self.is_astra:
            return "Linux / Astra Linux"
        if self.is_redos:
            return "Linux / RED OS"
        return "Linux"


def _unquote_os_release_value(raw: str) -> str:
    value = str(raw or "").strip()
    if not value:
        return ""
    try:
        parsed = shlex.split(value, posix=True)
    except ValueError:
        return value.strip("\"'")
    if len(parsed) == 1:
        return parsed[0]
    return " ".join(parsed)


def parse_os_release(text: str) -> Mapping[str, str]:
    """Parse the freedesktop os-release key/value format without execution."""
    result = {}
    for raw_line in str(text or "").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, raw_value = line.split("=", 1)
        key = key.strip()
        if not key or not all(ch.isalnum() or ch == "_" for ch in key):
            continue
        result[key] = _unquote_os_release_value(raw_value)
    return result


def _default_read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as stream:
        return stream.read()


def _read_first_available(
    paths: Sequence[str], read_text: Callable[[str], str]
) -> Mapping[str, str]:
    for path in paths:
        try:
            return parse_os_release(read_text(path))
        except (FileNotFoundError, PermissionError, OSError):
            continue
    return {}


def _read_optional_first_line(path: str, read_text: Callable[[str], str]) -> str:
    try:
        text = read_text(path)
    except (FileNotFoundError, PermissionError, OSError):
        return ""
    for line in str(text or "").splitlines():
        value = line.strip()
        if value:
            return value
    return ""


def _split_words(value: str) -> Tuple[str, ...]:
    return tuple(part.strip().lower() for part in str(value or "").split() if part.strip())


def _desktop_environment(environ: Mapping[str, str]) -> str:
    for key in ("XDG_CURRENT_DESKTOP", "DESKTOP_SESSION", "GDMSESSION"):
        value = str(environ.get(key, "") or "").strip()
        if value:
            return value
    return ""


def detect_linux_runtime(
    *,
    platform_name: Optional[str] = None,
    environ: Optional[Mapping[str, str]] = None,
    which: Callable[[str], Optional[str]] = shutil.which,
    uname: Callable[[], object] = platform_module.uname,
    read_text: Callable[[str], str] = _default_read_text,
    os_release_paths: Sequence[str] = _DEFAULT_OS_RELEASE_PATHS,
    astra_version_path: str = _DEFAULT_ASTRA_VERSION_PATH,
) -> LinuxRuntimeEnvironment:
    """Return immutable Linux/Astra runtime facts without changing system state."""
    current_platform = str(sys.platform if platform_name is None else platform_name).lower()
    if not current_platform.startswith("linux"):
        raise LinuxRuntimeDetectionError(
            "Linux runtime detection requires a Linux host, got %s"
            % (current_platform or "<empty>")
        )

    environment = os.environ if environ is None else environ
    release = _read_first_available(tuple(os_release_paths), read_text)
    distro_id = str(release.get("ID", "") or "").strip().lower()
    id_like = _split_words(release.get("ID_LIKE", ""))
    name = str(release.get("NAME", "") or "").strip()
    pretty_name = str(release.get("PRETTY_NAME", "") or "").strip()
    astra_version = _read_optional_first_line(astra_version_path, read_text)

    distro_text = " ".join((distro_id, name, pretty_name)).lower()
    is_astra = distro_id == "astra" or "astra linux" in distro_text or bool(astra_version)
    is_redos = distro_id == "redos" or "red os" in distro_text
    is_debian_family = distro_id == "debian" or "debian" in id_like or is_astra

    system_uname = uname()
    kernel_release = str(getattr(system_uname, "release", "") or "")
    architecture = str(getattr(system_uname, "machine", "") or "")
    nmcli_path = str(which("nmcli") or "")

    return LinuxRuntimeEnvironment(
        distro_id=distro_id,
        id_like=id_like,
        name=name,
        pretty_name=pretty_name,
        version_id=str(release.get("VERSION_ID", "") or "").strip(),
        version_codename=str(release.get("VERSION_CODENAME", "") or "").strip(),
        variant=str(release.get("VARIANT", "") or "").strip(),
        variant_id=str(release.get("VARIANT_ID", "") or "").strip().lower(),
        astra_version=astra_version,
        kernel_release=kernel_release,
        architecture=architecture,
        desktop_environment=_desktop_environment(environment),
        session_type=str(environment.get("XDG_SESSION_TYPE", "") or "").strip().lower(),
        nmcli_path=nmcli_path,
        is_astra=is_astra,
        is_redos=is_redos,
        is_debian_family=is_debian_family,
        network_manager_client_available=bool(nmcli_path),
    )
