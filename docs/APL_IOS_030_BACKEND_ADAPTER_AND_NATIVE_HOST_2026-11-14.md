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
