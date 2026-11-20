"""Structural release-criteria gate, not a release approval or evidence authenticator."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / "specs/001-ios-030-roadmap-traceability"
PIN = "67df7e205ff63703bde90809e89f06211ec0d870"
SOURCE = "docs/APL_IOS_030_UNIFIED_RELEASE_2026-11-11.md"
SOURCE_HASH = "8d32cc457d8c6c8356e8df80600aed69bb51c2ee22f9436f9bb8a57fe128d391"
LINES = tuple(range(9, 18)) + tuple(range(33, 39))


def validate(data, raw, board, current_source):
    errors = []
    if current_source != raw:
        errors.append("current source differs from reviewed baseline; reconcile before changing scope")
    if hashlib.sha256(raw).hexdigest() != SOURCE_HASH:
        errors.append("pinned source hash mismatch")
    if data.get("source") != {"commit": PIN, "path": SOURCE, "sha256": SOURCE_HASH}:
        errors.append("source identity mismatch")
    if data.get("schema") != "arvectum.apl.release-criteria-review/1" or data.get("release_authorized") is not False:
        errors.append("invalid schema or self-authorized release")
    text = raw.decode("utf-8").splitlines()
    rows = data.get("rows", [])
    expected = {f"APL-REL-{n:03d}" for n in LINES}
    ids = [r["id"] for r in rows]
    if len(ids) != len(set(ids)) or set(ids) != expected:
        errors.append("missing, extra or duplicate original criterion")
    tasks = re.findall(r"^- \[([ xX])\] (APL-VERIFY-\d{3}) \((APL-REL-\d{3})\)", board, re.M)
    if len(tasks) != len(expected) or len({t[1] for t in tasks}) != len(tasks):
        errors.append("missing or duplicate criterion verification task")
    mapping = {(t[1], t[2]): t[0].lower() == "x" for t in tasks}
    for row in rows:
        n = row.get("source_line")
        if n not in LINES or row["id"] != f"APL-REL-{n:03d}" or row.get("source_text") != text[n-1]:
            errors.append(row["id"] + ": source mismatch")
            continue
        task_id = f"APL-VERIFY-{n:03d}"
        state = row.get("state")
        if row.get("task_id") != task_id or (task_id,row["id"]) not in mapping:
            errors.append(row["id"] + ": missing task link")
        elif mapping[(task_id,row["id"])] != (state == "verified"):
            errors.append(row["id"] + ": checkbox/state mismatch")
        if state not in {"open","partial","blocked","verified"} or not str(row.get("next_action","")).strip():
            errors.append(row["id"] + ": status/next action missing")
        # Observations cannot be silently promoted to acceptance evidence.
        for o in row.get("observations", []):
            if o.get("kind") != "recorded_report_not_independent_acceptance" or not re.fullmatch(r"[a-f0-9]{40}",o.get("commit","")) or not o.get("path"):
                errors.append(row["id"] + ": unpinned observation")
        if state == "verified":
            evidence=row.get("acceptance_evidence",[])
            if not evidence or any(e.get("criterion") != row["id"] or e.get("outcome") != "pass"
                or not re.fullmatch(r"[a-f0-9]{40}",e.get("source_commit",""))
                or not re.fullmatch(r"[a-f0-9]{64}",e.get("artifact_sha256",""))
                or not e.get("receipt_ref") or not e.get("review_ref")
                for e in evidence):
                errors.append(row["id"] + ": no criterion-specific pinned reviewed PASS evidence")
    return errors


def main():
    raw = subprocess.check_output(["git","-C",str(ROOT),"show",PIN+":"+SOURCE])
    data = json.loads((DIR/"release-criteria.json").read_text())
    errors=validate(data,raw,(DIR/"tasks.md").read_text(),(ROOT/SOURCE).read_bytes())
    if errors:
        raise SystemExit("\n".join(errors))
    print("Structural source/criterion/task check PASS; actual acceptance and release authority not established.")


if __name__ == "__main__":
    main()
