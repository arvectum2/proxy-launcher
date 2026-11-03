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
    # The activity ring retains only the most recent 40 events. The early
    # lab-enabled marker can legitimately roll off after several TLS retries.
    # Require the most recent actual independent probe-start instead.
    starts = [
        e.get("timestamp", 0) for e in events
        if e.get("type") == "lab scoped probe started"
    ]
    marker = max(starts) if starts else None
    if marker is None:
        raise ValueError("Independent physical probe never started")
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
    if max(e.get("timestamp", 0) for e in events) - marker > 55:
        raise ValueError("Physical evidence spans multiple QA sessions")
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
        "direct_ipv4_sockets": types["lab physical tcp ipv4"],
        "direct_ipv6_sockets": types["lab physical tcp ipv6"],
    }


def verify_reversion(group_plist: Path, mock_log: Path, mode: str) -> dict[str, int]:
    """Ensure a real recovered TLS route becomes proxy-only on QA revoke/TTL."""
    if mode not in {"path", "ttl"}:
        raise ValueError("Unknown bounded QA reversion mode")
    data = plistlib.loads(group_plist.read_bytes())
    source = data.get("tunnel_events_v1", b"[]")
    if isinstance(source, str):
        source = source.encode("utf-8")
    records = json.loads(source)
    events = sorted(records, key=lambda x: x.get("timestamp", 0))
    armed = [e for e in events if e.get("type") == "lab direct armed"]
    if not armed:
        raise ValueError("No independently approved DIRECT route")
    approved = armed[-1].get("timestamp", 0)
    events = [e for e in events if e.get("timestamp", 0) >= approved]
    kind = "smart direct reverted" if mode == "path" else "smart direct expired"
    revoked = [e for e in events if e.get("type") == kind and
               (mode != "path" or e.get("detail") == "qa network change")]
    if not revoked:
        raise ValueError("No bounded revocation or TTL expiry event")
    time = revoked[-1].get("timestamp", 0)
    if not approved < time:
        raise ValueError("Route revoked before it was approved")
    if mode == "ttl" and not 3 <= time - approved <= 8:
        raise ValueError("Shortened TTL did not expire at expected delay")
    original = [e for e in events if e.get("type") == "lab sameflow tls data"
                and e.get("timestamp", 0) < time]
    if len(original) < 2:
        raise ValueError("Original blocked TCP/TLS streams did not recover")
    retry = [e for e in events if e.get("type") == "lab scoped tls attempt"
             and e.get("timestamp", 0) > time]
    if not retry:
        raise ValueError("No new target connection after route was revoked")
    wrong = [e for e in events if e.get("type") == "lab scoped tls data"
             and e.get("timestamp", 0) > time]
    if wrong:
        raise ValueError("Previously approved target still received DIRECT TLS after revoke")
    raw = mock_log.read_text(errors="replace")
    if raw.count("BLOCKED_CONNECT") < 3:
        raise ValueError("Expected third target CONNECT through proxy after revoke")
    if raw.count("HEALTHY_CONNECT") < 1:
        raise ValueError("Healthy other-host proxy evidence missing")
    if max(e.get("timestamp", 0) for e in events) - approved > 45:
        raise ValueError("Reversion evidence spans multiple physical QA runs")
    return {
        "original_tls_responses": len(original),
        "post_revoke_proxy_target_connects": raw.count("BLOCKED_CONNECT") - 2,
        "post_revoke_direct_tls_responses": len(wrong),
        "route_revocations": len(revoked),
    }


def verify_ipv6_fail_closed(group_plist: Path, mock_log: Path) -> dict[str, int]:
    """Physical iPhone direct IPv6 TCP can stall TLS; disallow this egress."""
    settings = plistlib.loads(group_plist.read_bytes())
    raw_events = settings.get("tunnel_events_v1", b"[]")
    if isinstance(raw_events, str):
        raw_events = raw_events.encode("utf-8")
    events = sorted(json.loads(raw_events), key=lambda x: x.get("timestamp", 0))
    starts = [e.get("timestamp", 0) for e in events
              if e.get("type") == "lab scoped probe started"]
    if not starts:
        raise ValueError("No physical IPv6 test learning attempt observed")
    started = max(starts)
    events = [e for e in events if e.get("timestamp", 0) >= started]
    counts = collections.Counter(e.get("type", "") for e in events)
    for key in ("lab ipv6 neighbor via proxy", "lab ipv6 neighbor tcp ready",
                "lab scoped tls attempt"):
        if counts[key] < 1:
            raise ValueError("Missing verified proxy-neighbor or test attempt: "+key)
    for bad in ("lab physical tcp ipv6", "lab scoped tls data",
                "lab sameflow tls data", "lab direct server bytes"):
        if counts[bad] != 0:
            raise ValueError("IPv6-only host escaped fail-closed: "+bad)
    text = mock_log.read_text(errors="replace")
    if text.count("BLOCKED_CONNECT") < 2 or text.count("HEALTHY_CONNECT") < 1:
        raise ValueError("Missing two independent proxy failures or healthy peer")
    if text.count("IPV6_NEIGHBOR_PROXY_CONNECT") < 1:
        raise ValueError("Canonical IPv6 neighbor bypassed upstream proxy")
    return {
        "upstream_ipv6_target_failures": text.count("BLOCKED_CONNECT"),
        "ipv6_neighbor_proxy_connects": text.count("IPV6_NEIGHBOR_PROXY_CONNECT"),
        "outgoing_direct_ipv6_sockets": counts["lab physical tcp ipv6"],
        "direct_tls_responses": counts["lab scoped tls data"] + counts["lab sameflow tls data"],
        "reverted_unvalidated_routes": counts["lab direct reverted"],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group-plist", type=Path, required=True)
    parser.add_argument("--mock-log", type=Path, required=True)
    parser.add_argument("--reversion-mode", choices=("path", "ttl"))
    parser.add_argument("--ipv6-failclosed", action="store_true")
    args = parser.parse_args()
    if args.ipv6_failclosed:
        result = verify_ipv6_fail_closed(args.group_plist, args.mock_log)
        print("IPV6_ONLY_FAILCLOSED_DEVICE_AND_UPSTREAM_EVIDENCE_PASS", result)
    elif args.reversion_mode:
        result = verify_reversion(args.group_plist, args.mock_log, args.reversion_mode)
        print("DIRECT_REVERSION_DEVICE_AND_UPSTREAM_EVIDENCE_PASS", result)
    else:
        result = verify_shared_ip(args.group_plist, args.mock_log)
        print("SHARED_IP_DEVICE_AND_UPSTREAM_EVIDENCE_PASS", result)


if __name__ == "__main__":
    main()
