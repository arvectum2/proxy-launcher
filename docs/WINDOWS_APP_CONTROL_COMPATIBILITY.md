# APL-WIN-014 — Windows application-control execution compatibility

Status: **AUTONOMOUS IMPLEMENTATION / REAL APP-CONTROL ACCEPTANCE PENDING**

## Problem

Windows `0.2.3` is governed by the Russian-first release contour: the exact release manifest is signed and verified with the controlled CryptoPro/Rutoken identity. That detached signature proves release-set integrity and provenance but does not embed a Windows Authenticode signature into the executable.

A real owner workstation with Windows application-control enforcement refused to execute the restored legacy Arvectum Proxy Launcher EXE. The same host recovered successfully when the product was run from repository source under an already trusted controlled Python runtime.

This proves that release provenance and Windows execution trust are separate controls.

Microsoft's current Windows guidance makes the same distinction:

- Smart App Control can block unsigned code when its cloud reputation is insufficient;
- Smart App Control treats a valid RSA code-signing signature from a trusted provider as an execution-trust signal;
- App Control for Business supports organization-defined file rules including exact hash rules;
- App Control for Business supports managed-installer trust for software deployed by an organization-designated installation system;
- supplemental policies extend an approved base policy by union, but the base policy must explicitly allow supplements;
- with App Control script enforcement active, PowerShell runs policy-authorized scripts in `FullLanguage` and untrusted scripts in `ConstrainedLanguage`.

## Non-negotiable security rules

1. Do **not** disable Smart App Control, App Control for Business, Defender application-control policy, script enforcement, or comparable Windows protections as a product workaround.
2. Do **not** change `VerifiedAndReputablePolicyState` from Arvectum tooling.
3. Do **not** claim that the current detached Russian release signature provides SmartScreen, Smart App Control or Authenticode execution trust.
4. Do **not** deploy App Control policy automatically from an Arvectum release or installer.
5. Customer App Control deployment is an administrator/governance action owned by the customer's IT/security team.
6. Hash trust is exact-byte trust. New or rebuilt bytes require a new trust pack.
7. App Control rule option 11 (`Disabled:Script Enforcement`) is forbidden in the Arvectum product supplemental policy.
8. Release maintenance scripts may run in `FullLanguage` only because their exact release bytes are explicitly hash-authorized by the product supplemental policy.
9. A normal owner workstation is not an APL-REL-014 destructive acceptance environment.

## Russian-first target architecture

APL-WIN-014 uses two independent trust planes.

### Plane A — Russian release provenance

Unchanged from the existing release contour:

- exact release `v0.2.3-ru.2`;
- detached CryptoPro/Rutoken signature and signer identity;
- exact production release manifest;
- published release gate `PUBLISH`;
- exact installer, portable ZIP and application hashes.

This remains the primary Arvectum evidence of release origin/integrity for the Russian market.

### Plane B — Windows execution authorization

For managed Russian B2B/government deployments, the primary path is **App Control for Business enterprise trust**, not disabling Windows security and not treating the Russian detached signature as Authenticode.

Two supported enterprise profiles are implemented.

#### Profile 1 — exact-hash supplemental policy

Canonical generator:

`tools/windows_app_control_enterprise_trust_pack.ps1`

The generator:

1. verifies the exact Russian release before policy creation;
2. verifies the pinned installer, portable ZIP and application hashes;
3. statically validates the exact Inno Setup 6.7.1 child runtime derived from the sealed Setup;
4. verifies `upgrade_helper.ps1` and `uninstall_helper.ps1` against the sealed `build_manifest.json`;
5. creates a multi-policy-format App Control policy using exact `Hash` rules for PE files and the exact release maintenance scripts;
6. explicitly rejects generated XML containing rule option 11 (`Disabled:Script Enforcement`);
7. converts the result to a supplemental policy for a customer-supplied base policy ID;
8. emits XML + binary `.cip` + `trust-pack.json` + checksums + deployment guidance;
9. never deploys the generated policy;
10. never changes Smart App Control/App Control state.

Modes:

- `BootstrapHash` — exact production Setup + exact application EXE + exact `upgrade_helper.ps1` / `uninstall_helper.ps1` + exact Inno Setup 6.7.1 child runtime. Useful as a narrow bootstrap allow-list that can actually execute the sealed install helper without weakening PowerShell script enforcement.
- `ReferenceFullHash` — all `BootstrapHash` material plus the complete exact installed reference tree. This is the required hash mode for lifecycle coverage because generated maintenance binaries such as the Inno uninstaller must also be authorized.

`ReferenceFullHash` must be generated only from an isolated reference installation whose application EXE, cached repair Setup and maintenance helper scripts match the sealed production identities exactly.

### Why maintenance scripts must be in the policy

The sealed Inno installer executes `upgrade_helper.ps1` during installation. That helper uses .NET APIs which are intentionally unavailable to an untrusted PowerShell script in `ConstrainedLanguage`. Uninstall similarly executes `uninstall_helper.ps1`.

Therefore a correct App Control policy must not solve installation by disabling script enforcement. It must explicitly authorize the exact release helper script bytes. This preserves the desired boundary:

- interactive/unrelated PowerShell remains constrained by the organization policy;
- exact release helper scripts are policy-trusted and may execute in `FullLanguage`;
- any changed helper bytes require a regenerated release-specific hash policy.

The verifier `tools/windows_app_control_verify_runtime_trust_pack.ps1` fails closed if:

- `script_enforcement_preserved` is absent/false;
- either maintenance helper is missing from `trust-pack.json`;
- reference helper hashes do not match the sealed helper hashes;
- the policy XML contains `Disabled:Script Enforcement`;
- either helper has no App Control hash rule;
- helper hash rules are not bound into UMCI SigningScenario 12.

A customer's base policy must enable rule option 17 (`Allow Supplemental Policies`). If the base policy is signed, the customer's policy governance must also authorize the supplemental-policy signer; Arvectum tooling does not alter that base-policy trust configuration.

#### Profile 2 — customer Managed Installer

For managed fleets using Intune, Configuration Manager or another organization-governed deployment system, Managed Installer is a sustainable path when the customer's security model accepts its trade-offs.

Arvectum supplies:

- the exact release set;
- Russian signature verification evidence;
- exact hashes;
- the trust-pack manifest and deployment boundary.

Customer IT designates and governs the managed installer. Arvectum does not silently mark itself as a managed installer and does not modify the customer's base policy.

Managed Installer can reduce per-release hash-policy churn, but it is heuristic trust and is not equivalent to explicit hash/publisher rules. Microsoft documents important limitations: self-updated files do not automatically retain managed-installer origin, generated/downloaded binaries can require additional authorization, and administrator-level deployment requires careful security review. Therefore every Arvectum update used with this profile must be deployed through the customer's approved managed installer or separately authorized by policy.

For high-assurance deployments where exact release bytes are fixed, `ReferenceFullHash` remains the more deterministic Arvectum-supplied policy artifact.

## Read-only assessment

Canonical script:

`tools/windows_app_control_assess.ps1`

It records without mutation:

- Windows version/build;
- `VerifiedAndReputablePolicyState` if present;
- effective Code Integrity policies via `CiTool -lp -json` when available;
- installed/release Authenticode state;
- exact release verification result;
- whether the installed EXE matches the sealed release EXE;
- a conservative recommended path.

The script contains no App Control deployment or policy-changing operation.

## Safe permanent owner/developer path

Canonical script:

`tools/windows_owner_source_mode.ps1`

The owner workstation may remain in a supported **source-mode owner/developer profile** while the public embedded-signing question remains unresolved.

This profile:

- runs repository source under the controlled local Python runtime;
- preserves the existing persistent proxy settings under LocalAppData;
- keeps the desktop shortcut on the source GUI;
- maintains a source rollback recovery Run entry;
- deliberately keeps main runtime autostart disabled, avoiding an unordered `--start` versus `--rollback` Windows Run race;
- records Python SHA-256, repository commit/clean state and a recovery snapshot;
- does not change Smart App Control or App Control policy;
- does not require the blocked unsigned legacy EXE.

The owner starts the product from the normal desktop shortcut after logon. This is a permanent **owner/developer operating profile**, not a customer production distribution format.

## Why no automatic Smart App Control conversion on the owner workstation

Smart App Control is a consumer/small-business policy layer built on Windows application-control technology. Microsoft documents that turning Smart App Control off is effectively one-way without resetting/reinstalling Windows.

Therefore Arvectum tooling must not convert the owner's current Smart App Control state into an enterprise App Control policy merely to permit Arvectum. Any such policy transition requires an explicit workstation/security-management decision outside this task.

## CI / contract verification

APL-WIN-014 repository contracts include:

- ASCII/Windows PowerShell 5.1 parse safety for the new scripts;
- static proof that the assessment script is read-only;
- static proof that trust-pack generation verifies the exact Russian release before policy creation;
- static proof that generated policy uses `Hash`, `MultiplePolicyFormat`, a customer base policy ID and `ConvertFrom-CIPolicy`;
- static proof that the product policy does not use `-NoScript`, rejects `Disabled:Script Enforcement`, and includes both exact maintenance helpers;
- runtime verifier proof that helper rules are present in UMCI SigningScenario 12 and script enforcement remains enabled;
- static proof that the generator does not invoke `CiTool --update-policy` or mutate Smart App Control registry state;
- Windows ConfigCI smoke generation of a non-deployed supplemental hash policy;
- owner source-mode contract proving it is non-production, main runtime autostart is disabled, and App Control state is unchanged.

## Required customer/real-host acceptance

Autonomous implementation does **not** replace a real App Control environment.

APL-WIN-014 production-distribution acceptance requires a representative organization-managed Windows 11 host or disposable VM with App Control for Business enabled.

Minimum acceptance matrix:

1. read-only assessment captured;
2. customer base policy identity confirmed and supplemental-policy permission confirmed;
3. exact release verification PASS;
4. enterprise trust pack generated from exact production bytes;
5. policy tested in the customer's normal audit/staging procedure;
6. exact Setup allowed without disabling protection or script enforcement;
7. exact `upgrade_helper.ps1` runs as a policy-authorized script while unrelated PowerShell remains constrained;
8. installed application first launch allowed;
9. proxy core start / GUI / PAC / rollback work;
10. cached repair works;
11. upgrade path works with the new release's corresponding trust policy or Managed Installer;
12. exact `uninstall_helper.ps1` and generated uninstaller work;
13. no unrelated application or script is newly trusted by the Arvectum supplemental rules;
14. Russian detached release signature remains independently verifiable.

For exact-hash fleet deployment, use `ReferenceFullHash`; `BootstrapHash` alone is not sufficient evidence for generated uninstaller/maintenance-binary coverage.

## Public/unmanaged Windows distribution

Smart App Control public execution remains a separate boundary. Microsoft's current Smart App Control guidance requires a supported trusted RSA code-signing path for deterministic signature-based admission. The currently governed Russian qualified certificate is `RELEASE-EVIDENCE-ONLY` and does not satisfy that public execution-trust requirement.

Russian/domestic embedded-signing options must continue to be investigated first. International Microsoft-trusted public code signing remains a lower-priority fallback, not the default Russian-market dependency.

## Relation to APL-REL-014

APL-REL-014 destructive lifecycle acceptance is prohibited on a normal owner workstation after the 2026-08-20 incident. It may run only in a disposable/isolated Windows acceptance environment.

Canonical incident evidence:

`docs/evidence/APL_REL_014_OWNER_HOST_INCIDENT_2026-08-20.md`
