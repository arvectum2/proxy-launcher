#!/usr/bin/env python3
"""Reject silent TCP/CLOSE_WAIT leaks even if VPN and HTTPS are still online.

Raw monitor JSONL and its prior verdict remain immutable. This evaluator
is independent of the application and never changes networking.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path


def assess(samples: list[dict]) -> dict:
    problems: list[str] = []
    if len(samples) < 30:
        problems.append("too few physical samples")
    if not samples:
        return {"verdict": "FAIL", "problems": ["no samples"]}
    elapsed = int(samples[-1]["elapsed"])
    if elapsed < 3600:
        problems.append("physical test shorter than 60 minutes")
    if any(sample["vpn"] != "Connected" for sample in samples):
        problems.append("VPN interruption")
    if any(sample.get("arc_online") is not True for sample in samples):
        problems.append("independent ARC/Tailscale interruption")
    if any(
        sample.get("https") and (
            sample["https"].get("rc") != 0 or sample["https"].get("status") != "200"
        ) for sample in samples
    ):
        problems.append("HTTPS probe failure")
    pids = {sample.get("pid") for sample in samples}
    if None in pids or len(pids) != 1:
        problems.append("Packet Tunnel process restarted/disappeared")

    max_tcp = max(int(sample["tcp"]) for sample in samples)
    max_wait = max(int(sample["close_wait"]) for sample in samples)
    final_wait = int(samples[-1]["close_wait"])
    final_tcp = int(samples[-1]["tcp"])
    if max_tcp > 110:
        problems.append("upstream TCP peak exceeds protected 96-session budget")
    if max_wait > 45:
        problems.append("CLOSE_WAIT peak exceeds 45")
    if final_wait > 25:
        problems.append("CLOSE_WAIT not drained by end of test")
    # An early high burst is not necessarily a leak. Compare complete
    # ten-minute buckets rather than accepting a single lucky last sample.
    early = [s for s in samples if int(s["elapsed"]) < 600]
    late = [s for s in samples if int(s["elapsed"]) >= elapsed - 600]
    if early and late:
        early_avg = sum(int(s["close_wait"]) for s in early) / len(early)
        late_avg = sum(int(s["close_wait"]) for s in late) / len(late)
        if late_avg > early_avg + 15:
            problems.append("sustained CLOSE_WAIT accumulation between first and last 10 minutes")
    return {
        "verdict": "FAIL" if problems else "PASS",
        "elapsed": elapsed,
        "samples": len(samples),
        "max_tcp": max_tcp,
        "max_close_wait": max_wait,
        "final_tcp": final_tcp,
        "final_close_wait": final_wait,
        "problems": problems,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("logfile", type=Path)
    ap.add_argument("--result", type=Path)
    options = ap.parse_args()
    samples = [json.loads(line) for line in options.logfile.read_text().splitlines() if line.strip()]
    decision = assess(samples)
    out = json.dumps(decision, indent=2, ensure_ascii=False)
    print(out)
    if options.result:
        options.result.write_text(out + "\n")
    return 0 if decision["verdict"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
