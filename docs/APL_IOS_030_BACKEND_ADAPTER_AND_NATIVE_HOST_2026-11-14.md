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
