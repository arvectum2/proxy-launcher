# GitHub `main` protection recovery after canonical repository migration

Updated: 2026-09-10  
Repository: `arvectum2/proxy-launcher`  
Branch: `main`  
Status: **DONE**

## Current live state

The current canonical repository uses active repository ruleset `Protect main` (`id=22763244`) targeting the default branch.

Verified configuration on 2026-09-10:

- `main` reports `protected: true`;
- ruleset enforcement is `active`;
- changes must reach `main` through a pull request;
- approvals required: 0;
- required status check: `build`;
- strict/up-to-date status-check enforcement is enabled;
- review-thread resolution is required;
- branch deletion is blocked;
- non-fast-forward / force-push updates are blocked;
- bypass actor list is empty;
- `current_user_can_bypass = never`.

The legacy branch-protection subobject may show `protection.enabled=false` because enforcement is supplied by a repository ruleset rather than the older branch-protection-rule mechanism. The effective branch state and ruleset are the governing source of truth.

## Negative acceptance

The migration governance boundary was first proven on PR #1 (`test: verify main branch protection`) in the current `arvectum2/proxy-launcher` repository. The test PR was closed without merge after verifying that the required `build` boundary blocked the normal merge path while the check was incomplete.

A supplemental re-verification was performed later on PR #4 after APL-WIN-014 production-runtime trust integration. On initial PR head `370a76f1dd635419aeee1ae0a81180e4e5945b3e`, a normal merge attempt while `build` was in progress was rejected with HTTP `405 Repository rule violations found` and explicit reason `Required status check "build" is in progress.`

Evidence: `docs/evidence/GITHUB_MAIN_PROTECTION_ACCEPTANCE_2026-09-10.md`.

## Completion

Repository migration governance is **CLOSED** for `arvectum2/proxy-launcher`.

This does not close product/release gates that require the physical Windows acceptance host, owner-operated signing, or human/legal approval.
