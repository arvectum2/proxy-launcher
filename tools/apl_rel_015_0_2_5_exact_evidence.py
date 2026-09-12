#!/usr/bin/env python3
"""APL-REL-015 exact 0.2.5 CFA hotfix evidence binder.

The binder joins four independently preserved boundaries:

* the exact CI installer candidate/evidence from Windows-installer run 34720855917;
* the exact application bytes that passed owner-operated CFA/reboot acceptance;
* the customer portable ZIP materialized around those exact accepted application bytes;
* the immutable 0.2.5 hotfix contract in the release worktree.

The output is placed inside the final release directory before REL-011 signing so
REL-012/REL-013 can authenticate it with the rest of the exact customer set.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA = "arvectum.proxy.apl-rel-015-cfa-hotfix-evidence.v1"
CANONICAL_EVIDENCE_NAME = "apl-rel-015-cfa-hotfix-evidence.json"
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONTRACT = ROOT / "release" / "APL_REL_015_0_2_5_CFA_HOTFIX_CONTRACT.json"


class EvidenceError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def read_json(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        raise EvidenceError(f"Cannot read JSON evidence: {path}: {exc}") from exc
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise EvidenceError(f"Malformed JSON evidence: {path}: {exc}") from exc
    require(isinstance(value, dict), f"JSON evidence must be an object: {path}")
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


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def norm_hash(value: Any, label: str) -> str:
    text = str(value or "").strip().lower()
    require(len(text) == 64 and all(ch in "0123456789abcdef" for ch in text), f"{label} is not SHA-256.")
    return text


def norm_commit(value: Any, label: str) -> str:
    text = str(value or "").strip().lower()
    require(len(text) == 40 and all(ch in "0123456789abcdef" for ch in text), f"{label} is not a full Git commit.")
    return text


def find_exact_file(root: Path, name: str) -> Path:
    matches = [path for path in root.rglob(name) if path.is_file()]
    require(len(matches) == 1, f"Expected exactly one {name} under {root}; found {len(matches)}.")
    return matches[0]


def require_exact_source_file(path: Path, expected_hash: Any, label: str) -> None:
    require(path.is_file(), f"{label} is missing: {path}")
    actual = sha256_file(path)
    expected = norm_hash(expected_hash, f"{label} expected hash")
    require(actual == expected, f"{label} SHA-256 mismatch: {actual} != {expected}")


def checks_by_id(acceptance: dict[str, Any]) -> dict[str, dict[str, Any]]:
    checks = acceptance.get("checks")
    require(isinstance(checks, list) and checks, "windows-rc-acceptance checks are missing.")
    result: dict[str, dict[str, Any]] = {}
    for item in checks:
        require(isinstance(item, dict), "windows-rc-acceptance contains a malformed check.")
        check_id = str(item.get("id") or "")
        require(check_id and check_id not in result, f"Duplicate/blank RC acceptance check id: {check_id!r}")
        result[check_id] = item
        require(item.get("status") == "PASS", f"RC acceptance check did not PASS: {check_id}")
    require(acceptance.get("failures") == [], "windows-rc-acceptance reports failures.")
    return result


def validate_ci(contract: dict[str, Any], ci_dir: Path) -> dict[str, Any]:
    ci_contract = contract["accepted_installer_candidate"]["ci_evidence"]
    files: dict[str, Path] = {}
    for key, record in ci_contract.items():
        require(isinstance(record, dict), f"Contract CI evidence record malformed: {key}")
        path = find_exact_file(ci_dir, str(record["filename"]))
        require_exact_source_file(path, record["sha256"], f"CI evidence {key}")
        files[key] = path

    setup_name = str(contract["accepted_installer_candidate"]["setup_filename"])
    setup_path = find_exact_file(ci_dir, setup_name)
    require_exact_source_file(setup_path, contract["accepted_installer_candidate"]["setup_sha256"], "accepted CI Setup")

    issue171 = read_json(files["windows_installer_171_e2e"])
    require(issue171.get("schema") == "arvectum.proxy.windows-installer-171-e2e.v2", "Issue #171 evidence schema is unexpected.")
    require(issue171.get("issue") == 171, "Issue #171 evidence has wrong issue identity.")
    require(str(issue171.get("current_version")) == "0.2.5", "Issue #171 evidence is not for 0.2.5.")
    require(issue171.get("result") == "PASS", "Issue #171 evidence is not PASS.")
    require(norm_hash(issue171.get("current_setup_sha256"), "Issue #171 Setup hash") == norm_hash(contract["accepted_installer_candidate"]["setup_sha256"], "contract Setup hash"), "Issue #171 Setup hash mismatch.")
    expected_app = norm_hash(contract["accepted_installer_candidate"]["application_sha256"], "contract application hash")
    require(norm_hash(issue171.get("current_portable_exe_sha256"), "Issue #171 application hash") == expected_app, "Issue #171 portable application hash mismatch.")
    require(norm_hash(issue171.get("final_application_sha256"), "Issue #171 final application hash") == expected_app, "Issue #171 final application hash mismatch.")
    for phase in (
        "active_portable_to_installer",
        "active_runtime_continuity",
        "cfa_safe_localappdata_target",
        "preflight_partial_install_prevention",
    ):
        require(issue171.get("phases", {}).get(phase) == "PASS", f"Issue #171 phase did not PASS: {phase}")
    require(issue171.get("configuration_preserved") is True, "Issue #171 did not preserve configuration.")

    rc = read_json(files["windows_rc_e2e"])
    require(rc.get("schema") == "arvectum.proxy.windows-rc-e2e.v2", "Windows RC lifecycle schema is unexpected.")
    require(str(rc.get("current_version")) == "0.2.5", "Windows RC lifecycle is not for 0.2.5.")
    require(str(rc.get("predecessor_version")) == "0.2.4", "Windows RC predecessor is not 0.2.4.")
    require(rc.get("result") == "PASS", "Windows RC lifecycle is not PASS.")
    require(norm_hash(rc.get("current_setup_sha256"), "Windows RC Setup hash") == norm_hash(contract["accepted_installer_candidate"]["setup_sha256"], "contract Setup hash"), "Windows RC Setup hash mismatch.")
    for phase in (
        "fresh_install_smoke",
        "fresh_uninstall",
        "documents_to_localappdata_upgrade",
        "upgrade",
        "repair",
        "uninstall",
    ):
        require(rc.get("phases", {}).get(phase) == "PASS", f"Windows RC phase did not PASS: {phase}")
    require(rc.get("configuration_preserved") is True, "Windows RC did not preserve configuration.")
    require(rc.get("foreign_startup_preserved") is True, "Windows RC did not preserve foreign startup state.")

    acceptance = read_json(files["windows_rc_acceptance"])
    require(acceptance.get("schema") == "arvectum.proxy.windows-rc-acceptance.v1", "Windows RC acceptance schema is unexpected.")
    require(acceptance.get("product") == "Arvectum Proxy Launcher", "Windows RC acceptance product is unexpected.")
    require(str(acceptance.get("version")) == "0.2.5", "Windows RC acceptance is not for 0.2.5.")
    require(acceptance.get("result") == "PASS", "Windows RC acceptance is not PASS.")
    indexed = checks_by_id(acceptance)
    for required_id in (
        "portable.build_manifest.sha256",
        "portable.exe.identity",
        "lifecycle.fresh_install_smoke",
        "lifecycle.fresh_uninstall",
        "lifecycle.upgrade",
        "lifecycle.repair",
        "lifecycle.uninstall",
        "lifecycle.configuration_preserved",
        "lifecycle.foreign_startup_preserved",
    ):
        require(required_id in indexed, f"Required RC acceptance check is missing: {required_id}")
    recorded_portable = norm_hash(indexed["portable.build_manifest.sha256"].get("detail"), "recorded same-run portable hash")
    require(recorded_portable == norm_hash(contract["accepted_installer_candidate"]["recorded_same_run_portable_sha256"], "contract same-run portable hash"), "RC acceptance same-run portable hash drifted.")
    require(norm_hash(indexed["portable.exe.identity"].get("detail"), "RC application identity") == expected_app, "RC application identity drifted.")

    sums_raw = files["windows_rc_sha256sums"].read_text(encoding="ascii")
    parsed: dict[str, str] = {}
    for line in sums_raw.splitlines():
        if not line.strip():
            continue
        parts = line.split(None, 1)
        require(len(parts) == 2, "Malformed windows-rc-SHA256SUMS line.")
        digest, name = parts[0].lower(), parts[1].strip()
        require(name not in parsed, f"Duplicate windows-rc-SHA256SUMS entry: {name}")
        parsed[name] = norm_hash(digest, f"windows-rc-SHA256SUMS {name}")
    require(parsed.get(setup_name) == norm_hash(contract["accepted_installer_candidate"]["setup_sha256"], "contract Setup hash"), "windows-rc-SHA256SUMS Setup mismatch.")
    portable_name = "Arvectum-Proxy-Launcher-0.2.5-windows-x64-portable.zip"
    require(parsed.get(portable_name) == norm_hash(contract["accepted_installer_candidate"]["recorded_same_run_portable_sha256"], "contract same-run portable hash"), "windows-rc-SHA256SUMS portable mismatch.")
    require(len(parsed) == 2, "windows-rc-SHA256SUMS contains unexpected entries.")

    return {
        "github_run_id": str(contract["accepted_installer_candidate"]["github_run_id"]),
        "artifact_id": str(contract["accepted_installer_candidate"]["artifact_id"]),
        "artifact_zip_sha256": norm_hash(contract["accepted_installer_candidate"]["artifact_zip_sha256"], "installer artifact ZIP hash"),
        "setup_sha256": norm_hash(contract["accepted_installer_candidate"]["setup_sha256"], "Setup hash"),
        "application_sha256": expected_app,
        "recorded_same_run_portable_sha256": recorded_portable,
        "issue_171": "PASS",
        "fresh_install": "PASS",
        "upgrade": "PASS",
        "repair": "PASS",
        "uninstall": "PASS",
        "configuration_preserved": True,
        "foreign_startup_preserved": True,
        "source_files": {key: {"filename": path.name, "sha256": sha256_file(path)} for key, path in files.items()},
    }


def validate_physical(contract: dict[str, Any], physical_path: Path) -> dict[str, Any]:
    pc = contract["physical_acceptance"]
    require_exact_source_file(physical_path, pc["sha256"], "raw 0.2.5 physical evidence")
    physical = read_json(physical_path)
    require(physical.get("schema") == pc["schema"], "Physical evidence schema is unexpected.")
    require(physical.get("result") == pc["required_result"], "Physical evidence is not PASS.")
    require(norm_commit(physical.get("source_commit"), "physical source_commit") == norm_commit(contract["accepted_product_source_commit"], "contract source commit"), "Physical evidence source commit mismatch.")

    application = physical.get("application")
    runtime = physical.get("runtime")
    network = physical.get("network")
    autostart = physical.get("autostart")
    checks = physical.get("checks")
    require(all(isinstance(item, dict) for item in (application, runtime, network, autostart, checks)), "Physical evidence is missing required objects.")

    expected_app = norm_hash(contract["accepted_installer_candidate"]["application_sha256"], "contract application hash")
    require(str(application.get("version")) == "0.2.5", "Physical application version is not 0.2.5.")
    require(norm_hash(application.get("sha256"), "physical application hash") == expected_app, "Physical application hash mismatch.")
    canonical_suffix = "AppData\\Local\\Programs\\ArvectumProxyLauncher\\Arvectum Proxy Launcher.exe".lower()
    app_path = str(application.get("path") or "")
    runtime_path = str(runtime.get("path") or "")
    require(app_path.lower().endswith(canonical_suffix), "Physical application is not in the canonical LocalAppData Programs path.")
    require(runtime_path.lower() == app_path.lower(), "Physical runtime path differs from accepted application path.")
    require(int(runtime.get("pid") or 0) > 0, "Physical runtime PID is missing.")
    expected_command = f'"{app_path}" --start'
    require(str(runtime.get("command_line")) == expected_command, "Physical runtime command line is not the canonical --start command.")
    require(str(autostart.get("value")) == expected_command, "Physical autostart is not the canonical --start command.")

    require(str(network.get("pac_url")) == pc["required_pac_url"], "Physical PAC URL mismatch.")
    require(int(network.get("pac_http_status") or 0) == 200, "Physical PAC did not return HTTP 200.")
    require(str(network.get("local_http_proxy")) == pc["required_local_http_proxy"], "Physical local HTTP proxy mismatch.")
    require(str(network.get("https_test_url")) == pc["required_https_test_url"], "Physical HTTPS test URL mismatch.")
    require(int(network.get("https_status") or 0) == 200, "Physical HTTPS-through-proxy test did not return HTTP 200.")

    for name in pc["required_checks"]:
        require(checks.get(name) is True, f"Physical acceptance check is not true: {name}")

    return {
        "raw_sha256": sha256_file(physical_path),
        "schema": physical["schema"],
        "source_commit": norm_commit(physical["source_commit"], "physical source commit"),
        "timestamp": str(physical.get("timestamp") or ""),
        "boot_time": str(physical.get("boot_time") or ""),
        "result": "PASS",
        "application_sha256": expected_app,
        "runtime_pid": int(runtime["pid"]),
        "runtime_path": runtime_path,
        "runtime_command_line": expected_command,
        "pac_url": pc["required_pac_url"],
        "pac_http_status": 200,
        "https_test_url": pc["required_https_test_url"],
        "https_status": 200,
        "local_http_proxy": pc["required_local_http_proxy"],
        "autostart": expected_command,
        "checks": {name: True for name in pc["required_checks"]},
    }


def validate_portable(contract: dict[str, Any], portable_path: Path) -> dict[str, Any]:
    require(portable_path.is_file(), f"Release portable ZIP is missing: {portable_path}")
    expected_app = norm_hash(contract["portable_materialization"]["required_application_sha256"], "portable required application hash")
    required_static = contract["portable_materialization"]["required_static_members"]
    require(isinstance(required_static, dict) and required_static, "Contract portable static members are missing.")
    expected_names = {"Arvectum Proxy Launcher.exe", "SHA256SUMS.txt", *required_static.keys()}

    try:
        with zipfile.ZipFile(portable_path, "r") as archive:
            names = [item.filename.rstrip("/") for item in archive.infolist() if not item.is_dir()]
            require(len(names) == len(set(names)), "Portable ZIP contains duplicate file names.")
            require(set(names) == expected_names, f"Portable ZIP member set mismatch. actual={sorted(names)}")
            app_bytes = archive.read("Arvectum Proxy Launcher.exe")
            require(sha256_bytes(app_bytes) == expected_app, "Portable ZIP application is not the physically accepted application.")
            internal = archive.read("SHA256SUMS.txt").decode("ascii").strip()
            require(internal == f"{expected_app}  Arvectum Proxy Launcher.exe", "Portable internal SHA256SUMS is incorrect.")
            for name, expected in required_static.items():
                require(sha256_bytes(archive.read(name)) == norm_hash(expected, f"static member {name}"), f"Portable static member hash mismatch: {name}")
    except (OSError, zipfile.BadZipFile, UnicodeDecodeError) as exc:
        raise EvidenceError(f"Cannot validate portable ZIP: {exc}") from exc

    return {
        "filename": portable_path.name,
        "size_bytes": portable_path.stat().st_size,
        "sha256": sha256_file(portable_path),
        "application_sha256": expected_app,
        "member_count": len(expected_names),
        "materialization_policy": contract["portable_materialization"]["policy"],
    }


def validate_toolchain_baseline(contract: dict[str, Any], repo_root: Path) -> dict[str, Any]:
    baseline = contract["inherited_runtime_trust_baseline"]
    python_version_file = repo_root / "BUILD_PYTHON_VERSION"
    lock_file = repo_root / "requirements-build.lock.txt"
    require_exact_source_file(python_version_file, baseline["build_python_version_file_sha256"], "BUILD_PYTHON_VERSION")
    require_exact_source_file(lock_file, baseline["requirements_build_lock_sha256"], "requirements-build.lock.txt")
    require(python_version_file.read_text(encoding="utf-8").strip() == baseline["build_python_version"], "Build Python version drifted from hotfix contract.")
    lock_text = lock_file.read_text(encoding="utf-8")
    require(f"pyinstaller=={baseline['pyinstaller_version']}" in lock_text.splitlines(), "PyInstaller version drifted from hotfix contract.")
    return {
        "status": "PASS",
        "basis": baseline["basis"],
        "accepted_0_2_4_source_commit": norm_commit(baseline["accepted_0_2_4_source_commit"], "inherited 0.2.4 source commit"),
        "build_python_version": baseline["build_python_version"],
        "pyinstaller_version": baseline["pyinstaller_version"],
        "requirements_build_lock_sha256": sha256_file(lock_file),
        "scope": baseline["scope"],
    }


def build_evidence(
    contract_path: Path,
    ci_dir: Path,
    physical_path: Path,
    accepted_application: Path,
    release_dir: Path,
) -> dict[str, Any]:
    contract = read_json(contract_path)
    require(contract.get("schema") == "arvectum.proxy.apl-rel-015-cfa-hotfix-contract.v1", "Unexpected APL-REL-015 contract schema.")
    require(contract.get("task") == "APL-REL-015", "Unexpected APL-REL-015 contract task.")
    require(contract.get("product") == "Arvectum Proxy Launcher", "Unexpected APL-REL-015 contract product.")
    require(str(contract.get("version")) == "0.2.5", "APL-REL-015 contract does not target 0.2.5.")
    contract["accepted_product_source_commit"] = norm_commit(contract.get("accepted_product_source_commit"), "contract accepted product source commit")

    require(release_dir.is_dir(), f"Release directory does not exist: {release_dir}")
    setup_name = str(contract["accepted_installer_candidate"]["setup_filename"])
    setup_path = release_dir / setup_name
    require_exact_source_file(setup_path, contract["accepted_installer_candidate"]["setup_sha256"], "release Setup")

    expected_app = norm_hash(contract["accepted_installer_candidate"]["application_sha256"], "contract application hash")
    require_exact_source_file(accepted_application, expected_app, "accepted installed application")

    portable_path = release_dir / "Arvectum-Proxy-Launcher-0.2.5-windows-x64-portable.zip"
    portable = validate_portable(contract, portable_path)
    ci = validate_ci(contract, ci_dir)
    physical = validate_physical(contract, physical_path)
    baseline = validate_toolchain_baseline(contract, contract_path.resolve().parents[1])

    require(ci["application_sha256"] == expected_app, "CI application identity differs from contract.")
    require(physical["application_sha256"] == expected_app, "Physical application identity differs from contract.")
    require(portable["application_sha256"] == expected_app, "Portable application identity differs from contract.")

    return {
        "schema": SCHEMA,
        "task": "APL-REL-015",
        "product": "Arvectum Proxy Launcher",
        "result": "PASS",
        "scope": "EXACT_0_2_5_CFA_HOTFIX_SET_READY_FOR_REL011_SIGNING",
        "version": "0.2.5",
        "accepted_product_source_commit": contract["accepted_product_source_commit"],
        "release_assets": {
            "setup": {
                "filename": setup_name,
                "size_bytes": setup_path.stat().st_size,
                "sha256": sha256_file(setup_path),
            },
            "portable_zip": portable,
            "accepted_application": {
                "filename": "Arvectum Proxy Launcher.exe",
                "sha256": expected_app,
            },
        },
        "ci_acceptance": ci,
        "physical_acceptance": physical,
        "inherited_runtime_trust_baseline": baseline,
        "source_evidence": {
            "contract_file": contract_path.name,
            "contract_sha256": sha256_file(contract_path),
            "raw_physical_result_file": physical_path.name,
            "raw_physical_result_sha256": sha256_file(physical_path),
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
    parser.add_argument("--ci-artifact-directory", type=Path, required=True)
    parser.add_argument("--physical-result", type=Path, required=True)
    parser.add_argument("--accepted-application", type=Path, required=True)
    parser.add_argument("--release-directory", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        release_dir = args.release_directory.resolve()
        output = args.output.resolve() if args.output else (release_dir / CANONICAL_EVIDENCE_NAME).resolve()
        require(output.parent == release_dir and output.name == CANONICAL_EVIDENCE_NAME, f"APL-REL-015 output must be exactly {CANONICAL_EVIDENCE_NAME} inside the release directory.")
        require(args.overwrite or not output.exists(), f"APL-REL-015 evidence already exists: {output}. Use --overwrite only before REL-011 signing.")
        evidence = build_evidence(
            args.contract.resolve(),
            args.ci_artifact_directory.resolve(),
            args.physical_result.resolve(),
            args.accepted_application.resolve(),
            release_dir,
        )
        output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except EvidenceError as exc:
        print(f"APL_REL_015_RESULT=FAIL: {exc}", file=sys.stderr)
        return 1

    print(f"APL_REL_015_RESULT=PASS")
    print(f"Evidence: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
