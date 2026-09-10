# GitHub `main` protection acceptance — 2026-09-10

Purpose: supplemental re-verification of repository-governance enforcement after migration to the current canonical owner `arvectum2`.

Canonical repository: `arvectum2/proxy-launcher`
Canonical branch: `main`
Baseline `main` SHA before this supplemental acceptance: `1560f0650a0c819ad26dda6020f9583dd88abcf1`
Ruleset: `Protect main` (`id=22763244`)

The canonical migration negative acceptance had already been completed earlier on PR #1 (`test: verify main branch protection`), which was closed without merge after proving the required-check boundary. This file records a second independent confirmation performed while reconciling stale backlog documentation.

Observed live ruleset configuration:
- enforcement: `active`;
- target: default branch;
- pull request required;
- required approvals: 0;
- required review-thread resolution: enabled;
- required status check: `build` (GitHub Actions integration 15368);
- strict/up-to-date required status checks: enabled;
- branch deletion blocked;
- non-fast-forward/force-push blocked;
- bypass actors: none;
- current connected identity bypass: never.

## Supplemental negative merge test

PR: `#4 test(governance): re-prove arvectum2 main protection`
Initial PR head: `370a76f1dd635419aeee1ae0a81180e4e5945b3e`

A normal merge was attempted immediately while required `build` was still in progress. GitHub rejected the merge with HTTP `405 Repository rule violations found` and the explicit reason:

`Required status check "build" is in progress.`

Result: **PASS** — the current `arvectum2/proxy-launcher` ruleset actively prevents a normal merge before the required `build` check succeeds.

This supplemental test does not replace or invalidate the earlier PR #1 acceptance; it corroborates it after subsequent APL-WIN-014 changes.

No product/runtime behavior is changed by this acceptance record.
