#!/usr/bin/env python3
"""APL-REL-014 exact lifecycle/recovery evidence binder.

This tool closes the pre-signing half of APL-REL-014 for the immutable 0.2.4
candidate. It binds the exact product bytes selected for the Russian release to
the authoritative APL-WIN-014 physical lifecycle result.

The canonical output, ``apl-rel-014-lifecycle-evidence.json``, is deliberately
written into the final release directory before APL-REL-011. REL-011 therefore
hashes and signs the lifecycle evidence itself together with the exact Setup,
portable ZIP, and consumer verification UX.

The post-signing half is enforced by APL-REL-013: the Russian production gate
must prove that the signed manifest contains this exact REL-014 evidence and the
same exact Setup/portable hashes before publication can be authorized.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA = "arvectum.proxy.apl-rel-014-exact-evidence.v1"
CANONICAL_EVIDENCE_NAME = "apl-rel-014-lifecycle-evidence.json"
DEFAULT_CONTRACT = (
    Path(__file__).resolve().parents[1]
    / "release"
    / "APL_REL_014_EXACT_SIGNED_SET_CONTRACT.json"
)


class EvidenceError(RuntimeError):
    pass


def read_json(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        raise EvidenceError(f"Cannot read JSON evidence: {path}: {exc}") from exc
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise EvidenceError(f"Malformed JSON evidence: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise EvidenceError(f"JSON evidence must be an object: {path}")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise EvidenceError(f"Cannot hash file: {path}: {exc}") from exc
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def norm_hash(value: Any, label: str) -> str:
    text = str(value or "").strip().lower()
    require(
        len(text) == 64 and all(ch in "0123456789abcdef" for ch in text),
        f"{label} is not a SHA-256 value.",
    )
    return text


def norm_commit(value: Any, label: str) -> str:
    text = str(value or "").strip().lower()
    require(
        len(text) == 40 and all(ch in "0123456789abcdef" for ch in text),
        f"{label} is not a 40-character Git commit.",
    )
    return text


def resolve_release_asset(
    release_dir: Path,
    candidate_record: Any,
    expected_hash: str,
    label: str,
) -> dict[str, Any]:
    require(isinstance(candidate_record, dict), f"candidate_evidence.{label} is missing.")
    name = str(candidate_record.get("filename") or "").strip()
    require(name != "", f"candidate_evidence.{label}.filename is missing.")
    require(
        Path(name).name == name and name not in {".", ".."},
        f"candidate_evidence.{label}.filename is not a flat release filename.",
    )
    candidate_hash = norm_hash(candidate_record.get("sha256"), f"candidate_evidence.{label}.sha256")
    require(
        candidate_hash == expected_hash,
        f"candidate_evidence {label} hash does not match the APL-REL-014 contract.",
    )
    asset = release_dir / name
    require(asset.is_file(), f"Exact {label} release asset is missing: {asset}")
    actual = sha256_file(asset)
    require(actual == expected_hash, f"Exact {label} release asset SHA-256 mismatch.")
    return {
        "filename": name,
        "size_bytes": asset.stat().st_size,
        "sha256": actual,
    }


def assert_candidate(contract: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    require(
        candidate.get("schema") == "arvectum.proxy.apl-win-014-final-0.2.4-candidate.v1",
        "Candidate evidence schema is not the canonical final 0.2.4 schema.",
    )
    require(candidate.get("task") == "APL-WIN-014", "Candidate evidence task is not APL-WIN-014.")
    require(
        str(candidate.get("product_version")) == contract["version"],
        "Candidate evidence version does not match the APL-REL-014 contract.",
    )
    require(
        str(candidate.get("supported_predecessor_version")) == contract["predecessor"]["version"],
        "Candidate predecessor version does not match the APL-REL-014 contract.",
    )
    require(
        norm_commit(candidate.get("candidate_source_commit"), "candidate_source_commit")
        == contract["candidate_source_commit"],
        "Candidate source commit does not match the immutable accepted candidate.",
    )

    expected = contract["candidate"]
    app = candidate.get("application")
    require(isinstance(app, dict), "candidate_evidence.application is missing.")
    require(
        norm_hash(app.get("sha256"), "candidate_evidence.application.sha256")
        == expected["application_sha256"],
        "Candidate application hash does not match the APL-REL-014 contract.",
    )

    checks = candidate.get("checks")
    require(isinstance(checks, dict), "candidate_evidence.checks is missing.")
    for name in (
        "single_application_build",
        "portable_application_identity",
        "setup_installed_application_identity",
        "ci_upgrade_0_2_3_to_0_2_4",
        "fresh_install",
        "repair",
        "uninstall",
        "windows_rc_acceptance",
    ):
        require(str(checks.get(name)) == "PASS", f"Candidate CI gate did not PASS: {name}")

    return candidate


def assert_physical(contract: dict[str, Any], physical: dict[str, Any]) -> dict[str, Any]:
    physical_contract = contract["physical_evidence"]
    require(
        physical.get("schema") == physical_contract["schema"],
        "Physical evidence schema does not match the canonical APL-WIN-014 final runner.",
    )
    require(
        physical.get("task") == physical_contract["task"],
        "Physical evidence task is not APL-WIN-014.",
    )
    require(physical.get("result") == "PASS", "Authoritative physical result is not PASS.")
    require(str(physical.get("host") or "").strip() != "", "Physical evidence host is missing.")
    require(str(physical.get("started_utc") or "").strip() != "", "Physical evidence start time is missing.")
    require(str(physical.get("finished_utc") or "").strip() != "", "Physical evidence finish time is missing.")
    require(
        norm_commit(physical.get("candidate_source_commit"), "physical candidate_source_commit")
        == contract["candidate_source_commit"],
        "Physical result is for a different candidate source commit.",
    )
    require(
        norm_hash(physical.get("candidate_setup_sha256"), "physical candidate_setup_sha256")
        == contract["candidate"]["setup_sha256"],
        "Physical result Setup hash does not match the selected release candidate.",
    )
    require(
        norm_hash(physical.get("candidate_application_sha256"), "physical candidate_application_sha256")
        == contract["candidate"]["application_sha256"],
        "Physical result application hash does not match the selected release candidate.",
    )
    require(
        norm_hash(physical.get("predecessor_setup_sha256"), "physical predecessor_setup_sha256")
        == contract["predecessor"]["setup_sha256"],
        "Physical result predecessor Setup hash does not match the sealed predecessor.",
    )

    gates = physical.get("gates")
    require(isinstance(gates, dict), "Physical evidence gates object is missing.")
    for name in physical_contract["required_gates"]:
        require(gates.get(name) == "PASS", f"Physical lifecycle gate did not PASS: {name}")

    app_control = physical.get("app_control")
    require(isinstance(app_control, dict), "Physical evidence app_control object is missing.")
    for name in physical_contract["required_app_control"]:
        require(app_control.get(name) == "PASS", f"Physical App Control gate did not PASS: {name}")

    require(
        physical.get("code_integrity_3077_count")
        == physical_contract["required_code_integrity_3077_count"],
        "Physical result contains Arvectum-related Code Integrity 3077 blocks.",
    )

    runtime = physical.get("runtime")
    require(isinstance(runtime, dict), "Physical runtime evidence is missing.")
    require(runtime.get("pac_http_status") == 200, "Physical PAC HTTP status is not 200.")
    require(int(runtime.get("pac_body_length") or 0) > 100, "Physical PAC body evidence is too small.")
    require(
        str(runtime.get("auto_config_url")) == physical_contract["required_pac_url"],
        "Physical WinINET AutoConfigURL does not match the governed PAC URL.",
    )
    require(int(runtime.get("listener_pid") or 0) > 0, "Physical listener PID is missing.")
    require(int(runtime.get("starter_pid") or 0) > 0, "Physical starter PID is missing.")
    require(
        physical.get("block_reason") in (None, ""),
        "PASS physical evidence unexpectedly has block_reason.",
    )
    return physical


def build_evidence(
    contract_path: Path,
    candidate_path: Path,
    physical_path: Path,
    release_dir: Path,
) -> dict[str, Any]:
    contract = read_json(contract_path)
    require(
        contract.get("schema") == "arvectum.proxy.apl-rel-014-exact-set-contract.v1",
        "APL-REL-014 contract schema is unexpected.",
    )
    require(contract.get("task") == "APL-REL-014", "APL-REL-014 contract task is unexpected.")
    require(
        contract.get("product") == "Arvectum Proxy Launcher",
        "APL-REL-014 contract product is unexpected.",
    )
    contract["candidate_source_commit"] = norm_commit(
        contract.get("candidate_source_commit"), "contract candidate_source_commit"
    )
    for key in ("portable_zip_sha256", "setup_sha256", "application_sha256"):
        contract["candidate"][key] = norm_hash(
            contract["candidate"].get(key), f"contract candidate.{key}"
        )
    for key in ("setup_sha256", "application_sha256"):
        contract["predecessor"][key] = norm_hash(
            contract["predecessor"].get(key), f"contract predecessor.{key}"
        )

    candidate = assert_candidate(contract, read_json(candidate_path))
    physical = assert_physical(contract, read_json(physical_path))

    require(release_dir.is_dir(), f"Release directory does not exist: {release_dir}")
    setup = resolve_release_asset(
        release_dir,
        candidate.get("setup"),
        contract["candidate"]["setup_sha256"],
        "setup",
    )
    portable = resolve_release_asset(
        release_dir,
        candidate.get("portable_zip"),
        contract["candidate"]["portable_zip_sha256"],
        "portable_zip",
    )

    return {
        "schema": SCHEMA,
        "task": "APL-REL-014",
        "product": "Arvectum Proxy Launcher",
        "result": "PASS",
        "scope": "EXACT_PRODUCT_SET_READY_FOR_REL011_SIGNING",
        "version": contract["version"],
        "candidate_source_commit": contract["candidate_source_commit"],
        "release_assets": {
            "setup": setup,
            "portable_zip": portable,
            "application_inside_lifecycle": {
                "sha256": contract["candidate"]["application_sha256"],
            },
        },
        "predecessor": {
            "version": contract["predecessor"]["version"],
            "setup_sha256": contract["predecessor"]["setup_sha256"],
            "application_sha256": contract["predecessor"]["application_sha256"],
        },
        "lifecycle": {
            "source_task": "APL-WIN-014",
            "physical_schema": contract["physical_evidence"]["schema"],
            "host": physical["host"],
            "started_utc": physical["started_utc"],
            "finished_utc": physical["finished_utc"],
            "gates": {
                name: "PASS" for name in contract["physical_evidence"]["required_gates"]
            },
            "app_control": {
                name: "PASS"
                for name in contract["physical_evidence"]["required_app_control"]
            },
            "code_integrity_3077_count": 0,
            "runtime": {
                "listener_pid": int(physical["runtime"]["listener_pid"]),
                "starter_pid": int(physical["runtime"]["starter_pid"]),
                "pac_http_status": 200,
                "pac_body_length": int(physical["runtime"]["pac_body_length"]),
                "auto_config_url": contract["physical_evidence"]["required_pac_url"],
            },
        },
        "source_evidence": {
            "contract_file": contract_path.name,
            "contract_sha256": sha256_file(contract_path),
            "candidate_evidence_file": candidate_path.name,
            "candidate_evidence_sha256": sha256_file(candidate_path),
            "physical_result_file": physical_path.name,
            "physical_result_sha256": sha256_file(physical_path),
        },
        "signed_set_binding": {
            "state": "READY_FOR_REL011_SIGNING",
            "required_signing_mode": contract["russian_release"]["required_signing_mode"],
            "required_signer_thumbprint": contract["russian_release"]["required_signer_thumbprint"],
            "rel013_post_sign_binding_required": True,
            "final_signed_set_pass_claimed": False,
        },
        "generated_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--candidate-evidence", type=Path, required=True)
    parser.add_argument("--physical-result", type=Path, required=True)
    parser.add_argument("--release-directory", type=Path, required=True)
    parser.add_argument(
        "--output",
        type=Path,
        help=f"Canonical output path; defaults to <release-directory>/{CANONICAL_EVIDENCE_NAME}.",
    )
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        release_dir = args.release_directory.resolve()
        output = (
            args.output.resolve()
            if args.output
            else (release_dir / CANONICAL_EVIDENCE_NAME).resolve()
        )
        require(
            output.parent == release_dir and output.name == CANONICAL_EVIDENCE_NAME,
            f"APL-REL-014 evidence must be exactly {CANONICAL_EVIDENCE_NAME} inside the release directory.",
        )
        require(
            args.overwrite or not output.exists(),
            f"APL-REL-014 evidence already exists: {output}. Use --overwrite only before REL-011 signing.",
        )

        evidence = build_evidence(
            args.contract.resolve(),
            args.candidate_evidence.resolve(),
            args.physical_result.resolve(),
            release_dir,
        )
        output.write_text(
            json.dumps(evidence, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    except EvidenceError as exc:
        print(f"APL-REL-014 exact evidence: BLOCK: {exc}", file=sys.stderr)
        return 2
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print(
            f"APL-REL-014 exact evidence: BLOCK: malformed/unavailable input: {exc}",
            file=sys.stderr,
        )
        return 2

    print("APL-REL-014 exact lifecycle/recovery evidence: PASS")
    print(f"Evidence: {output}")
    print("Signed-set state: READY_FOR_REL011_SIGNING")
    print("REL-011 must sign this evidence file as a normal release asset.")
    print("Final signed-set PASS is intentionally deferred to APL-REL-013 post-sign binding.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
