# GitHub `main` protection acceptance — 2026-09-10

Purpose: re-prove repository-governance enforcement after migration to the current canonical owner `arvectum2`.

Canonical repository: `arvectum2/proxy-launcher`
Canonical branch: `main`
Baseline `main` SHA before this acceptance: `1560f0650a0c819ad26dda6020f9583dd88abcf1`
Ruleset: `Protect main` (`id=22763244`)

Observed ruleset configuration before the negative test:
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

## Negative merge test

Status: **TEST IN PROGRESS**.

A normal merge will be attempted on this acceptance PR before required `build` completes. The expected result is rejection by GitHub repository rules. The observed HTTP/result and PR head SHA will replace this paragraph before the PR is merged.

No product/runtime behavior is changed by this acceptance record.
