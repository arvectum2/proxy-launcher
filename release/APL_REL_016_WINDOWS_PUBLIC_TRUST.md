# APL-REL-016 — Windows public trust for direct distribution

**Status:** IMPLEMENTED AT REPOSITORY/CONTRACT LEVEL / PUBLIC CERTIFICATE + PHYSICAL MOTW ACCEPTANCE PENDING  
**Decision date:** 2026-09-13  
**First eligible release:** `0.2.6+`  
**Immutable predecessor:** `v0.2.5`  
**Owner:** ООО «Арвектум»

## 1. Goal

APL-REL-016 closes the gap between a cryptographically governed Arvectum release and a Windows executable that a normal public user can identify as coming from a native Windows publisher.

The `v0.2.5` release proved the Russia-first release-evidence chain but its Setup is not PE/Authenticode-signed. A browser download therefore arrives with Mark-of-the-Web and Windows can present an unknown/unsigned publisher warning even though the exact file hash is governed and Defender has no malware detection.

APL-REL-016 does **not** rewrite `v0.2.5`. The tag and published assets remain immutable. Every byte-changing embedded-signature operation belongs to a new release, beginning no earlier than `0.2.6`.

Canonical machine-readable contract:

```text
release/APL_REL_016_WINDOWS_PUBLIC_TRUST_CONTRACT.json
```

## 2. Three trust layers that must not be conflated

### 2.1 Public consumer Windows trust

For direct Win32 distribution, the executable publisher identity must be verifiable by Windows without requiring the customer to install an Arvectum-specific root certificate or enterprise policy.

The production baseline is:

- Authenticode Code Signing EKU `1.3.6.1.5.5.7.3.3`;
- RSA key, minimum 2048 bits;
- SHA-256 file digest;
- RFC 3161 timestamp with SHA-256;
- certificate chain accepted by Windows through a CA participating in the Microsoft Trusted Root Program for the applicable code-signing use;
- stable publisher identity for ООО «Арвектум»;
- no PFX/P12 or private-key password committed to the repository or stored as a normal cloud-CI secret.

A self-signed certificate is useful for CI only. It is not public trust.

### 2.2 Managed enterprise trust

A managed Russian customer may use App Control for Business/WDAC, catalog signing, an internal CA, or another organization-managed allow policy. That can be a valid enterprise deployment model.

It is **not** equivalent to public consumer trust. A policy deployed by an administrator to a managed fleet does not make the same binary a generally trusted public download on an unrelated Windows machine.

### 2.3 Russian qualified release evidence

The existing REL-011/REL-012/REL-013 CryptoPro/Rutoken chain remains mandatory for the Russia-first release line:

```text
final release bytes
  -> SHA256SUMS.txt
  -> detached CryptoPro/Rutoken signature
  -> signer certificate/evidence
  -> REL-012 verification
  -> final production release gate
```

The current governed ФНС certificate remains `RELEASE-EVIDENCE-ONLY`. It has already been proven for detached evidence and must **not** be relabeled as Authenticode, SmartScreen reputation, Microsoft trusted-publisher identity, or Smart App Control public trust.

## 3. SmartScreen, Smart App Control and App Control are different decisions

APL-REL-016 treats the following separately:

- **Microsoft Defender SmartScreen App Reputation** evaluates application/publisher reputation and download context. A valid new signature establishes a publisher identity but does not guarantee that a brand-new binary will immediately have enough reputation to avoid an "unrecognized app" warning.
- **Smart App Control** is an execution-control feature distinct from SmartScreen. When cloud intelligence cannot classify a binary, a valid signature from an accepted public trust chain can be decisive. The current Microsoft guidance requires RSA-based signing for this path.
- **App Control for Business / WDAC** is a managed policy system and belongs to the enterprise layer.

Therefore APL-REL-016 never encodes the false rule `valid Authenticode signature == guaranteed no SmartScreen warning`.

## 4. Russia-first provider decision

The provider policy is vendor-neutral.

The procurement order is:

1. investigate a Russian-native issuer/service first **only if** it can issue a real Authenticode Code Signing certificate for ООО «Арвектум» that chains to Windows public trust through the Microsoft Trusted Root Program and satisfies the RSA/code-signing profile;
2. reject any proposal that merely provides a ГОСТ УКЭП, TLS certificate, enterprise-installed root, or detached CMS signature and calls that public Authenticode trust;
3. if no Russian-native path satisfies native Windows public trust, use an eligible external code-signing provider as a narrowly scoped compatibility dependency for the Windows public-distribution layer while retaining Russian qualified release evidence independently;
4. do not bind the architecture to GlobalSign, DigiCert or any other specific vendor in source code or release policy.

Microsoft Artifact Signing/Trusted Signing may be evaluated when the legal entity is eligible for the service geography. It is not assumed available to a Russian legal entity. Microsoft Store distribution remains a separate future channel and is not required by this task.

The current project decision is therefore **not** "buy an international certificate now". The repository is prepared so that an approved provider can be inserted without changing the release trust model.

## 5. Exact byte order for a direct public Win32 release

Embedded signing changes PE bytes. The release pipeline must use this exact order:

```text
1. canonical clean build
2. sign Arvectum Proxy Launcher.exe with production Authenticode identity
3. verify application Authenticode signature and expected publisher
4. build the portable ZIP around that exact signed application
5. verify the ZIP contains those exact signed application bytes
6. build Setup from that exact signed application
7. sign Setup.exe with the same approved production publisher identity
8. verify Setup Authenticode signature and expected publisher
9. only now calculate final release hashes
10. add REL-012 consumer verification UX before detached signing
11. run REL-011 CryptoPro/Rutoken detached signing over the final set
12. run REL-012 and REL-013/current exact-release gate
13. publish only the exact verified set
```

Do **not** sign an executable after it has been put in a ZIP without rebuilding the ZIP. Do **not** sign the installer after calculating the release checksum and keep the old checksum. Do **not** run Russian detached signing before the final Authenticode byte changes.

Canonical helpers:

```text
tools/windows_authenticode.ps1
tools/package_signed_windows_portable.ps1
tools/build_windows_installer.ps1
tools/windows_public_trust_gate.ps1
```

## 6. Production signing identity contract

`tools/windows_authenticode.ps1` is the canonical PE signing primitive. For production it requires:

- certificate available through a Windows certificate store/private-key provider;
- Code Signing EKU;
- RSA key of at least 2048 bits;
- SHA-256 Authenticode digest;
- RFC 3161 SHA-256 timestamp;
- expected publisher verification after signing;
- SignTool `/pa` verification.

The script deliberately does not accept a PFX path or password.

Recommended production environment variables are non-secret identity/configuration only:

```text
WINDOWS_SIGNING_CERT_THUMBPRINT
WINDOWS_SIGNING_EXPECTED_PUBLISHER
WINDOWS_SIGNING_TIMESTAMP_URL
```

The private key should remain hardware-backed, HSM-backed or otherwise non-exportable under the selected provider model. If interactive owner operation is required, public release signing remains an owner-operated ceremony instead of weakening key custody to make cloud CI convenient.

## 7. Packaging the signed application

`tools/package_signed_windows_portable.ps1` exists because the old clean-build portable is assembled before production signing.

The helper:

- accepts the canonical signed application and the original build-result manifest;
- verifies that the application has a valid Authenticode signature, expected publisher and expected signer thumbprint;
- verifies RSA + Code Signing EKU;
- rebuilds the canonical portable around the **signed** executable;
- regenerates the portable internal `SHA256SUMS.txt` from the signed bytes;
- preserves the normal README/diagnostic payload;
- invokes the promoted Windows third-party-license compliance packager;
- updates `build-result.json` to the signed executable/portable hashes;
- reopens the final archive and verifies that the contained application is byte-identical to the approved signed application and still has a valid signature.

The resulting signed portable/build-result pair can then be supplied to:

```powershell
.\tools\build_windows_installer.ps1 `
  -UseExistingPayload `
  -ApplicationExe <signed-app> `
  -PortableZip <signed-portable.zip> `
  -BuildResultPath <signed-build-result.json> `
  -ExpectedApplicationSha256 <signed-app-sha256>
```

This preserves the existing invariant that Setup embeds the exact same application bytes distributed in the portable package.

## 8. Physical public-trust gate

Repository/CI proof cannot establish SmartScreen reputation. A real public release candidate must be tested as a real Internet download.

Canonical collector/gate:

```text
tools/windows_public_trust_gate.ps1
```

Required public-acceptance conditions:

1. test on a clean/reset or otherwise trustworthy supported Windows host, not a machine with a manually installed Arvectum test root;
2. download the candidate through the normal browser/public release channel;
3. preserve Mark-of-the-Web and require `ZoneId=3` on the downloaded Setup;
4. require `Get-AuthenticodeSignature` = `Valid` for both application and Setup;
5. require the expected publisher and approved signer thumbprint;
6. require Code Signing EKU, RSA >= 2048 and a successful Windows chain build;
7. preserve explicit evidence for the CA/root's Microsoft Trusted Root Program status rather than inferring program membership solely from an arbitrary local root store;
8. keep Defender enabled and require no product-specific threat detection;
9. record the actual SmartScreen outcome;
10. when Smart App Control is enforced on the acceptance host, record whether the exact candidate was allowed;
11. preserve the generated JSON evidence alongside the release evidence.

### Public acceptance classifications

`BLOCKED_NO_WINDOWS_PUBLIC_SIGNATURE`
: Application or Setup is unsigned/invalid, the signer profile is wrong, publisher identity is wrong, or public-chain evidence is absent.

`BLOCKED_USER_FACING_TRUST`
: The signed candidate still presents an unknown-publisher/block outcome, Defender flags the candidate, or enforced Smart App Control blocks it.

`PUBLIC_SIGNATURE_READY_PHYSICAL_ACCEPTANCE_PENDING`
: Native signatures are valid, but the real MOTW/SmartScreen physical test is incomplete.

`PUBLIC_SIGNATURE_READY_REPUTATION_PENDING`
: Native publisher signature is valid and Windows identifies the publisher, but SmartScreen still reports a reputation-based "unrecognized app" warning. This is **not** an unsigned-publisher failure and must be tracked separately.

`PUBLIC_TRUST_ESTABLISHED_ON_TEST_HOST`
: Exact public candidate passes the required MOTW host gate and SmartScreen reports no warning; enforced Smart App Control, when present, allows the candidate.

The release manager may additionally require `-RequireNoSmartScreenWarning`. That is intentionally stricter than mere Authenticode readiness.

## 9. SmartScreen reputation policy

A valid OV/EV-style Authenticode identity does not create instant reputation for every new binary. EV no longer receives a special automatic SmartScreen bypass in current Microsoft behavior.

Consequences:

- do not rotate publisher identity unnecessarily;
- sign consistently with the same approved publisher identity while the certificate is valid;
- do not make gratuitous byte changes to an already accepted release candidate;
- preserve normal download volume/reputation organically;
- never attempt to bypass reputation using test signing, disabling SmartScreen, alternate-zone stripping, or customer instructions to disable Windows protections;
- submit false-positive/reputation cases through the appropriate Microsoft channel when necessary.

## 10. Timestamp and renewal policy

Production Authenticode signing requires RFC 3161 timestamping with SHA-256. The timestamp must be applied at signing time and verified as part of the signature.

Certificate renewal/replacement is a governed identity event:

1. obtain the replacement before the old certificate expires where operationally possible;
2. validate Code Signing EKU, RSA profile, Windows chain and provider eligibility;
3. verify expected publisher subject/identity continuity;
4. update the governed production thumbprint outside source-secret storage;
5. execute an REL-016 signing/physical acceptance candidate before first production use;
6. retain historical evidence for old releases; never re-sign immutable published releases merely because the certificate changed.

A timestamp is not permission to continue signing with an expired certificate. It preserves validation semantics for bytes that were legitimately signed during certificate validity.

## 11. Enterprise Russian-market option

For customers managing their own Windows fleet, Arvectum may provide a documented App Control/WDAC integration path. That path can use customer-approved publisher/file/catalog rules and, where appropriate, an internal enterprise CA.

It must be marketed explicitly as **managed enterprise deployment**. It is useful for Russian organizations even when consumer SmartScreen public trust is unavailable, but it cannot be presented as proof that arbitrary unmanaged Windows machines will trust the binary.

## 12. Forbidden shortcuts

APL-REL-016 fails policy if a release requires or recommends any of the following as a normal customer path:

- mutate `v0.2.5` or replace its assets;
- disable Defender, SmartScreen, Smart App Control or Controlled Folder Access;
- enable Windows test-signing/developer mode;
- ask consumers to install a self-signed Arvectum root merely to make a public download appear trusted;
- treat the existing ФНС УКЭП as native Authenticode without a separately proven Code Signing EKU/public Windows chain;
- publish hashes produced before final embedded signing;
- store PFX/P12, private keys or PIN/password material in Git or ordinary cloud-CI secrets;
- claim "SmartScreen trusted" merely because `Get-AuthenticodeSignature` is `Valid`.

## 13. CI boundary

Workflow:

```text
.github/workflows/windows-public-trust.yml
```

Hosted CI can prove:

- REL-016 contract/runbook consistency;
- PowerShell syntax;
- RSA/EKU/timestamp fail-closed signing logic;
- signed-portable packaging contract;
- real-PE Authenticode mechanics using ephemeral CI identity through the existing Authenticode smoke workflow.

Hosted CI cannot prove:

- a production certificate has actually been issued to ООО «Арвектум»;
- a CA is contractually/legally able to issue to the company at ceremony time;
- current SmartScreen reputation;
- real Mark-of-the-Web launch UX on the customer's Windows configuration;
- a production hardware/private-key ceremony that has not occurred.

Those remain explicit external/physical gates rather than fabricated CI PASS results.

## 14. Completion state

Repository implementation is complete when the REL-016 contract, runbook, RSA-hardened Authenticode primitive, signed-portable packager, public-trust physical gate, tests and CI are merged.

The production public-trust lane becomes **release-ready** only after an approved production certificate/provider exists and a `0.2.6+` candidate produces:

```text
Application Authenticode: VALID
Setup Authenticode: VALID
Expected publisher: PASS
Expected signer thumbprint: PASS
MOTW ZoneId=3: PASS
Defender: ENABLED / NO PRODUCT DETECTION
Microsoft public-chain evidence: PRESENT
SmartScreen outcome: RECORDED
Smart App Control outcome: RECORDED WHEN ENFORCED
REL-016 classification: PUBLIC_SIGNATURE_READY_REPUTATION_PENDING
or
REL-016 classification: PUBLIC_TRUST_ESTABLISHED_ON_TEST_HOST
```

For a release policy that promises **no SmartScreen warning**, only `PUBLIC_TRUST_ESTABLISHED_ON_TEST_HOST` satisfies that stronger promise.

Russian REL-011/012/013 evidence remains independently mandatory after the final Authenticode bytes are fixed.
