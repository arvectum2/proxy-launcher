# APL-REL-016 — Windows public trust decision packet

Status: `REVIEW-READY / no production choice approved`
Date: `2026-09-14`
Repository: `arvectum2/proxy-launcher`
Issue: `#30`
Release boundary: `v0.2.5` is immutable; any Authenticode/public-trust change belongs to `0.2.6+`.

## 1. Purpose

Prepare a Product Owner/Owner decision on Windows public trust without treating research, repository edits, certificate availability, or technical feasibility as approval to purchase a certificate, enroll a signing service, sign production binaries, publish a release, or mutate `v0.2.5`.

The current public `v0.2.5` Windows installer is governed and byte-identified but unsigned at the PE/Authenticode layer. The existing CryptoPro/Rutoken detached signature remains a separate Russian release-evidence layer and must not be described as Microsoft-native publisher trust.

## 2. Current Microsoft trust model

As of 2026-09-14, Microsoft documents three materially different concepts that must remain separate:

1. **Authenticode signature validation / publisher identity.** A Windows binary can carry a code-signing signature whose certificate chains to a provider trusted by Windows. For Smart App Control, Microsoft currently requires RSA-based signing; ECC signatures are not currently accepted by the Smart App Control signature check.
2. **Microsoft Defender SmartScreen App Reputation.** SmartScreen considers both publisher/certificate reputation and file-hash reputation. A valid OV/EV or Microsoft Artifact Signing signature does **not** guarantee that a newly released file will avoid an “unrecognized app” prompt on first downloads. Microsoft states that EV no longer gets an automatic SmartScreen reputation bypass.
3. **Smart App Control / enterprise application control.** Smart App Control can allow correctly signed apps from trusted providers even when cloud reputation is not yet established, but this is a different enforcement system from SmartScreen reputation. Managed enterprise App Control/WDAC policy is a separate distribution/trust lane again.

Primary Microsoft references checked on 2026-09-14:

- SmartScreen reputation for Windows app developers: https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation
- Smart App Control signing: https://learn.microsoft.com/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control
- Code-signing options for Windows app developers: https://learn.microsoft.com/windows/apps/package-and-deploy/code-signing-options
- Microsoft Trusted Root Program participant list: https://learn.microsoft.com/security/trusted-root/participants-list

## 3. Trust matrix

| Distribution lane | What must be true | What it proves | What it does **not** prove | Recommended role |
|---|---|---|---|---|
| Public direct download, unsigned | Exact bytes may still be governed/reproducible | Artifact identity only | Publisher identity, Smart App Control signing trust, SmartScreen reputation | Not acceptable as the long-term `0.2.6+` public trust target |
| Public direct download, RSA Authenticode from Microsoft-trusted provider | Valid signature over installer and relevant executable payloads; trusted chain; timestamping policy | Native Windows publisher identity and signing integrity; compatible basis for Smart App Control | Guaranteed first-download SmartScreen reputation | Primary technical candidate for direct-download `0.2.6+` |
| Microsoft Artifact Signing public trust | Eligible organization + service availability + signing integration | Microsoft-managed trusted signing identity | Guaranteed elimination of SmartScreen warnings; availability for an ООО «Арвектум» Russian legal entity | Candidate only if legal/geographic eligibility is independently confirmed at decision time |
| Microsoft Store distribution | Store packaging/submission accepted; Store re-signing/distribution | Microsoft-managed distribution trust/reputation path | Suitability for all current desktop packaging, Russian-market distribution strategy, or offline channels | Optional parallel channel, not assumed primary |
| Managed enterprise distribution | Customer/admin deploys trusted App Control/WDAC policy and/or enterprise trust | Controlled organization-specific allow policy | Public consumer trust or SmartScreen reputation | Strong B2B/enterprise lane |
| CryptoPro/Rutoken detached signing | Existing Russian evidence process remains intact | Russian release-evidence/provenance layer | Authenticode, Smart App Control publisher trust, SmartScreen reputation | Mandatory separate evidence layer, not a substitute for native Windows signing |

## 4. Russian-native CA / Минцифры / ФНС boundary

No repository evidence currently establishes that a Russian GOST УКЭП, Минцифры/ФНС certificate, or CryptoPro certificate chain is accepted by stock Windows as a Microsoft-native Authenticode/Smart App Control public publisher chain.

The correct acceptance test is not “CryptoPro can create a signature” but:

- the exact RSA code-signing certificate chain is trusted by supported stock Windows through the Microsoft Trusted Root Program/current Windows trust distribution;
- `WinVerifyTrust`/SignTool validation succeeds without installing an Arvectum-specific private root;
- Smart App Control recognizes the signing path under its current requirements;
- the intended legal entity can actually obtain and lawfully use that certificate for software publisher signing.

Until a concrete Russian provider and exact certificate hierarchy satisfy those checks, the Russian-native public Authenticode path remains `UNPROVEN`, not rejected and not approved.

The Microsoft Trusted Root Program participant source should be re-checked at the time of purchase because participants and permitted usage change over time. Absence of a familiar Russian CA name from a cached list must not be elevated into a permanent legal/technical impossibility claim.

## 5. Artifact Signing eligibility caveat

Microsoft’s 2026 documentation has changed materially during the year and public eligibility has expanded unevenly by geography. Therefore this packet does **not** assert that an ООО «Арвектум» Russian legal entity is eligible for Artifact Signing Public Trust.

Before selecting Artifact Signing, the decision owner must verify current organization-country eligibility in Microsoft’s current quickstart/portal and identity-validation rules. Service availability in an Azure region does not itself prove identity-validation eligibility for a Russian company.

## 6. Candidate production architecture for review

This is a technical recommendation, not an approved production decision.

For a future direct-download `0.2.6+` release, the lowest-surprise Windows-native architecture is:

1. keep the existing Russian detached CryptoPro/Rutoken release-evidence chain;
2. add a separate **RSA Authenticode** signing stage using a certificate/service that chains to a Microsoft-trusted public provider and is legally obtainable by the Company;
3. sign relevant application executables before installer packaging where feasible, then sign the final installer after packaging;
4. apply an RFC3161-compatible trusted timestamp so signatures remain verifiable after certificate expiry, subject to provider/tool requirements;
5. verify signatures with Windows-native tooling (`signtool verify` / WinVerifyTrust semantics) on the exact candidate;
6. perform clean-machine acceptance with Mark-of-the-Web present, without disabling Defender, SmartScreen, Smart App Control, CFA, or other security controls;
7. record SmartScreen behavior separately from Authenticode validity, because a valid new signature can still show an “unrecognized app” reputation warning;
8. preserve exact release hashes and both native-Windows and Russian detached-signature evidence.

## 7. OV vs EV

Do not purchase EV solely for the historical expectation of immediate SmartScreen reputation. Microsoft’s current guidance states that EV no longer bypasses SmartScreen reputation and that OV/EV signed files can still show warnings until reputation builds.

EV may still have independent value for identity assurance, enterprise procurement, or a provider-specific operational model. That value must be justified separately; it is not a technical SmartScreen bypass criterion.

## 8. Acceptance matrix for `0.2.6+`

Before production release, the chosen path should prove at minimum:

| Gate | Required evidence |
|---|---|
| Native signature | `Get-AuthenticodeSignature` / SignTool reports valid signature and expected publisher on installer and declared payloads |
| Trusted chain | Clean supported Windows validates the chain without installing a private Arvectum root |
| RSA / SAC compatibility | Signing algorithm and chain satisfy current Smart App Control requirements |
| Timestamp | Signature verifies after normal certificate validity semantics; timestamp source and policy recorded |
| Packaging order | Payload signing occurs before packaging where required; final installer is signed after final packaging |
| MOTW launch | Fresh internet download retaining `ZoneId=3` tested on a clean Windows machine |
| SmartScreen | Actual warning/no-warning result recorded as observed reputation evidence, not inferred from certificate type |
| Smart App Control | SAC-enabled clean-machine test where practical; no security-control disablement accepted as PASS |
| Enterprise lane | If marketed for managed organizations, WDAC/App Control deployment behavior documented separately |
| Russian evidence | CryptoPro/Rutoken detached release-evidence signature generated and verified independently |
| Immutability | `v0.2.5` tag/assets remain untouched; all changes are in a new release line |
| Recovery/renewal | Certificate/key/service outage, renewal, revocation and signer-identity continuity procedure documented |

## 9. Key custody and CI boundary

A production signer introduces a high-value credential/service boundary. The implementation must not put exportable production private keys into the public repository, ordinary CI variables, generated artifacts, logs, prompts, or developer worktrees.

The final architecture must explicitly choose one supported custody model, for example provider-managed signing, hardware-backed key custody, or another approved non-exportable signing path. Any paid service, certificate purchase, cloud subscription, hardware token, HSM, contractual commitment, or new external dependency remains an Owner decision and is outside this REVIEW task.

## 10. Decision options

### Option A — Microsoft-trusted third-party OV/RSA Authenticode + Russian detached evidence

Pros:
- conventional direct-download Windows path;
- independent of Store packaging;
- native publisher identity on installer/app;
- can coexist cleanly with Russian detached evidence.

Cons/unknowns:
- exact provider eligibility for a Russian company must be confirmed;
- cost and identity-validation/legal constraints require Owner review;
- SmartScreen reputation still accumulates and is not guaranteed on first release.

### Option B — Microsoft Artifact Signing + Russian detached evidence

Pros:
- Microsoft-managed signing service and CI-friendly operating model;
- Microsoft currently presents it as the preferred signing approach where available.

Cons/unknowns:
- Russian legal-entity eligibility is not established by this packet;
- external Azure/service dependency and paid commitment require Owner approval;
- SmartScreen first-download reputation is still not guaranteed.

### Option C — Microsoft Store as primary public Windows channel + separate direct-download policy

Pros:
- Store re-signing/distribution has the strongest Microsoft-managed reputation path;
- reduces direct-download warning friction for Store users.

Cons/unknowns:
- packaging/product/distribution constraints may not fit current architecture or Russian-market goals;
- does not eliminate the need to decide how direct/offline/enterprise distributions are trusted.

### Option D — Enterprise-managed trust only

Pros:
- strong controlled B2B lane using customer-managed App Control/WDAC policy.

Cons:
- does not solve public consumer direct-download trust.

## 11. Review recommendation

Recommended **decision direction** for Owner/Product Owner consideration:

- preserve a two-layer model: **Windows-native Authenticode public trust + Russian detached release evidence**;
- prefer an RSA Microsoft-trusted signing path for `0.2.6+` direct downloads;
- treat Artifact Signing as preferred operationally only if current legal-entity eligibility is verified;
- otherwise compare qualified Microsoft-trusted OV/RSA providers that can lawfully issue to ООО «Арвектум»;
- keep Microsoft Store and enterprise WDAC/App Control as separate optional distribution lanes rather than conflating them with direct-download Authenticode;
- do not buy EV merely for SmartScreen reputation;
- do not mutate `v0.2.5`.

No provider, purchase, certificate, release, signing key, Azure resource, Store submission, or production signing action is approved by this document.

## 12. Owner/Product Owner decision gate

To advance from REVIEW to implementation, record an explicit decision covering:

1. chosen distribution lane(s): direct public / Store / managed enterprise;
2. chosen native Windows signing mechanism/provider class;
3. confirmation that the issuing/service path is available to and legally usable by ООО «Арвектум»;
4. approved budget/external dependency if any;
5. key-custody/signing-service authority and operator boundary;
6. `0.2.6+` release acceptance matrix;
7. retention of the Russian detached evidence layer.

Until then, `APL-REL-016` remains `REVIEW` and must not progress into production signing or release publication.
