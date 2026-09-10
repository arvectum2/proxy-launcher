# APL-REPO-RECOVERY — arvectum2 canonical migration reconciliation

**Status:** IN PROGRESS  
**Decision date:** 2026-09-10  
**Canonical repository:** `arvectum2/proxy-launcher`  
**Canonical branch:** `main`

## Context

The previous GitHub account became unavailable. The repository was restored from the downstream mirror into the new GitHub account `arvectum2` with branches, tags and history preserved. From this point forward, `arvectum2/proxy-launcher` is the canonical GitHub source of truth for Arvectum Proxy Launcher.

Historical references to previous GitHub identities may remain only where they are required to preserve provenance, evidence, immutable release baselines, or truthful Git history. They must not be used by current operational documentation, release policy, CI/CD configuration, scripts, or maintained source as the active repository identity.

## Reconciliation checks

- [x] Repository exists as `arvectum2/proxy-launcher` and default branch is `main`.
- [x] Restored `main` head before reconciliation: `6b81b83c0ecbecc0f11f8cec212682d4c04fdc0e`.
- [x] Historical tags are present after recovery, including `v0.2.3` and the APL-WIN-014 transfer/evidence tags.
- [x] GitVerse mirror workflow uses `${{ github.repository }}` for the GitHub source and therefore follows the new owner automatically.
- [x] GitVerse mirror workflow completed successfully on the restored `main` SHA after migration.
- [x] No GitHub Releases are currently present in the restored repository; a production release must therefore be created afresh from a post-migration approved main SHA.
- [ ] Replace current-governance references to retired repository slugs with `arvectum2/proxy-launcher`.
- [ ] Strengthen repository hygiene tests so retired GitHub slugs cannot return to maintained current files.
- [ ] Run post-migration CI on the new canonical main SHA.
- [ ] Confirm Windows portable and Windows installer push CI PASS on the exact post-migration SHA.
- [ ] Confirm SAST PASS and generate Release Evidence Package for the exact post-migration SHA.
- [ ] Confirm GitVerse mirror PASS for the exact post-migration SHA.

## Release consequence

CI history from the previous GitHub repository is not treated as current-repository Actions evidence. The release workflow requires successful Windows portable, Windows installer, and exact-SHA release evidence runs in the active repository. Therefore the first production release from `arvectum2/proxy-launcher` must use a post-migration `main` commit that has rebuilt its required CI evidence in the new GitHub account.

Do not move or reuse immutable historical release tags to manufacture this evidence. If `v0.2.3` already exists as a historical tag, follow the canonical version policy for the next publishable version rather than retargeting it.

## Completion definition

This reconciliation is complete when current repository identity is normalized to `arvectum2/proxy-launcher`, the permanent hygiene guard passes, required release CI has passed on the exact canonical SHA in the new GitHub repository, and GitVerse mirrors that SHA successfully.
