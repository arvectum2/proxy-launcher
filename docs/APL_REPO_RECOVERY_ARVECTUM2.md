# APL-REPO-RECOVERY — arvectum2 canonical migration reconciliation

**Status:** CONTENT RECONCILIATION PREPARED / EXACT-SHA CI PENDING / MAIN PROTECTION ADMIN PENDING  
**Decision date:** 2026-09-10  
**Canonical repository:** `arvectum2/proxy-launcher`  
**Canonical branch:** `main`

## Context

The previous GitHub account became unavailable. The repository was restored from the downstream mirror into the new GitHub account `arvectum2` with history and tags preserved. From 2026-09-10 forward, `arvectum2/proxy-launcher` is the canonical GitHub source of truth for Arvectum Proxy Launcher.

Historical references to previous GitHub identities may remain only where they are required to preserve provenance, closed acceptance, immutable release baselines, truthful Git history, or tooling that deliberately records a historical source identity. They must not be used by current operational documentation, release policy, active support URLs, current legal drafts, or maintained source as the active repository identity.

## Reconciliation checks

- [x] Repository exists as `arvectum2/proxy-launcher`; default/canonical branch is `main`.
- [x] Restored `main` head before reconciliation: `6b81b83c0ecbecc0f11f8cec212682d4c04fdc0e`.
- [x] Historical tags are present after recovery, including `v0.2.3` and APL-WIN-014 transfer/evidence tags.
- [x] GitVerse mirror workflow uses `${{ github.repository }}` for the GitHub source and therefore follows the new owner automatically.
- [x] A post-migration GitVerse mirror run passed on the restored baseline.
- [x] No GitHub Releases are currently present in the restored repository.
- [x] Current release policy is rebound to `arvectum2/proxy-launcher`.
- [x] Current installer/support URLs and user-facing Windows documentation are rebound to `arvectum2/proxy-launcher`.
- [x] Current APL-IP-001 pending sign-off/addendum/template identify the new canonical repository while preserving immutable candidate commit/tree/hash identities.
- [x] Repository hygiene guard rejects retired repository slugs in current files and permits them only through an explicit bounded historical-file allowlist or historical evidence/baseline directories.
- [x] Canonical roadmap and local/human backlog are refreshed for the 2026-09-10 migration state.
- [x] Current `main` branch-protection state was inspected on 2026-09-10 and is **disabled** (`protected=false`).
- [ ] Restore governed `main` protection through the owner/admin UI and perform the negative required-check merge acceptance test.
- [ ] Obtain post-reconciliation Windows portable and Windows installer push CI PASS on one exact canonical SHA.
- [ ] Obtain SAST/provenance/SBOM and exact-SHA Release Evidence Package as required by release policy.
- [ ] Confirm GitVerse mirror PASS for that same exact canonical SHA.

## Historical-reference boundary

The repository contains intentionally preserved historical repository slugs in a small number of files. Examples include closed Gate R1–R3 records, superseded sign-off material, sealed APL-WIN-014 evidence workflow material, and scripts that verify/write the exact historical source identity of the retained `0.2.2 P0.4` baseline.

These references are not current operational authorities. `tests/test_repository_hygiene.py` keeps the exception list explicit and bounded so a retired slug cannot silently return elsewhere.

## Branch-protection finding

The new canonical repository currently reports:

```text
main.protected = false
protection.enabled = false
required status-check enforcement = off
```

This is an administrative migration regression. Restore the contract in `docs/GITHUB_MAIN_PROTECTION_RECOVERY.md` before treating repository governance as complete.

## Release consequence

GitHub Actions history from the previous repository is not treated as current-repository Actions evidence. The first production release from `arvectum2/proxy-launcher` must therefore use an exact candidate SHA for which the required release CI/evidence chain exists in this repository.

The historical `v0.2.3` tag is immutable and must not be moved to a new tree. Because repository/support/governance content has changed after that tag, a future new stable publication must use a new SemVer version/tag rather than retargeting `v0.2.3`. If the scope remains patch-level release/migration hardening, `0.2.4` is the natural candidate once the release candidate is deliberately selected.

## Completion definition

Repository migration reconciliation is complete only when:

1. current repository identity remains clean under the permanent guard;
2. required CI/release evidence passes on the exact canonical SHA in `arvectum2`;
3. GitVerse mirrors that SHA successfully;
4. `main` protection is restored and proven by negative merge acceptance.

Until all four are true, do not classify the migration as fully closed for production governance.
