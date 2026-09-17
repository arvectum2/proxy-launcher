#!/usr/bin/env python3
"""Read-only RED OS host/package preflight for APL-REG-001C."""
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


def detect_redos(os_release: dict[str, str]) -> bool:
    haystack = " ".join(
        (os_release.get("ID", ""), os_release.get("NAME", ""), os_release.get("PRETTY_NAME", ""))
    ).lower()
    return os_release.get("ID", "").lower() == "redos" or "red os" in haystack


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
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect(candidate: Path | None, allow_non_redos: bool) -> tuple[dict[str, str], list[str]]:
    osr = _os_release()
    detected = detect_redos(osr)
    virtualization = "unknown"
    if shutil.which("systemd-detect-virt"):
        rc, output = _run(["systemd-detect-virt"])
        virtualization = (output or "unknown") if rc == 0 else "none"

    data = {
        "schema": "1",
        "collector": "APL-REG-001C",
        "mutation": "false",
        "redos_detected": "yes" if detected else "no",
        "allow_non_redos": "yes" if allow_non_redos else "no",
        "virtualization": virtualization,
        "ci_detected": "yes" if any(os.environ.get(key) for key in CI_MARKERS) else "no",
        "architecture": platform.machine() or "unknown",
        "kernel": platform.release() or "unknown",
        "os_id": osr.get("ID", "unknown"),
        "os_pretty_name": osr.get("PRETTY_NAME", "unknown"),
        "os_version_id": osr.get("VERSION_ID", "unknown"),
        "os_edition": osr.get("EDITION", "unknown"),
        "platform_id": osr.get("PLATFORM_ID", "unknown"),
        "xdg_session_type": os.environ.get("XDG_SESSION_TYPE", "unknown"),
        "xdg_current_desktop": os.environ.get("XDG_CURRENT_DESKTOP", "unknown"),
        "display_present": "yes" if os.environ.get("DISPLAY") else "no",
        "wayland_display_present": "yes" if os.environ.get("WAYLAND_DISPLAY") else "no",
    }
    details: list[str] = []

    nmcli = shutil.which("nmcli")
    data["nmcli"] = nmcli or "unavailable"
    if nmcli:
        _, output = _run([nmcli, "--version"])
        details.append("nmcli_version=" + output)
        rc, output = _run([nmcli, "-t", "-f", "UUID", "connection", "show", "--active"])
        data["active_connection_count"] = str(len([line for line in output.splitlines() if line.strip()])) if rc == 0 else "0"
        _, output = _run([nmcli, "general", "permissions"])
        details += ["nmcli_permissions_begin", output, "nmcli_permissions_end"]
    else:
        data["active_connection_count"] = "0"

    if candidate is not None:
        if candidate.is_file():
            data["candidate_name"] = candidate.name
            data["candidate_sha256"] = _sha256(candidate)
            rpm = shutil.which("rpm")
            if rpm:
                fields = {
                    "candidate_package": "%{NAME}",
                    "candidate_version": "%{VERSION}",
                    "candidate_release": "%{RELEASE}",
                    "candidate_architecture": "%{ARCH}",
                }
                for key, query in fields.items():
                    _, output = _run([rpm, "-qp", "--qf", query, str(candidate)])
                    data[key] = output or "unavailable"
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
    lines = ["APL-REG-001C RED OS read-only preflight evidence"]
    lines += [f"{key}={value}" for key, value in data.items()]
    lines += [""] + details
    lines += ["", "NOTE: collector is read-only; it does not install/remove packages, mutate NetworkManager, elevate privileges, or start the app."]
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
