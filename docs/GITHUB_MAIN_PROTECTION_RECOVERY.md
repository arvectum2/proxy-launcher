# GitHub `main` protection recovery after canonical repository migration

Updated: 2026-09-10  
Repository: `arvectum2/proxy-launcher`  
Branch: `main`  
Status: **ADMIN PENDING**

## Observed state

On 2026-09-10 the GitHub branch API for the new canonical repository reports:

- `protected: false`;
- `protection.enabled: false`;
- required status-check enforcement: `off`;
- required status contexts/checks: empty.

This means branch governance did not survive the latest repository/account recovery. Until protection is restored, direct writes to `main` are technically possible and the repository must not be treated as having the governed protected-main contract.

## Required restored contract

Restore the following effective policy for `main`:

1. changes reach `main` through a pull request;
2. approvals required: 0 unless separately changed by an explicit governance decision;
3. required status check: `build`;
4. require the branch to be up to date before merging (`strict` status checks);
5. require conversation resolution before merging;
6. do not allow force pushes;
7. do not allow branch deletion;
8. apply the rule to administrators / do not allow a normal administrator bypass that silently defeats the gate.

Do not add unrelated requirements such as signed commits or linear history unless a separate project decision introduces them.

## GitHub UI path

Repository **Settings -> Rules -> Rulesets** or **Settings -> Branches**, depending on the GitHub UI presented for the account.

Create/restore a rule targeting `main` with the contract above.

## Verification

After saving the rule, verify all of the following:

- branch API reports `protected: true`;
- required status checks include `build`;
- strict/up-to-date enforcement is enabled;
- pull-request boundary is active;
- conversation resolution is required;
- force push and deletion are disabled;
- administrator behavior matches the no-silent-bypass contract.

Then perform a negative acceptance test:

1. create a harmless documentation branch/PR;
2. while required `build` is queued or running, attempt the normal merge path;
3. GitHub must reject the merge because the required check is incomplete;
4. after the check succeeds, the normal merge path may become available.

Record the branch API state, PR number, required-check state and rejected merge result in a dated evidence file under `docs/evidence/`.

## Automation boundary

The connected ChatGPT GitHub integration can read branch state and work with repository contents/PRs, but the currently exposed connector actions do not provide branch-protection/ruleset administration mutation. Therefore saving the protection rule is an explicit repository-owner/admin action and must not be falsely recorded as automated PASS.

## Completion definition

This recovery is complete only after the live `arvectum2/proxy-launcher` branch reports protection enabled and the negative required-check merge acceptance test passes. Until then repository migration remains **ADMIN PENDING** for governance even if source/CI reconciliation is otherwise green.
