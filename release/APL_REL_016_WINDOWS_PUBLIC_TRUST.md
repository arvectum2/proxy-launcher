# APL-REL-016 — Windows public trust for direct distribution

**Status:** REPOSITORY/ENGINEERING IMPLEMENTED; PRODUCTION CERTIFICATE + PHYSICAL MOTW ACCEPTANCE PENDING  
**Decision date / current-requirements review:** 2026-09-22
**First eligible release:** `0.2.13+`
**Immutable predecessor:** `v0.2.5`  
**Owner:** ООО «Арвектум»

## 1. Goal

APL-REL-016 closes the gap between governed Arvectum release evidence and a Windows executable that an ordinary unmanaged Windows machine can identify as coming from a trusted software publisher.

`v0.2.5`, `v0.2.9`, and the now-published `v0.2.12` remain immutable. Their governed release evidence is valid, but production Windows public Authenticode signing is not active on those published releases. Every embedded-signature byte change under APL-REL-016 therefore belongs to `0.2.13+`.

Canonical machine contract:

```text
release/APL_REL_016_WINDOWS_PUBLIC_TRUST_CONTRACT.json
```

## 2. Trust matrix

### 2.1 Public consumer Windows trust

Required for a direct public Win32 download that does not ask the user or administrator to install an Arvectum/Russian root manually.

Production profile:

- Authenticode Code Signing EKU `1.3.6.1.5.5.7.3.3`;
- RSA subscriber key **>= 3072 bits**;
- SHA-256 file digest;
- RFC 3161 timestamp with SHA-256;
- chain accepted by Windows through a CA participating in the Microsoft Trusted Root Program for code signing;
- public certificate/provider must meet the CA/Browser Forum Code Signing Baseline Requirements;
- for certificates procured under the current profile, the subscriber certificate must contain exactly one reserved CAB Forum code-signing policy OID: `2.23.140.1.4.1` (Non-EV) or `2.23.140.1.3` (EV); this requirement is effective from 2026-09-15;
- certificates issued on or after 2026-03-01 must have a validity period no longer than 460 days;
- stable verified publisher identity for ООО «Арвектум»;
- subscriber private-key custody must remain hardware/signing-service protected under the current CA/B Forum requirements;
- no PFX/P12/private-key material in Git or ordinary cloud-CI secrets.

The RSA-3072 floor is deliberate: current public Code Signing Baseline Requirements require at least RSA-3072 for subscriber code-signing certificates. Smart App Control additionally requires an RSA-compatible signing path; ECC is not the production baseline here. The REL-016 public gate also checks the post-2026-09-15 certificate-policy profile and the 460-day validity ceiling rather than assuming that a syntactically valid Authenticode signature is current-policy compliant.

### 2.2 Managed enterprise Windows trust

Russian enterprise customers may deploy App Control for Business / WDAC, catalog rules, publisher rules, internal CA trust, or another organization-managed policy.

That is a valid managed-fleet deployment model, but **not** equivalent to public consumer trust on an unrelated Windows machine.

### 2.3 Russian qualified release evidence

The existing Russia-first layer remains mandatory and independent:

```text
final release bytes
  -> SHA256SUMS.txt
  -> detached CryptoPro/Rutoken signature
  -> signer certificate/evidence
  -> REL-012 verification UX
  -> final release gate
```

The current ФНС certificate remains `RELEASE-EVIDENCE-ONLY`. It must not be relabeled as Authenticode, SmartScreen reputation, Microsoft trusted-publisher identity, or Smart App Control public trust.

## 3. SmartScreen, Smart App Control and App Control are different

- **Microsoft Defender SmartScreen App Reputation** uses application/publisher reputation and download context. A valid Authenticode signature establishes identity, but a new signed binary may still show an "unrecognized app" reputation warning.
- **Smart App Control** is a separate execution-control feature. For unknown code, an accepted public signature can be decisive; the current Microsoft path requires RSA-based signing.
- **App Control for Business / WDAC** is a managed-policy system and belongs to the enterprise layer.

Therefore REL-016 never assumes:

```text
valid Authenticode signature == guaranteed no SmartScreen warning
```

A reputation warning with a verified publisher is tracked separately from an unsigned/unknown-publisher failure.

## 4. Russia-first provider decision

The architecture is vendor-neutral. GlobalSign, DigiCert, Sectigo, Microsoft Artifact Signing, or any other foreign provider is **not** hard-coded as the preferred solution.

Procurement order:

1. re-check a Russian-native path first;
2. accept it for public Windows distribution only if it produces a real RSA Authenticode code-signing chain accepted on clean supported Windows without manual root installation and with authoritative Microsoft Trusted Root Program evidence;
3. reject any proposal that merely supplies a ГОСТ УКЭП, TLS certificate, manually installed enterprise/root trust, or detached CMS signature and calls it public Authenticode trust;
4. use an eligible foreign provider only as a narrowly scoped Windows compatibility dependency if no Russian-native path satisfies the native Windows requirement;
5. retain Russian CryptoPro/Rutoken release evidence regardless of which Authenticode provider is used.

### 4.1 Russian National Certification Authority watch-path

The MinDigital draft dated **2026-08-28**, re-checked on **2026-09-22**, is important: it defines a separate **RSA code-signing certificate using international cryptographic algorithms**, requires `codeSigning` EKU, and references the CAB Forum code-signing policy OID `2.23.140.1.4.1`.

This is now the **first Russian-native candidate to re-check** before any international certificate purchase.

Current classification:

```text
DRAFT_REGULATORY_CANDIDATE_NOT_PRODUCTION_PROVEN
```

It must not be promoted to public Windows trust until all of the following are true:

- final regulation and production issuance service exist;
- ООО «Арвектум» is eligible and can actually obtain the certificate;
- issued subscriber key/profile meets RSA-3072 + code-signing requirements;
- clean supported Windows builds the chain without manually installing Russian Trusted Root;
- relevant root/intermediate participation in the Microsoft Trusted Root Program is authoritatively verified;
- RFC 3161 timestamping is available and passes the REL-016 gate;
- real MOTW / SmartScreen / Smart App Control acceptance is recorded.

The fact that the current Russian Trusted Root can be manually installed into Windows does **not** satisfy public consumer trust.

Microsoft Artifact Signing Public Trust is **not currently available to a Russian organization under Microsoft’s published geography list**. As checked on 2026-09-22, Microsoft lists organizations in the United States, Canada, the European Union, the United Kingdom, Australia, New Zealand, Japan, South Korea, Singapore, Switzerland, Norway and Israel; Russia is not listed. Re-evaluate only if Microsoft changes eligibility or the Owner explicitly approves a separately eligible legal-entity path after legal review. Microsoft Store/MSIX remains a separate future distribution channel.

## 5. Exact byte order

Embedded Authenticode signing changes PE bytes. The release order is therefore fixed:

```text
1. canonical clean build
2. Authenticode-sign Arvectum Proxy Launcher.exe
3. verify application signature + publisher + signer profile
4. rebuild portable ZIP around that exact signed application
5. verify portable contains those exact signed application bytes
6. compile Setup from that exact signed application
7. Authenticode-sign final Setup.exe
8. verify Setup signature + publisher + signer profile
9. generate final release hashes
10. add/finalize REL-012 user verification material
11. CryptoPro/Rutoken-sign the final release manifest/set
12. run REL-012 + REL-013/current exact-release gates
13. publish only the exact verified set
```

Never calculate final hashes before the last embedded-signature byte change. Never sign the application after it has already been zipped without rebuilding the ZIP. Never run the Russian detached-signature ceremony over a set that will later be mutated by Authenticode.

Canonical helpers:

```text
tools/windows_authenticode.ps1
tools/package_signed_windows_portable.ps1
tools/build_windows_installer.ps1
tools/windows_public_trust_gate.ps1
```

## 6. Signing identity and key custody

`tools/windows_authenticode.ps1` is the canonical PE-signing primitive. Production mode requires:

- Code Signing EKU;
- RSA >= 3072;
- SHA-256 Authenticode digest;
- RFC 3161 SHA-256 timestamp;
- expected publisher verification;
- SignTool `/pa` verification.

Configuration variables are identifiers/configuration, not private keys:

```text
WINDOWS_SIGNING_CERT_THUMBPRINT
WINDOWS_SIGNING_EXPECTED_PUBLISHER
WINDOWS_SIGNING_TIMESTAMP_URL
```

Private key custody must remain hardware-backed, HSM-backed, provider-backed, or otherwise non-exportable. If the approved Russian/provider path requires an owner-operated signing ceremony, that is preferable to weakening key custody merely to make hosted CI convenient.

## 7. Signed portable and installer binding

`tools/package_signed_windows_portable.ps1` exists because the portable package must contain the already signed application.

It verifies:

- Authenticode status `Valid`;
- expected publisher and thumbprint;
- Code Signing EKU;
- RSA >= 3072;
- signed EXE hash differs from the pre-sign build hash;
- final ZIP contains byte-identical signed EXE;
- internal `SHA256SUMS.txt` covers the signed EXE;
- APL-IP-004 third-party license bundle remains valid;
- `build-result.json` matches the final portable bytes.

`tools/build_windows_installer.ps1 -UseExistingPayload` then consumes that exact signed EXE and portable. REL-016 also fixes a pre-existing PowerShell case-insensitive variable-shadowing bug that previously could overwrite the caller-supplied `-PortableZip` path with the default unsigned portable path. A regression test now locks that fix.

## 8. Physical public-trust gate

Repository CI cannot prove current SmartScreen reputation. A production candidate must be tested as a real public download.

Canonical evidence collector:

```text
tools/windows_public_trust_gate.ps1
```

For `-RequirePublicReady`, require:

1. clean/reset or otherwise trustworthy supported Windows host;
2. candidate downloaded through the normal browser/public release path;
3. Mark-of-the-Web preserved with `ZoneId=3`;
4. application Authenticode = `Valid`;
5. Setup Authenticode = `Valid`;
6. expected publisher + thumbprint;
7. Code Signing EKU + RSA >= 3072;
8. successful Windows chain build;
9. exactly one current CAB Forum reserved subscriber code-signing policy OID (`2.23.140.1.4.1` Non-EV or `2.23.140.1.3` EV);
10. subscriber certificate validity window compliant with the current 460-day ceiling where applicable;
11. an RFC 3161 timestamp is present;
12. retained authoritative Microsoft Trusted Root Program reference; local root-store presence alone is insufficient proof;
13. Defender enabled with no candidate-specific detection;
14. actual SmartScreen outcome recorded;
15. Smart App Control outcome recorded when enforced.

The gate emits JSON evidence rather than relying on screenshots alone.

## 9. Acceptance classifications

`BLOCKED_NO_WINDOWS_PUBLIC_SIGNATURE`  
Unsigned/invalid binary, wrong signer profile, wrong identity, or failed chain.

`BLOCKED_USER_FACING_TRUST`  
Unknown-publisher/block outcome, Defender detection, or enforced Smart App Control block.

`PUBLIC_SIGNATURE_READY_PHYSICAL_ACCEPTANCE_PENDING`  
Native signature profile is valid, but a real browser/MOTW test is incomplete.

`PUBLIC_SIGNATURE_READY_REPUTATION_PENDING`  
Publisher signature is valid and Windows identifies the publisher, but SmartScreen still shows a reputation-based "unrecognized app" warning.

`PUBLIC_TRUST_ESTABLISHED_ON_TEST_HOST`  
Exact candidate passes the MOTW host gate and SmartScreen shows no warning; enforced Smart App Control, when present, allows it.

A release policy promising **no SmartScreen warning** may only use `PUBLIC_TRUST_ESTABLISHED_ON_TEST_HOST`.

## 10. Timestamp and renewal

Every production Authenticode signature requires RFC 3161 timestamping with SHA-256.

Renewal/replacement is a governed identity event:

1. obtain replacement before expiry where operationally possible;
2. validate Code Signing EKU, RSA-3072+, Windows chain, public-trust eligibility, and provider status;
3. verify publisher-identity continuity;
4. update the governed signer thumbprint outside secret-bearing source storage;
5. execute REL-016 signing + physical acceptance before first production use;
6. preserve historical evidence and never re-sign immutable published releases merely because a certificate changed.

Timestamping preserves validation semantics for a file legitimately signed during certificate validity; it is not permission to continue signing with an expired certificate.

## 11. CI boundary

Workflow:

```text
.github/workflows/windows-public-trust.yml
```

Hosted CI can prove:

- contract/runbook consistency;
- PowerShell syntax;
- RSA/EKU fail-closed logic;
- build -> sign app -> package signed portable -> compile installer from same signed bytes -> sign/verify installer;
- packaging/hash invariants;
- no production PFX/private key in the repository.

Hosted CI uses an ephemeral self-signed RSA-3072 test identity only to exercise byte order and Authenticode mechanics. It is explicitly **not** public trust.

Hosted CI cannot prove:

- a production public certificate has been issued to ООО «Арвектум»;
- the Russian NUC draft path has become operational and Microsoft-publicly trusted;
- current SmartScreen reputation;
- real browser Mark-of-the-Web launch UX;
- production hardware/private-key ceremony.

Those remain external gates instead of fabricated PASS results.

## 12. Forbidden shortcuts

REL-016 fails policy if production requires or recommends:

- mutating `v0.2.5`, `v0.2.9`, or `v0.2.12` or replacing their assets;
- disabling Defender, SmartScreen, Smart App Control or Controlled Folder Access;
- Windows test-signing/developer mode;
- asking ordinary users to install a self-signed/Arvectum/Russian root merely to make a public download appear trusted;
- treating the current ФНС УКЭП as native Authenticode without a separately proven public code-signing chain;
- calculating final hashes before final embedded signing;
- storing PFX/P12/private keys/PINs/passwords in Git or ordinary cloud CI;
- claiming "SmartScreen trusted" merely because `Get-AuthenticodeSignature` is `Valid`;
- treating Artifact Signing Public Trust as currently available to ООО «Арвектум» while Russia remains outside Microsoft’s published organization geography.

## 13. Completion state

Repository implementation is complete when this contract, the RSA-3072 signing primitive, signed-portable packager, physical public-trust gate, regression tests and CI are merged.

Production public trust remains pending until a `0.2.13+` candidate has an eligible production identity and physical evidence equivalent to:

```text
Application Authenticode: VALID
Setup Authenticode: VALID
RSA: >=3072
Expected publisher: PASS
Expected signer thumbprint: PASS
MOTW ZoneId=3: PASS
Defender: ENABLED / NO PRODUCT DETECTION
Microsoft public-chain evidence: PRESENT
SmartScreen outcome: RECORDED
Smart App Control outcome: RECORDED WHEN ENFORCED
```

Russian qualified release evidence remains independently mandatory after final Authenticode bytes are fixed.
