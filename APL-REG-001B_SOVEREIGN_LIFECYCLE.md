# APL-REG-001B — Sovereign lifecycle infrastructure

Status: **repository tooling implemented; physical Russian perimeter evidence required before registry filing**  
Decision date: 2026-09-14  
Tracking: #55 / parent #46

## Decision

Proxy Launcher must be buildable, stored and distributed without GitHub or PyPI being available. GitHub may remain a public collaboration/mirror channel, but it is not the filing-grade sovereign lifecycle baseline.

The target production chain is:

`Russian authoritative source → Russian-controlled build host → offline governed inputs → exact release artifacts → Russian authoritative artifact/distribution storage → release evidence bundle`

No provider is considered compliant merely because it is Russian. The physical provider/operator, hosting/control facts and exact release bytes must be evidenced for the submitted release.

## Source storage

Target: Russian-controlled authoritative repository. GitVerse is the current candidate because a mirror already exists, but its current mirror role is not silently promoted to legal/technical proof. Before filing, retain evidence of operator/hosting, Arvectum control, exact commit parity and an export/backup procedure independent of GitHub.

GitHub role after promotion: collaboration/public mirror. Loss of GitHub must not prevent access to the authoritative source or production build.

## Build and compilation

Windows already has the core sovereign-build primitive: `tools/clean_build_windows.ps1 -WheelhousePath ...` forces `--no-index`, `--only-binary`, `--no-deps` and `--require-hashes`. A controlled CPython + wheelhouse archive can already be prepared by `tools/archive_windows_build_inputs.ps1` without network access.

For a filing-grade run:

1. obtain source from the authoritative Russian repository at the exact release commit;
2. place the governed CPython/wheelhouse archive inside the controlled perimeter;
3. verify all archive/hash manifests offline;
4. execute the canonical clean build with `-WheelhousePath` on a Russian-controlled Windows build host;
5. require `out/build-result.json` to record `dependency_mode=offline-hash-locked` and the exact source commit;
6. create the APL-REG-001B release evidence bundle;
7. copy artifacts + evidence to authoritative Russian artifact storage and verify bytes after retrieval.

GitHub Actions remains useful development CI. It is not evidence that the registry production build happened in the required perimeter.

## Object code, artifacts and distribution

GitHub Releases must not be the only authoritative release store. The submitted release needs a Russian-controlled primary artifact/distribution location with recorded operator/location/control, artifact SHA-256, evidence-bundle SHA-256 and a clean-client retrieval verification.

GitHub Releases may remain a secondary public channel if desired.

## Activation / license keys

Current product has no activation service, subscription control plane or license-key server. Registry documentation should state **not applicable for the submitted version**, not invent infrastructure that does not exist.

If such functionality is later introduced, the lifecycle contract becomes fail-closed until the new infrastructure is documented and evidenced.

## Evidence bundle

`tools/apl_reg_001b_release_evidence.py` creates a deterministic registry-facing evidence directory from an already-built release. It intentionally does not upload anywhere and does not contain credentials.

Required core inputs are copied from the exact checkout and build output. Optional release-bound SBOM, IP provenance and signing evidence can be attached when available. A canonical `MANIFEST.sha256` binds every file in the bundle.

The generator rejects:

- missing core governance files;
- a build manifest not using `offline-hash-locked` dependency mode;
- missing or malformed source commit;
- product/version mismatch;
- artifact hash mismatch.

This means repository automation cannot falsely turn a GitHub build into `filing-grade` evidence.

## Physical acceptance still required

Repository completion of APL-REG-001B does **not** mean the external infrastructure is already proven. Before #55 can be closed as filing-grade complete, collect private/controlled evidence for:

- authoritative Russian source storage;
- Russian-controlled production build host and offline run;
- authoritative Russian artifact/distribution storage;
- exact release retrieval/hash verification.

Credentials, private keys, УКЭП material, personal data and sensitive corporate documents stay outside the public repository.

## Relationship to other work

- APL-IP-002: completed inventory; this task implements its lifecycle handoff.
- APL-IP-001: still owns final human/legal IP provenance and release-bound legal disposition.
- APL-REG-001C: separately proves compatibility on two qualifying trusted operating systems.
- APL-REL-016: separately governs Windows public signing/trust for 0.2.6+.
- v0.2.5 remains immutable.
