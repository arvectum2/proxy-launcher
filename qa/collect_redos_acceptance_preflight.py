#!/usr/bin/env python3
"""Read-only RED OS host/RPM preflight for APL-REG-001C."""
from __future__ import annotations

import argparse
import hashlib
import os
import platform
import shutil
import subprocess
from pathlib import Path

CI_MARKERS = ("CI", "GITHUB_ACTIONS", "GITLAB_CI", "JENKINS_URL", "BUILDKITE", "TEAMCITY_VERSION")


def _read(path: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return ""


def _os_release() -> dict[str, str]:
    result: dict[str, str] = {}
    for raw in _read("/etc/os-release").splitlines():
        if "=" not in raw or raw.lstrip().startswith("#"):
            continue
        key, value = raw.split("=", 1)
        result[key] = value.strip().strip('"')
    return result


def detect_redos(os_release: dict[str, str], release_marker: str = "") -> bool:
    haystack = " ".join(
        (
            os_release.get("ID", ""),
            os_release.get("NAME", ""),
            os_release.get("PRETTY_NAME", ""),
            os_release.get("VARIANT", ""),
            release_marker,
        )
    ).lower()
    normalized = " ".join(haystack.replace("_", " ").replace("-", " ").split())
    return "redos" in normalized or "red os" in normalized or "ред ос" in normalized


def _run(args: list[str]) -> tuple[int, str]:
    try:
        completed = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
            timeout=15,
            env={**os.environ, "LC_ALL": "C"},
        )
        return completed.returncode, completed.stdout.strip()
    except Exception as exc:
        return 127, f"unavailable: {exc}"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect(candidate: Path | None, allow_non_redos: bool) -> tuple[dict[str, str], list[str]]:
    os_release = _os_release()
    release_marker = _read("/etc/redos-release")
    detected = detect_redos(os_release, release_marker)

    virtualization = "unknown"
    if shutil.which("systemd-detect-virt"):
        rc, output = _run(["systemd-detect-virt"])
        virtualization = (output or "unknown") if rc == 0 else "none"

    data: dict[str, str] = {
        "schema": "1",
        "collector": "APL-REG-001C-REDOS",
        "mutation": "false",
        "redos_detected": "yes" if detected else "no",
        "allow_non_redos": "yes" if allow_non_redos else "no",
        "virtualization": virtualization,
        "ci_detected": "yes" if any(os.environ.get(key) for key in CI_MARKERS) else "no",
        "architecture": platform.machine() or "unknown",
        "os_id": os_release.get("ID", "unknown"),
        "os_version_id": os_release.get("VERSION_ID", "unknown"),
        "os_pretty_name": os_release.get("PRETTY_NAME", "unknown"),
        "redos_release_marker": release_marker or "unavailable",
        "xdg_session_type": os.environ.get("XDG_SESSION_TYPE", "unknown"),
        "xdg_current_desktop": os.environ.get("XDG_CURRENT_DESKTOP", "unknown"),
        "display_present": "yes" if os.environ.get("DISPLAY") else "no",
        "wayland_display_present": "yes" if os.environ.get("WAYLAND_DISPLAY") else "no",
    }
    details: list[str] = []

    for command in ("dnf", "rpm", "nmcli"):
        path = shutil.which(command)
        data[command] = path or "unavailable"
        if path:
            rc, output = _run([path, "--version"])
            details.append(f"{command}_version={output.splitlines()[0] if output else 'unavailable'}")

    nmcli = shutil.which("nmcli")
    if nmcli:
        rc, output = _run([nmcli, "-t", "-f", "UUID", "connection", "show", "--active"])
        data["active_connection_count"] = str(len([line for line in output.splitlines() if line.strip()])) if rc == 0 else "0"
        _, permissions = _run([nmcli, "general", "permissions"])
        details += ["nmcli_permissions_begin", permissions, "nmcli_permissions_end"]
    else:
        data["active_connection_count"] = "0"

    if candidate is not None:
        if candidate.is_file():
            data["candidate_name"] = candidate.name
            data["candidate_sha256"] = _sha256(candidate)
            rpm = shutil.which("rpm")
            if rpm:
                for query, key in (
                    ("%{NAME}", "candidate_package"),
                    ("%{VERSION}-%{RELEASE}", "candidate_version_release"),
                    ("%{ARCH}", "candidate_architecture"),
                ):
                    rc, output = _run([rpm, "-qp", "--qf", query, str(candidate)])
                    data[key] = output if rc == 0 and output else "unavailable"
        else:
            data["candidate_missing"] = str(candidate)
    else:
        data["candidate"] = "not-supplied"

    for path in ("/sys/class/dmi/id/sys_vendor", "/sys/class/dmi/id/product_name", "/sys/class/dmi/id/board_name"):
        value = _read(path)
        if value:
            data["dmi_" + Path(path).name] = value.replace("\n", " ")
    return data, details


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", nargs="?", default="redos-acceptance-preflight.txt", type=Path)
    parser.add_argument("candidate", nargs="?", type=Path)
    parser.add_argument("--allow-non-redos", action="store_true")
    args = parser.parse_args()
    data, details = collect(args.candidate, args.allow_non_redos)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    lines = ["APL-REG-001C RED OS read-only preflight evidence"] + [f"{key}={value}" for key, value in data.items()] + [""] + details + ["", "NOTE: collector is read-only; it does not install/remove packages, mutate NetworkManager, elevate privileges, or start the app."]
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    if data["redos_detected"] != "yes" and not args.allow_non_redos:
        print(f"RED OS was not detected; evidence written to {args.output}", file=__import__("sys").stderr)
        return 3
    if args.candidate is not None and not args.candidate.is_file():
        return 4
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
