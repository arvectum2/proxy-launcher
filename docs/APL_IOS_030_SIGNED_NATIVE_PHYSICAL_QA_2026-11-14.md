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
