#!/usr/bin/env python3
"""Fail-closed verifier for an APL-REG-001C RED OS real-host evidence bundle."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

REQUIRED_FILES = (
    "00-repository.txt", "01-preflight.txt", "02-network-before.json", "03-package.txt",
    "04-gui.md", "05-enable.md", "06-network-enabled.json", "07-disable.md",
    "08-network-after-disable.json", "09-autostart.md", "10-crash-recovery.md",
    "11-network-after-crash-recovery.json", "12-reboot-recovery.md",
    "13-network-after-reboot-recovery.json", "14-update-remove.md",
    "15-diagnostics-privacy.md", "HOST_ATTESTATION.env", "SUMMARY.md",
)

CHECKS = (
    "read-only preflight", "RPM install/remove/update", "GUI launch/platform UX",
    "NetworkManager runtime/preflight", "PolicyKit authorization UX", "real enable",
    "no-proxy routing", "normal disable exact rollback", "autostart/login",
    "crash/relaunch recovery", "reboot/login recovery",
    "update/remove + user-state preservation", "diagnostics privacy", "final cleanup",
)


def _parse_kv(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip()
    return result


def _load_snapshot(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != 1 or payload.get("collector") != "APL-REG-001C-REDOS":
        raise ValueError(f"unsupported snapshot: {path.name}")
    return payload


def _snapshot_proxy_map(payload: dict) -> dict:
    result = {}
    for connection in payload.get("connections", []):
        identity = connection.get("identity_sha256")
        if not identity or identity in result:
            raise ValueError("invalid or duplicate connection identity")
        result[identity] = {"type": connection.get("type"), "proxy": connection.get("proxy")}
    return result


def _snapshots_equal(before: dict, after: dict) -> bool:
    return _snapshot_proxy_map(before) == _snapshot_proxy_map(after)


def verify(root: Path) -> list[str]:
    failures: list[str] = []
    for name in REQUIRED_FILES:
        path = root / name
        if not path.is_file() or path.stat().st_size == 0:
            failures.append(f"missing/non-empty required evidence: {name}")

    preflight_path = root / "01-preflight.txt"
    preflight: dict[str, str] = {}
    if preflight_path.is_file():
        preflight = _parse_kv(preflight_path.read_text(encoding="utf-8", errors="replace"))
        if preflight.get("collector") != "APL-REG-001C-REDOS":
            failures.append("preflight collector identity is invalid")
        if preflight.get("redos_detected") != "yes":
            failures.append("preflight does not prove RED OS")
        if preflight.get("allow_non_redos") == "yes":
            failures.append("preflight used --allow-non-redos")
        if preflight.get("virtualization") not in {"none", "unknown"}:
            failures.append("preflight reports a virtualized host")
        if preflight.get("ci_detected") != "no":
            failures.append("preflight was collected in CI")
        if preflight.get("architecture") not in {"x86_64", "amd64"}:
            failures.append("host architecture is not x86-64")
        if preflight.get("candidate_package") != "arvectum-proxy-launcher":
            failures.append("candidate RPM package identity is invalid")
        if preflight.get("candidate_architecture") != "x86_64":
            failures.append("candidate RPM architecture is not x86_64")
        if not re.fullmatch(r"[0-9a-f]{64}", preflight.get("candidate_sha256", "")):
            failures.append("candidate RPM SHA256 is missing from preflight")
        for required_tool in ("dnf", "rpm", "nmcli"):
            if preflight.get(required_tool) in {None, "", "unavailable"}:
                failures.append(f"required RED OS tool unavailable: {required_tool}")

    package_path = root / "03-package.txt"
    if preflight and package_path.is_file():
        candidate_sha = preflight.get("candidate_sha256", "")
        package_text = package_path.read_text(encoding="utf-8", errors="replace").lower()
        if candidate_sha and candidate_sha.lower() not in package_text:
            failures.append("package evidence does not contain the preflight candidate SHA256")

    baseline_path = root / "02-network-before.json"
    for phase_name, snapshot_name in (
        ("normal disable", "08-network-after-disable.json"),
        ("crash recovery", "11-network-after-crash-recovery.json"),
        ("reboot recovery", "13-network-after-reboot-recovery.json"),
    ):
        snapshot_path = root / snapshot_name
        if baseline_path.is_file() and snapshot_path.is_file():
            try:
                if not _snapshots_equal(_load_snapshot(baseline_path), _load_snapshot(snapshot_path)):
                    failures.append(f"{phase_name} snapshot does not match baseline")
            except Exception as exc:
                failures.append(f"{phase_name} snapshot comparison failed: {exc}")

    attestation_path = root / "HOST_ATTESTATION.env"
    if attestation_path.is_file():
        attestation = _parse_kv(attestation_path.read_text(encoding="utf-8", errors="replace"))
        for key in ("physical_host", "interactive_graphical_session", "operator_confirmed"):
            if attestation.get(key) != "YES":
                failures.append(f"host attestation requires {key}=YES")

    summary_path = root / "SUMMARY.md"
    if summary_path.is_file():
        summary = summary_path.read_text(encoding="utf-8", errors="replace")
        if not re.search(r"^RESULT:\s*PASS\s*$", summary, re.MULTILINE):
            failures.append("SUMMARY.md does not declare RESULT: PASS")
        for check in CHECKS:
            pattern = rf"^-\s*{re.escape(check)}:\s*PASS\s*$"
            if not re.search(pattern, summary, re.MULTILINE | re.IGNORECASE):
                failures.append(f"SUMMARY.md missing PASS check: {check}")
        if not re.search(r"^pending rollback:\s*NO\s*$", summary, re.MULTILINE | re.IGNORECASE):
            failures.append("SUMMARY.md must end with pending rollback: NO")
        if not re.search(r"^final proxy state:\s*(OFF|BASELINE)\s*$", summary, re.MULTILINE | re.IGNORECASE):
            failures.append("SUMMARY.md must prove final proxy state OFF/BASELINE")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence_dir", type=Path)
    args = parser.parse_args()
    failures = verify(args.evidence_dir)
    if failures:
        print("APL-REG-001C RED OS VERDICT: NOT ACCEPTED")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print("APL-REG-001C RED OS VERDICT: EVIDENCE COMPLETE")
    print("The bundle satisfies the mechanical RED OS real-host evidence contract.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
