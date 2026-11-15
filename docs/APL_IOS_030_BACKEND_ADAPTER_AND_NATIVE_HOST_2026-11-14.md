# Isolated backend command execution and physical lab host preparation

## Implemented

SharedCore TransportBackendAdapter serializes driver commands and receipts
on MainActor. It is an inactive lab adapter, not installed in the
production app/provider path. Same-process shared ownership lease is
retained across switching and failures; competitor refuses start until
the owner independently reconciles both provider slots as quiescent.
This does not provide an OS-global or cross-app process lock. Adapter
must remain alive until stopped/reconciled; abandoned failed owner
intentionally does not unlock automatically.

Start needs two independently reported readiness events (native and OS).
Stop needs both native drain and OS disconnect plus a fresh driver
snapshot of BOTH owned slots including pending starts. A queued
contradictory event during reconciliation prevents a replacement.
Epoch+generation and exact immutable plan bind receipts to session;
stale events ignored, conflicting current identity cancels. Submit is
nonblocking; synchronous receipts are queued in FIFO order, dispatch
failure precedes synchronous success. Startup/stop monotonic deadlines
cancel once, clear pending replacement and retain lease. Explicit stop
cancels pending switch. Recovery only after authoritative reconciliation,
new epoch, no silent retry/downgrade/DIRECT. Actual provider identity
and quiescence verification must be implemented by the real NE driver;
fake callbacks and receipt types are NOT physical proof. Disconnect
can restore ordinary OS routing, no continuous kill-switch claim.

13 Swift adapter integration tests pass with fake native/OS drivers,
including actual Task.sleep deadlines, contention, both readiness and
stop orders, false/contradictory receipts, synchronous callbacks,
throwing dispatch, uncertain recovery and reentrant inspection.
Initial additional test compile error fixed and rerun PASS.

## Separate physical VLESS lab host

Tools/NativeTunnelLab/Host/NativeLabHost.swift is an explicit synthetic
QA SwiftUI app, not the production app and not wired to the above
multi-provider adapter. Fixed host bundle:
ru.arvectum.proxylauncher.lab.nativeqa; embedded extension:
ru.arvectum.proxylauncher.lab.nativeqa.PacketTunnel. The existing
separate VLESS-only provider accepts the explicit opt-in synthetic
fixture only, a single TEST-NET /32 route and no default route/DNS.

Host requires explicit actions; no launch-time changes or on-demand
VPN. Only exact lab provider ID and owner marker accepted, refuses
conflicting or multiple profiles and other active managers it can see.
iOS manager enumeration is scoped to the application; it cannot
prove absence of every other application's VPN. Before a physical
run separately confirm installed APL and other VPN off. Input only
the temporary synthetic VLESS fixture for fixed LAN peer, never a
real credential. URI kept in RAM, passed in start options, not saved
in manager prefs. Exact 40-hex nonce probe to fixed synthetic HTTP
endpoint, ephemeral URLSession, no redirects. ATS allow-arbitrary-loads
only in this isolated QA host, not production. Independent server
receipt and actual routes must still be observed; the host's UI
response alone does not certify the data plane or no leak.
Explicit stop/remove only owned lab profile after disconnect.
If timeout/refusal, retain profile rather than remove uncertain state.

Updated build_unsigned.sh compiles and embeds genuine ARM64
iPhoneOS NE in separate application, verifies pinned Xray and current
Rust digest and extension symbols. Fresh build PASS 11:40 MSK.
No signing, install, Apple Developer registration, Keychain writes,
actual manager creation, runtime or real iPhone changes. Temporary
project/build removed. Separate provisioning for both exact IDs,
entitlements and signed installation require owner consent; actual
physical test must use isolated ephemeral LAN peer, never real
profiles. Full AWG provider/OS adapter, DNS/UDP/MTU/QUIC and hardware
switch acceptance remain open. No public release until legal/security
and production acceptance gates.

Final ordinary unsigned Release 0.3.0 build49 PASS, no new native
runtime symbols; Swift full281/281, focused Python35/35. Only
the pure adapter source added to normal project, no live dispatch.
The disposable generated lab project includes the minimal packet
tunnel entitlement templates for future approved signing; there
are no App Group or shared Keychain entitlements in the lab.

## Two-slot dispatch boundary — 22:38 MSK

OwnedTransportDispatcher routes exact immutable session commands to Xray or standalone AWG slots, requires both authoritative quiescence observations before start, rejects stale same-epoch start and foreign stop/cancel. Wrong-slot current-generation receipts signal failure; old receipts ignored. Ownership established before slot submission, so synchronous callbacks can be attributed. Four focused tests and full Swift 285/285 passed. Concrete native/NE slot implementations and signed integration remain pending; this is an inactive dispatch boundary with synthetic slot fixtures, not OS-level exclusive ownership or a kill switch. No device, provider registration or production linkage changed.

## Session-bound native control and NE integration boundary — 23:44 MSK

Both isolated native providers now optionally bind a versioned opaque epoch/generation/provider identity at startup, service bounded exact-request observe/drain messages and return native state. Explicit drain retains synthetic routes until OS teardown; only actual native stop completion can yield drained, unknown or contradictory receipt cannot unlock replacement. Existing physical QA launch option without identity remains compatible. `OwnedNativeControlSlot` uses separate native and OS observations; initial native quiescence proof is mandatory, stale request/identity or missing drain fails closed. `NETunnelNativeControlEndpoint` compiles against actual iOS NetworkExtension API and validates exact existing NativeLab ID and provider-specific ownership marker, no preference writes or automatic creation. It is not activated by the shipping VPNController. Two lab binary variants still share existing IDs and cannot coexist; injected fake endpoints prove dispatch semantics, not OS-level simultaneous manager switching. On stop during startup or unavailable receipt, cancel and poison without automatic recovery. Kernel-wide kill switch is not asserted.

Swift 290/290 incl5 new tests PASS; AWG legacy fixture contract now includes measured TCP/UDP IPv4/IPv6, still no general AWG or production acceptance. Python50 PASS; iPhoneOS endpoint typecheck, unsigned AWG device+sim builds, unsigned Xray device build/link with verified original pins PASS. Exact-head physical acceptance CI4/4 PASS. No iPhone, account, provisioning, main branch or production configuration changes. Next integrate actual control channel into the existing isolated host and exercise it on real OS; production packaging/configuration and broader interoperability remain.

## Existing NativeLab host integration — 23:48 MSK

Both mutually exclusive existing NativeLab variants now compile the same `NativeControlLabHost`, `OwnedNativeControlSlot` and real `NETunnelNativeControlEndpoint`. Explicit supervised opt-in with external no-live-extension and prepared-manager checks; no normal-launch behavior change. Native readiness plus OS connection, explicit matching rejected response to a fresh wrong-epoch observation (nil/timeout not accepted), actual drain then OS off required. Startup allows a one-second OS publication grace, not a manufactured receipt. Targeted VLESS TCP4 and AWG TCP4 control cases avoid repeating accepted full physical transport suites. Strict common receipt validator rejects any missing/nonboolean/contradictory field. Swift290, active iOS Python50 and receipt5 PASS. Both device builds and AWG simulator build PASS. Both offline signed using exact existing NativeLab development profiles and verified signatures, no portal or new IDs; artifacts `native-artifacts/native-control-xray-signed-20261114/NativeLabHost.app` and `native-artifacts/native-control-awg-signed-20261114/AWGCompileHost.app`. No iPhone changes, real device provider-message acceptance pending; same IDs preclude concurrent installed variants, no actual cross-provider production switch claim. Prior head CI pending at checkpoint.

## Physical native-control acceptance, Xray — 15 Nov 08:33 MSK

Matching prepare-only receipt accepted; signed existing NativeLab Xray build completed targeted VLESS TCP4 with independent exact witness1, HTTP200, TCP/SOCKS/target counters1, RSS48480256 bytes. Strict native-ready, OS connected, stale rejection, native-drained and OS-off receipt gate PASS, exit0. Owned cleanup confirmed and lab removed; Netherlands 2 restored and all three owner hashes unchanged. AWG variant then installed, prepare-only with all extensions OFF; OS permission prompt pending. No production modification or new Apple IDs.

## Offline native configuration compiler — 15 Nov 08:52 MSK

Reused validated wg-quick grammar for secret-bearing ephemeral compiler intermediate with redacted diagnostic reflection. Standard WG produces one Xray loopback SOCKS inbound and sole WireGuard outbound, AWG1 produces fixed numeric legacy parameters and peer keys in native UAPI. Narrow initial accepted format: one peer, literal endpoint, IPv4 /32 + IPv6 /128, exact dual default AllowedIPs, explicit DNS list, MTU1280–1500, no custom listen port. No persistence, activation, OS routing, DNS handling, WAN or full AWG version acceptance. Compiler success cannot unlock production backend. Pinned native macOS Xray testXray and AWG IpcSet without Up accepted generated ephemeral fixtures, repeatable `Tools/validate_native_wg_config.sh` verifies pins and cleans temporary files. Swift296/296, iOS Python50/50, regenerated Xcode project and normal unsigned iPhoneOS Release build PASS with no experimental native engine symbols. Existing phone untouched; AWG native-control hardware permission gate remains.

## Physical native-control acceptance, AWG — 15 Nov 09:00 MSK

Exact prepare-only receipt accepted after direct owner confirmation, verified actual Wi-Fi IP, all extensions off. Existing signed AWG NativeLab targeted TCP4 positive case completed with strict native-control receipts (ready, OS connected, explicit stale rejection, drained, OS off), independent exact witness1 and outer packets5/5, foreign rejection count0. Runner exit0 and owned profile cleanup confirmed. Lab uninstalled, Netherlands 2 production extension restored, all three owner fingerprints unchanged; external egress not separately measured. Together with earlier Xray control case both isolated hardware control gates PASS. This does not establish simultaneous production provider switching or general WAN/route/DNS acceptance. No new App IDs or production changes.

## Offline native route/DNS plan — 15 Nov

A shared candidate route plan consumes the validated WG/AWG runtime compiler output. Full IPv4 and IPv6 routes, profile-provided literal DNS and MTU, canonical literal peer IP/port. Reject special/mapped IPs, overlapping endpoint/local/DNS roles, duplicate DNS aliases and unsupported exclusion/direct policies. The candidate generates no explicit excluded routes, including for the peer; a provider-owned underlay socket path must be verified separately. The real NetworkExtension settings factory is inactive; its object fields were checked on macOS for both engines and both endpoint families (4/4), plus iPhoneOS typecheck. This does not establish actual Apple routing semantics (including implicit system routes), DNS leak protection, direct accessibility or a kill switch. VLESS route/DNS parity remains separately gated. Swift302/302, Python50/50, normal unsigned iPhoneOS Release build and absent experimental engine symbols PASS. No phone or production changes.

## Offline native profile preparation — 15 Nov

NativeProfilePreparation binds the compiled WG/AWG configuration and route plan to an opaque profile UUID/revision, explicit selection and a one-use validation ticket. In-memory staging bounded to 32 entries; edits/deletion/selection and failed preparation invalidate prior tickets. Provider mismatch or consumer failure consumes the ticket; cross-instance replay rejected. Legacy ProfileStore exposes a read-only ID collision guard via the existing strict decoding path. No changes to persisted format, existing selection, backup or Keychain writes. No UI activation, cross-process transfer or production authorization. Swift310/310, Python50/50 and ordinary unsigned iPhoneOS Release build PASS; native engine symbols remain absent. Next independently verified provider-owned underlay and secure handoff.

## Native credential handoff and bound-socket groundwork

Immutable native WG/AWG revision records use an inactive, separate device-only Keychain adapter. The one-use metadata-only ticket references a retained revision, provider and epoch/generation; expires after 60 s; one successful exact deletion wins. Tests use synthetic credentials and injected fake store (including 16 competing consumers); signed app/extension access, authoritative current revision, catalog and cleanup are still separate gates. AWG fixed-peer connected UDP bind verifies kernel interface index via IP_BOUND_IF/IPV6_BOUND_IF; restricted to lo0 local fixture. Exact IPv4/v6 UDP witness, foreign source filtering, close and actual pinned AWG frame exchange passed, race detector three repetitions, device/simulator archives built. No actual Wi-Fi/LTE underlay or OS route proof, no activation. Swift317, Python50, ordinary unsigned Release PASS; installed phone untouched.

## Persistent catalog and recovery groundwork

Native current-selection catalog uses a separate device-only metadata item. Old tickets reject replaced revisions even while exact retired record cleanup is pending. App is the intended single writer; new revision publication is journaled before insertion, pending exact-reference cleanup recovers interruptions, retired cleanup retries idempotently. Tests use fake stores, not actual shared Keychain or active profile switching. Both process factories remain inactive. Actual provider authorization, cross-process access and full lifecycle coordination still required. Swift322/322, Python50/50, unsigned Release PASS, no experimental engine link.

AWG source-level iOS-arm64 CGO dependency closure inventory captured with pinned Go1.25.0 and upstream commit. Five components (AWG, x/crypto, x/net, x/sys, Go standard library/runtime); nine original LICENSE/PATENTS texts and hashes verified at native-artifacts/awg-ios-source-license-inventory-20261115. Reproducible offline runner Tools/AWGNativeLab/inventory_ios_licenses.sh. Not final linked-binary SBOM, distribution clearance or proof for Xray/Rust/gVisor. No phone, publication or production changes.

## Provider-side credential validation and simulator acceptance attempt

`NativeCredentialReceiver` validates the opaque ticket against an independently expected profile revision/session/provider and consumes at most once per startup attempt even on failure. Recompile and recheck current selection before handing bytes to validation closure. Added two regression tests; production inactive. `Tools/NativeCredentialLab/run_simulator.sh` builds two synthetic simulator apps with a QA-only service namespace/group and no real VPN/NE operations. Xcode build and simulator ad-hoc signature succeed. Sender launch fails with NSPOSIXErrorDomain 3 even after fully booted compatible iOS 27.0/iPhone 17 retry; 27.1 runtime incompatible. No shared Keychain receipt. All created disposable simulators removed; no owner device or secrets touched. Swift324/324, Python50/50, normal unsigned iPhoneOS Release PASS, experimental engine symbols absent.

## Rust dependency/source notices

`inventory_native_rust_licenses.py` reproduces pinned tun2proxy source commit e271de19683937f23d3f8f0eb4df0a61fc4a6e50, applies exact clean lab patch chain with lockfile and Rust1.98.1, resolves offline normal/build iOS target source graph. 151 crate/version entries, 261 original notices initially. `supplement_native_rust_licenses.py` retrieved four exact pinned upstream Git blobs for daemonize and etherparse, verified git blob identities and SHA256. Final 265 file hashes match. tproxy-config 7.0.9 and tun 0.8.14 have declared license expressions but no original standalone notice found in crate or exact upstream commit tree; remain open. Artifact directory native-artifacts/tun2proxy-ios-source-license-inventory-20261115. This is source-level inventory, not complete binary SBOM or legal clearance; Xray/Rust final packaging/publication remains gated. Pinned Xray asset and go.mod reverified (60 declared modules, not proven linked closure).

## VLESS revision parity and native encrypted backup

VLESS now participates in native immutable revision/catalog and session-bound validation handoff, using the strict share-link parser and deterministic reconstruction that matches the pinned converter. Initial profile endpoint is literal unicast IPv4, validation context TCP4 only (no WG full routes, UDP/DNS claims). Pinned converter equivalence and testXray with/without Vision 2/2 pass. Distinct native encrypted backup format uses existing PBKDF2-HMAC-SHA256/AES-GCM envelope, authenticates format, validates all three protocol kinds and mints fresh IDs for additive restore planning. No legacy format change; no actual restore writes, UI or activation. Swift334/334, Python50/50, unsigned Release PASS, native engine symbols absent. Prior head 1f0f8fb8a CI7/7.

## Journaled native backup restore

Additive restore mints fresh profile/revision IDs; preflight capacity, current and retired IDs, legacy IDs, record absence and injected VPN inactivity. A single-writer metadata journal names every new revision before insertion; none is current until one atomic publish. While batch journal is pending, selection authorization, exports and other mutations reject. Failure or interruption recovers exactly journaled revisions, retries after cleanup/publication failure, preserves prior selected/current records. Six synthetic tests cover partial insert, failed final commit, VPN becoming active, failed journal clear, malformed journal and pre-existing v1 snapshot. Swift340/340, Python50/50, unsigned Release PASS, experimental link symbols absent. Actual OS inactive/exclusive VPN-start/write lease, signed shared Keychain and UI not yet connected; no device or owner credentials used.

## Native restore review / app-process coordination

Secret-free import summary counts WG/AWG1/VLESS, captures catalog and legacy IDs, expires at 5 minutes elapsed uptime, consumes confirmation once; invalidated on failed preview/cancel, and rejects changed state. Shared MainActor start/restore gate serializes VPNController starts across instances in the same process and holds during suspension. Inactive `confirmNativeRestoreForValidation` loads visible APL managers read-only (no reconcile/save), rejects nil load result, on-demand and non-disconnected state; this is not a global OS lease or proof against external starts. Native UI not enabled, actual signed Keychain/OS acceptance still required. Swift345/345, Python50/50, unsigned Release PASS, experimental symbols absent. Previous exact head 2804f9473 CI7/7.

## 15 November — unredeemed handoff metadata cleanup

Explicit `cleanupExpired` accepts at most 64 unique canonical handoff UUID accounts, validates whole input list before mutation and checks exact envelope ID/version/binding/time. Retains unexpired, rollback-clock and malformed entries; counts expired deletions and concurrent disappearance. Revision records are never enumerated or deleted by cleanup. Inactive Keychain adapter now applies separate record (32768 B) / handoff (2048 B) caps, and offers attribute-only enumeration of the isolated handoff service/group; OS enumeration itself is not bounded, deletion work is bounded by caller batches. No automatic cleanup, scheduling or real Keychain operation added. Four in-memory tests cover expiry, active records, invalid lists, failure/retry, wrong stored account and concurrent expired redemption. Wall-clock expiration and actual signed cross-process behavior remain separate risks/gates. Swift355/355, Python413/413+1527, unsigned Release PASS, no native engine symbols.
