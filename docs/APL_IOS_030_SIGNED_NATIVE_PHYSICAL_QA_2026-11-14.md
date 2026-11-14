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
