# Signed isolated physical VLESS lab: first attempt and operator gate

14.11.2026 owner explicitly approved dedicated dev IDs/provisioning,
temporary signed isolated app install, bounded work-iPhone tests,
and deletion of the lab app/profile. Not consent for production
profile modifications or distribution. Work iPhone 13 accessible
over cable, unlocked since boot, existing APL disconnected. Three
owner keychain profile read-only checks and existing profile/selected
profile/organization SHA parity verified before work.

Dedicated automatic development provisioning succeeded under company
team for ru.arvectum.proxylauncher.lab.nativeqa and its .PacketTunnel
extension, using explicit --approved-sign-lab mode of build script,
without device registration. Both embedded mobileprovision files
and actual code signing entitlements validated: exact IDs/team,
development get-task-allow, registered test device,
packet-tunnel-provider, no App Group/shared Keychain. The signed
host+NE builds and actual native binaries verified. Current reusable
signed copy path is recorded privately at /tmp/apl-signed-native-lab-path.
No production signing settings changed.

Standalone native macOS peer compiled fresh from pinned Xray.
Initial isolated signed lab installed and launched, then one-shot
synthetic fixture transferred via its own app container. Xray peer
and independent nonce HTTP witness loopback, bounded LAN TCP relay
only 192.168.1.80:39882 to the exact authenticated loopback peer,
server routes only synthetic 198.51.100.77:39883. Ephemeral keys
and fixture, no arbitrary forwarding or production profile data.

Physical first run: launch requested, input file consumed (device
Documents empty), but no result receipt within 45s. No observed
NativeLab.appex process on follow-up. iPhone Mirroring had been
paused; Resume showed "iPhone in Use — Lock your iPhone to connect".
System permission dialog / saveToPreferences stall is a plausible
cause, not proven, because no actual phone screen was available.
**No physical data plane PASS or even confirmed connected status.**
Runner exited2 and closed server/relay/witness, no local listeners
39882–39884 remaining.

Explicit one-shot cleanup-only run (original signed host, intentionally
invalid synthetic fixture) returned matching runID, cleaned=true,
connected=false. Then isolated host uninstalled, device app inventory
and process inventory confirm lab absent. Existing APL selected
profile, profile list and organization fingerprints match baseline
after; three existing authenticated profiles readable from keychain,
APL VPN OFF/read-only test2/2 PASS again. No owner profile mutation.

Improved host adds per-run nonsecret progress file with stages for
load/save/reload manager, start, connected, probe, cleanup.
One-shot input removed after validation, no automatic run without
explicit launch argument. Explicit cleanup-only mode to query/remove
owned lab manager even after a stalled attempt. LAN relay restricted
to local /24, at most twelve accepted connections and bounded time.
Signed fresh improved host+embedded NE build/sign verification PASS.
Only source and safe metadata committed, no credentials/binaries.
Focused 36 checks PASS; py_compile/bash/diff PASS.

Next: operator needs to lock work iPhone to allow Mac mini
iPhone Mirroring, or directly confirm the specific test-app VPN
permission when it appears. Verify screen and APL OFF before
reinstall; use signed current improved build; retry single bounded
case, read exact progress on timeout; no repeated blind starts.
After positive actual NE receipt proceed negative credentials
and controlled native exit/memory, then exact cleanup and owner
fingerprint recheck. No new account/profile approval needed for
these two dedicated test IDs, already granted, but no unrelated
signing or device changes. Actual multi-provider driver, AWG NE
and full hardware/product/legal acceptance are still outstanding.

## Operator resume, 11:51–11:54 MSK

Mirroring connected after owner locked iPhone. Settings visibly
VPN OFF, but the exact previous lab profile remained selected despite
the earlier app receipt and uninstall. Thus the former cleanup receipt
was insufficient to prove global Settings absence. Reinstalled only
the authorized lab. First retry: connected=true, receipt=false,
cleaned=true, independent witness0, runner exit1. This confirms actual
iOS Connected status for the isolated VLESS NE, not working data plane.
Need native transport diagnostics, not another simulator success.

Added aggregate-only Rust log category counts via exact lab provider
message, URLSession error/status code and explicit empty proxy
dictionary, LAN relay accepted connection/byte counters, reload exact
owned manager list after deletion. Corrected Swift callback API
compilation, fresh signed app/NE verified and installed. Second
diagnostic retry encountered the specific NativeLabHost VPN permission
prompt; clicked Allow under prior explicit consent. macOS then
displayed "Authenticate to access iPhone. Enter the Mac login for
'master' to continue." No authentication bypass; operator required.
Second retry returned connected=false, receipt=false, cleaned=true,
probeCode=-999, counters empty, relay0/0/0, witness0, exit1.
No data attempt occurred in that retry. The counter callback currently
has no independent deadline; before using it in another unattended run,
add bounded one-shot timeout to ensure cleanup even if provider fails
to respond.

Dedicated cleanup-only confirmed true, lab app uninstalled and app/
process absence verified. Existing owner profile/selected/org hashes
true, read-only Keychain3 and APL OFF tests2/2 passed; local listeners
closed. Global Settings absence/selection after this cleanup remains
unverified because Mirroring now requires Mac login. Do not claim
global profile removed. Operator should authenticate directly on
Mac or manually confirm the exact NativeLabHost permission on phone;
then inspect Settings and remove only any orphan exact lab profile,
restore prior APL selection while VPN OFF if appropriate, and retry
one bounded diagnostic case. No password requested or stored.
All 36 focused checks passed. No production activation.

## 12:07–12:09 MSK: authentication gate reproduced

Before reinstall, Mirroring showed Settings VPN disconnected, normal
APL selected, exact lab profile absent. This visually closes the
previous orphan-profile uncertainty for the preceding run. Added
a lock-protected single-resume gate with a 2-second diagnostic
provider-message deadline; signed host and embedded NE verified.
Focused 9 source/contract checks passed.

Installed the isolated build, launched the bounded physical runner.
The specific NativeLabHost VPN permission appeared; authorized Allow
click again led to the macOS login authentication dialog. No
authentication bypass. Runner returned connected=false, receipt=false,
cleaned=true, relay connections0 and bytes0/0, independent witness0.
Peer cleanup complete. Separate cleanup-only launch failed with
devicectl exit1, so do not claim independent cleanup-only success.
Uninstall succeeded; isolated app and process inventory absent,
owner profile/selection/organization hashes true. Final global
Settings appearance and repeated read-only Keychain/VPN status tests
not verified in this attempt. No data-plane acceptance.
Require direct operator authentication or direct physical iPhone
permission during next supervised attempt. Do not repeatedly install
and create new VPN permission prompts while operator unavailable.

## 12:25–12:32: direct operator and corrected test infrastructure

Direct unlocked owner-supervised run reached actual iOS Connected,
Rust aggregate tcp3/target3/socks1/connect1, HTTP timeout -1001,
LAN relay 10 accepted connections and 19702 bytes toward peer,
0 return bytes, independent witness0. App result cleaned=true,
separate cleanup confirmed and uninstall. Not physical data acceptance.

Reproduced failure **without phone**: independent native macOS
client via same pinned physical peer (loopback/LAN), no HTTP
receipt; OpenSSL local TLS target handshake itself timed out.
Adding ALPN and HTTP flags alone caused intermittent results.
Replaced the disposable local target with threaded TLS1.3
HTTP endpoint bound only to loopback, added actual TLS readiness
probe, and mandatory two authenticated fresh nonce receipts via
LAN relay before launching phone. Fresh local preflight2/2
and subsequent exact same-server preflight2/2 passed. This
corrects a proven test-infrastructure blocker, not yet proof of
physical data transfer. A dedicated compile flag
APL_PHYSICAL_PEER_PREFLIGHT permits the macOS native helper to
use client mode for only 127.0.0.1 or fixed test LAN host; default
Mac helper still server-only. Current helper binary
$(cat /tmp/apl-native-physical-peer-path)/preflight. Rebuild
using same pinned source files/headers/archive as hostpeer plus
-D APL_PHYSICAL_PEER_PREFLIGHT. Second device attempt after
preflight reached saveLabManagerBegin and no result in 45s;
peer closed, separate cleanup true, lab app uninstalled.

Separate signing-verified permission-only build then installed;
--approved --prepare-only passes only fixed nonsecret marker,
NO peer, secrets, startTunnel, or actual provider invocation.
Stage saveLabManagerBegin observed; no test listener and no lab
or APL native extension process. This is INTENTIONAL temporary
app retention while awaiting owner approval of the specific
VPN prompt; no automatic start after consent. Next turn inspect
stage/prepare receipt labPreparedOff, then ONLY after positive
confirmed prepare, use bounded physical runner with preflight
helper and fresh nonce. Start now refuses missing profile instead
of invoking save again. Verify exact connected+HTTP witness and
cleanup, owner profile parity and APL OFF/Keychain. If owner
declines, clean up prepared lab only. Do not blindly retry.
9 previous and new focused tests (10 total) pass.

## 12:32 MSK — physical VLESS original-flow positive acceptance PASS

Prepared permission-only receipt matched runID, prepared=true,
connected=false, stage labPreparedOff. No prior active native
extension. No reinstall after permission. Fresh exactly bounded
pinned native peer, local TLS readiness, two independent authenticated
LAN preflights (exact witness1 each), then actual signed installed
iPhone host+NE with fixed synthetic /32 route. Runner exit0, duration
4.744 seconds on host (including two preflights and cleanup).
Final relay3 accepted connections, cumulative 6721/7804 bytes each
direction (includes two preflights; final physical delta2383/2616).
On-device connected=true, receipt=true, probeCode=200,
native counter categories socks1/target1/tcp1, cleaned=true,
independent exact physical HTTP nonce witness1, total3 exact receipts.
Actual URLSession TCP request traversed OS NetworkExtension, original
utun descriptor, native Rust->Xray->LAN peer and independent HTTP
witness. No positive claim beyond this narrow synthetic VLESS
configuration, no general leakage, DNS/UDP/IPv6/QUIC/MTU/memory or
physical multi-protocol switch acceptance.

Separate cleanup-only receipt confirmed true; lab app uninstalled,
both lab app and extension processes absent; local listeners absent.
Owner profile list/selected profile/organization fingerprints all
match existing baseline; fresh Keychain3 and APL OFF read-only tests
2/2 PASS. Global Settings visual profile-list appearance not inspected
after this particular run; own manager reload/absence and app deletion
verified, do not claim all system-wide settings visually verified.
No user credentials or network profile data retained. Production and
main untouched. Next: physical negative-key and actual native exit,
restart/resource acceptance using a single permission session with
bounded multiple cases and cleanup after last case; then signed
physical WG/AWG and genuine multi-provider routing. Do not repeat
the accepted positive gate just to accumulate local evidence.
