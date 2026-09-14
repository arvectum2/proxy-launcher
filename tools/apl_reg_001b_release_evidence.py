#!/usr/bin/env python3
"""Create a fail-closed APL-REG-001B release evidence bundle.

No network access and no upload are performed. Run this from the exact release
checkout after the canonical offline Windows build has completed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def require_file(path: Path) -> None:
    if not path.is_file():
        raise SystemExit(f"required file missing: {path}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-result", default="out/build-result.json")
    parser.add_argument("--artifact", help="Release artifact path; defaults to ZIP named by build-result.json")
    parser.add_argument("--output", default="artifact/apl-reg-001b-evidence")
    parser.add_argument("--sbom", help="Optional release-bound CycloneDX SBOM")
    parser.add_argument("--ip-provenance", help="Optional release-bound IP provenance manifest")
    parser.add_argument("--signing-evidence", action="append", default=[], help="Optional signing evidence file; repeatable")
    args = parser.parse_args()

    build_path = (ROOT / args.build_result).resolve() if not Path(args.build_result).is_absolute() else Path(args.build_result)
    require_file(build_path)
    build = load_json(build_path)

    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if build.get("product") != "Arvectum Proxy Launcher":
        raise SystemExit("build-result product mismatch")
    if build.get("version") != version:
        raise SystemExit(f"build-result version mismatch: {build.get('version')!r} != {version!r}")
    if build.get("dependency_mode") != "offline-hash-locked":
        raise SystemExit("filing evidence requires dependency_mode=offline-hash-locked")
    source_commit = str(build.get("source_commit", "")).lower()
    if not COMMIT_RE.fullmatch(source_commit):
        raise SystemExit("build-result source_commit must be an exact 40-character Git commit")

    artifact = Path(args.artifact) if args.artifact else ROOT / "out" / str(build.get("zip_file", ""))
    if not artifact.is_absolute():
        artifact = (ROOT / artifact).resolve()
    require_file(artifact)
    artifact_hash = sha256(artifact)
    if artifact_hash != str(build.get("zip_sha256", "")).lower():
        raise SystemExit("release artifact SHA256 does not match build-result.json")

    core = [
        ROOT / "THIRD_PARTY_NOTICES.txt",
        ROOT / "BUILD_PYTHON_VERSION",
        ROOT / "requirements-build.lock.txt",
        ROOT / "requirements-build.windows-x64.hashes.txt",
        ROOT / "compliance" / "APL_IP_002_STACK_SOVEREIGNTY.json",
        ROOT / "compliance" / "APL_REG_001B_SOVEREIGN_LIFECYCLE.json",
    ]
    for path in core:
        require_file(path)

    output = Path(args.output)
    if not output.is_absolute():
        output = (ROOT / output).resolve()
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    copied: list[Path] = []

    def copy(path: Path, name: str | None = None) -> None:
        dest = output / (name or path.name)
        if dest.exists():
            raise SystemExit(f"duplicate evidence filename: {dest.name}")
        shutil.copy2(path, dest)
        copied.append(dest)

    copy(build_path)
    copy(artifact)
    for path in core:
        copy(path)

    optional_paths = []
    for value in [args.sbom, args.ip_provenance, *args.signing_evidence]:
        if value:
            p = Path(value)
            if not p.is_absolute():
                p = (ROOT / p).resolve()
            require_file(p)
            optional_paths.append(p)
    for path in optional_paths:
        copy(path)

    evidence = {
        "schema": "arvectum.proxy.apl-reg-001b.release-evidence.v1",
        "status": "REPOSITORY_BUNDLE_READY_PHYSICAL_RUSSIAN_PERIMETER_EVIDENCE_REQUIRED",
        "product": "Arvectum Proxy Launcher",
        "version": version,
        "source_commit": source_commit,
        "dependency_mode": build["dependency_mode"],
        "artifact": artifact.name,
        "artifact_sha256": artifact_hash,
        "activation_or_license_server": False,
        "github_is_authoritative_registry_evidence": False,
        "physical_acceptance_required": [
            "authoritative Russian source storage evidence",
            "Russian-controlled build host/offline run evidence",
            "authoritative Russian artifact/distribution evidence",
            "clean-client retrieval and SHA256 verification",
        ],
    }
    evidence_path = output / "APL_REG_001B_RELEASE_EVIDENCE.json"
    evidence_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    copied.append(evidence_path)

    manifest_lines = [f"{sha256(path)}  {path.name}" for path in sorted(copied, key=lambda p: p.name)]
    manifest_path = output / "MANIFEST.sha256"
    manifest_path.write_text("\n".join(manifest_lines) + "\n", encoding="ascii")

    print(f"APL-REG-001B evidence bundle prepared: {output}")
    print(f"Artifact SHA256: {artifact_hash}")
    print("Status: repository bundle ready; physical Russian perimeter evidence still required.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
