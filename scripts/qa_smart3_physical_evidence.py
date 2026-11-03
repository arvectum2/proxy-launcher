#!/usr/bin/env python3
"""Audit bounded Smart3 iPhone QA evidence without reading secrets.

Inputs are copies of the test-only App Group preference file and of the
no-forwarding LAN mock's local stdout. Never operate on a live device here.
"""
from __future__ import annotations

import argparse
import collections
import json
import plistlib
from pathlib import Path


def verify_shared_ip(group_plist: Path, mock_log: Path) -> dict[str, int]:
    preferences = plistlib.loads(group_plist.read_bytes())
    source = preferences.get("tunnel_events_v1", b"[]")
    if isinstance(source, str):
        source = source.encode("utf-8")
    events = json.loads(source)
    types = collections.Counter(e.get("type", "") for e in events)
    marker = next(
        (e.get("timestamp", 0) for e in events if e.get("type") == "lab scoped enabled"),
        None,
    )
    if marker is None:
        raise ValueError("Lab was never started on this iPhone")
    events = [e for e in events if e.get("timestamp", 0) >= marker]
    events.sort(key=lambda e: e.get("timestamp", 0))
    types = collections.Counter(e.get("type", "") for e in events)
    names = [e.get("type", "") for e in events]
    for name, amount in (
        ("lab scoped probe started", 1),
        ("lab scoped probe results", 1),
        ("lab direct armed", 1),
        ("lab sameflow recovered", 2),
        ("lab sameflow tls data", 2),
        ("lab direct client bytes", 2),
        ("lab direct server bytes", 2),
        ("lab scoped tls data", 1),
        ("lab neighbor via proxy", 1),
        ("lab neighbor tcp ready", 1),
    ):
        if types[name] < amount:
            raise ValueError(f"Missing independent per-flow proof: {name}")
    if names.index("lab direct armed") >= names.index("lab sameflow recovered"):
        raise ValueError("Direct armed AFTER same-flow recovery")
    raw = mock_log.read_text(errors="replace")
    for token, minimum in (
        ("BLOCKED_CONNECT", 2),
        ("HEALTHY_CONNECT", 1),
        ("NEIGHBOR_PROXY_CONNECT", 1),
    ):
        if raw.count(token) < minimum:
            raise ValueError(f"Missing proxy-side evidence: {token}")
    # Never print the plist, app settings, any hostname from private profiles,
    # credentials or user traffic. Only the fixed set of QA evidence counts.
    return {
        "proxy_target_failures": raw.count("BLOCKED_CONNECT"),
        "healthy_proxy_connects": raw.count("HEALTHY_CONNECT"),
        "neighbor_proxy_connects": raw.count("NEIGHBOR_PROXY_CONNECT"),
        "original_tcp_flows_recovered": types["lab sameflow recovered"],
        "original_tls_responses": types["lab sameflow tls data"],
        "fresh_tls_responses": types["lab scoped tls data"],
        "direct_server_payload_events": types["lab direct server bytes"],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group-plist", type=Path, required=True)
    parser.add_argument("--mock-log", type=Path, required=True)
    args = parser.parse_args()
    result = verify_shared_ip(args.group_plist, args.mock_log)
    print("SHARED_IP_DEVICE_AND_UPSTREAM_EVIDENCE_PASS", result)


if __name__ == "__main__":
    main()
