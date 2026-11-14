#!/usr/bin/env python3
"""Classify filtered, header-only USB RVI evidence. Never emit IP addresses.
This bounded positive-control receipt is not a general leak-proof claim.
"""
import argparse
import ipaddress
import re

TARGET = ipaddress.IPv6Address("2606:4700:4700::1111")
PHASES = ("BEFORE", "DURING", "AFTER")
PORTS = (53, 443)
MARKER = re.compile(r"APL_OFFLINK_WINDOW_(BEFORE|DURING|AFTER)_(BEGIN|END)_([0-9]+(?:\.[0-9]+)?)")
PACKET = re.compile(r"^([0-9]+(?:\.[0-9]+)?)\s+.*?IP6\s+([0-9a-fA-F:]+)\.(\d+)\s+>\s+([0-9a-fA-F:]+)\.(\d+):")


def evaluate(test, capture, statistics):
    marks = {}
    for phase, event, stamp in MARKER.findall(test):
        if (phase, event) in marks:
            raise ValueError("duplicate phase marker")
        marks[phase, event] = float(stamp)
    windows = {phase: (marks[phase, "BEGIN"], marks[phase, "END"]) for phase in PHASES}
    last = 0
    for phase in PHASES:
        start, end = windows[phase]
        if not last < start < end or end - start > 10:
            raise ValueError("invalid phase ordering/duration")
        last = end
    counts = {phase: {port: [0, 0] for port in PORTS} for phase in PHASES}
    for line in capture.splitlines():
        match = PACKET.search(line)
        if not match:
            continue
        stamp, source, _, dest, port = match.groups()
        port = int(port)
        if ipaddress.IPv6Address(dest) != TARGET or port not in PORTS:
            continue
        stamp = float(stamp)
        for phase, (start, end) in windows.items():
            if start <= stamp <= end:
                src = ipaddress.IPv6Address(source)
                counts[phase][port][0 if src.is_global else 1] += 1
    tunnel_receipt = ("APL_OFFLINK_DISPOSABLE_EGRESS_CONFIRMED" in test
                      and "APL_OFFLINK_VPN_OFF_CONFIRMED" in test)
    test_ok = "TEST EXECUTE SUCCEEDED" in test and tunnel_receipt
    capture_ok = bool(re.search(r"(?m)^0 packets dropped by kernel\b", statistics))
    for port in PORTS:
        before, during, after = [counts[p][port][0] for p in PHASES]
        print(f"PORT_{port}_GLOBAL_SOURCE_COUNTS_BEFORE_{before}_DURING_{during}_AFTER_{after}")
        print(f"PORT_{port}_NON_GLOBAL_SOURCE_DURING_{counts['DURING'][port][1]}")
    # A positive physical observation must not disappear just because
    # the accompanying XCTest correctly failed on a successful QUIC handshake.
    if capture_ok and tunnel_receipt and any(counts["DURING"][p][0] for p in PORTS):
        return "OFFLINK_PHYSICAL_UDP_OBSERVED"
    if not test_ok or not capture_ok:
        return "INCONCLUSIVE"
    if not all(counts[phase][p][0] for phase in ("BEFORE", "AFTER") for p in PORTS):
        return "INCONCLUSIVE"
    return "BOUNDED_OFFLINK_PHYSICAL_UDP_NOT_OBSERVED"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("test_log")
    parser.add_argument("capture")
    parser.add_argument("capture_statistics")
    args = parser.parse_args()
    try:
        from pathlib import Path
        result = evaluate(*(Path(p).read_text(errors="replace") for p in (
            args.test_log, args.capture, args.capture_statistics)))
    except (ValueError, KeyError):
        result = "INCONCLUSIVE"
    print("APL_OFFLINK_RVI_RESULT_" + result)
    raise SystemExit(0 if result == "BOUNDED_OFFLINK_PHYSICAL_UDP_NOT_OBSERVED" else 1)
