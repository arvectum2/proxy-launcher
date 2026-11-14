# Physical standard WireGuard QA — prepared

Existing isolated development IDs and signed Rust+Xray host/NE reused.
No new App-ID or production target. New explicit wg-dual lab mode
requires standard WG parsed configuration, exact two internal addresses,
one peer with fixed 192.168.1.80:39881 endpoint, and exact synthetic
IPv4/IPv6 host AllowedIPs. Simulator default still localhost only.
No AWG downgrade, DNS/default routes or freedom outbound. Corrected
connected-UDP native artifact required by signing build. iOS settings
scope only 198.51.100.77/32 and 2001:db8:77::77/128 for WG; MTU1280.
Host sends exact TCP HTTP or bounded NWConnection UDP nonce requests,
checks exact response while connected. UDP probeCode200 is a local
success marker, not HTTP status.

Independent official pinned wireguard-go reference process and private
UDP relay (LAN restricted, single source endpoint, bounded counts),
loopback TCP and UDP witnesses. Local macOS preflight with real pinned
Xray WG client, exact HTTP receipt + handshake/transport evidence
PASS. Fresh reference process after preflight avoids reused replay state.
Physical runner separately requires exact application witness, native
WG handshake counts, no wrong-key reply and no data returned. No
physical result yet. Compiler-flag-gated native Mac helper permits WG
client only with exact lab endpoint; ordinary simulator/default role
constraints remain. Signed ARM64 host/NE build PASS; focused40 PASS.

Temporary isolated application installed, prior owner fingerprints true,
no active production or test extension at installation. Permission-only
phase launched. Next require matching prepared OFF receipt, no live
extension, then bounded cases in one permission session:
```sh
A=/Volumes/ArvectumSSD/Arvectum/worktrees/proxy-launcher/native-artifacts
B=$(cat /tmp/apl-native-physical-peer-path)
R=mobile/ios/Tools/NativeTunnelLab/run_physical_wg.py
# each invocation uses fresh server and nonce; abort on failure
for kind in tcp4 udp4 udp6 tcp6; do
 python3.14 "$R" --approved --reference "$A/wg-reference-20261114/wg-reference-peer" --preflight "$B/wg-preflight" --kind "$kind" --retain-profile
done
python3.14 "$R" --approved --reference "$A/wg-reference-20261114/wg-reference-peer" --preflight "$B/wg-preflight" --kind tcp4 --wrong-key
```
Check extension absence between cases, explicit cleanup on failure,
uninstall and owner fingerprint/APL OFF/Keychain gate. No blind retries.
Physical standard WG results pending; separate AWG runtime/signing and
production integration still open.

## Actual iPhone execution — 14.11.2026 13:16–13:24 MSK

Owner permission-only matching prepared OFF receipt verified. The
initial installed baseline connected-UDP Rust library accepted TCP4
(HTTP200, exact witness1, handshake1/1, transport5/5, RSS47153152).
UDP4 failed after real target packet, SOCKS association, no WG
handshake or data, error errno49 EADDRNOTAVAIL. A second/third
diagnostic signed update reproduced errno49. Direct local SOCKS
association confirmed reply IPv4 loopback, nonzero port, and
both wildcard and explicit loopback UDP bind/connect success.
The actual failed operation was not independently isolated by those
connect-only probes.

Built a strictly separate Rust device candidate from pinned v0.8.3
plus existing patches: use explicit LOCALHOST for loopback UDP peers
(without changing non-loopback address selection) and stage-specific
error counters. No production patch or Frameworks symlink change.
Candidate SHA256:
9b1553c894f3a8c1669ba1cc8a37833f696a8f378bd91f0883d97fa12b87e1df.
Reproduction source NativeTunnelLab/tun2proxy-connected-udp-loopback-candidate.patch
and build_udp_candidate.sh; measured durable library under native-artifacts/
tun2proxy-v0.8.3-loopback-udp-candidate-20261114. Candidate signed
isolated extension updated in place without extra VPN permission.
First two candidate UDP4 probes no longer emitted errno49; handshake
and transport1/1 but no witness. In second failure encrypted type4
lengths112 inbound/144 outbound, UDP witness received nothing.
Potential ICMP rejection not proven in that pre-instrumentation run.
Do not assert the loopback fix alone eliminated all intermittent errors.

Added independent peer measurement wrapper (logical IP version,
protocol, allowed source/destination boolean, fixed destination-port
boolean, UDP length, checksum-zero flag, ICMP type/code only);
no decrypted payload/address values logged. Exact pinned upstream
reference rebuilt successfully (SHA256
7a59845559e8334fdcd93f335f414737cfedfe1810bd99c86eff3bf05a50af60,
wg-reference-peer-diag). On the candidate, next UDP4 succeeded,
then ordered remaining four cases passed (exit0, 19.399s).
Each case fresh reference process and exact LAN TCP preflight1/1.

| Case | Exact device witness | Handshake init/reply | Encrypted data in/out | RSS bytes |
| --- | ---: | --- | --- | ---: |
| Baseline TCP4 | 1 | 1/1 | 5/5 | 47153152 |
| Candidate UDP4 first success | 1 | 1/1 | 1/1 | 46710784 |
| Candidate UDP4 repeat | 1 | 1/1 | 1/1 | 46940160 |
| Candidate UDP6 | 1 | 1/1 | 1/1 | 46661632 |
| Candidate TCP6 | 1 (HTTP200) | 1/1 | 5/5 | 46399488 |
| Candidate TCP4 wrong-key | 0 (timeout) | 1/0 | 0/0 | 46956544 |

On each successful UDP case independent witness received exactly
48 bytes, raw IP metadata matched expected source/destination and
UDP destination port39883, length56 including UDP header, nonzero
checksum. Reverse packet length60 including UDP header; TX diagnostic
booleans describe forward direction and are expected false for reverse.
UDP code200 is a success marker, not HTTP. Physical evidence for each
required protocol/negative case now exists; **not final release acceptance**
because initial UDP4 failures and diagnostic candidate mix require
stable repeatability, remove invasive local SOCKS diagnostic and
temporary raw-log category probes, clean minimal patch and rebuild
device/simulator, retest under fresh independent peer without
instrumentation and on candidate final TCP4/VLESS regressions.
No same-process leak, MTU/DNS/QUIC or whole-device guarantee.

Separate cleanup-only true, uninstall and lab process/app/listener
absence, owner profiles/selected/org hashes true and fresh Keychain3/
APL OFF read-only2/2 PASS. Final global Settings visual unverified.
Focused40/40 PASS. No production activation, account or main changes.

## 21:24–21:29 MSK — minimal clean candidate and regression gate

Built clean source-pinned Rust candidate in isolated durable destination
native-artifacts/tun2proxy-v0.8.3-loopback-udp-clean-20261114.
Only effective additional behavior versus connected-UDP baseline:
explicit local source address for loopback peers, both address families.
No diagnostic stage logging in Rust; removed extra SOCKS association
probe from isolated provider. Independent reference netstack instrumented
wrapper is now explicit opt-in via measure=true; default uses original
uninstrumented path. Production patch and canonical framework unchanged.
Historical diagnostic candidate patch at prior commit retained.

Device SHA256 e81642cf494e218aeb3314289f235eeff8dff21dc8d72b8bd23ded8b41c0b852
Simulator SHA256 eb48446d2c94bddd0e5eb3fe49b37e86efcb4eff229665f930fd679acc0df75f
Independent clean reference SHA256 bcb050d80c22c18baa5f3fbac66e885652b5e681655bf768dd11ee436116976d.
Verified source-pinned build and both slice digests. Fresh WG dual native
simulator 12/12 PASS (valid UDP4/UDP6/TCP6 exact1 each; bad key/PSK/stopped
all0). VLESS native TUN simulator 5/5 PASS (two authenticated, three
negative). Focused42/42 PASS. Signed existing isolated host+NE built
and signatures verified; measured device archive exact clean SHA above.
Regression job exit0. Clean independent LAN WG preflight1/1 PASS after
simulator released shared ports (initial parallel preflight refused
bind with EADDRINUSE, no device action).
Logs /tmp/apl-loopback-clean-{build,wg-dual,tun,signed}.log.

Prepared run_clean_wg_stability.sh: require matching prepared OFF receipt,
check no active production/lab extension before and between cases,
TCP4, three UDP4/UDP6 pairs, TCP6, wrong key, final VLESS positive
regression with final owned manager removal. No automatic retries;
fresh key/nonce/reference for each WG case. Use same signed candidate
and clean uninstrumented reference. Hardware result not yet available.

Attempted pre-installation check: **production Arvectum Packet Tunnel
process present**. Guard stopped before app installation, profile
mutation or any device test. Do not interrupt the user's active VPN.
Await owner explicitly disconnecting APL and reporting ready; recheck
no live extension, current owner fingerprints, verify signed candidate,
install only authorized isolated host, prepare-only permission and
verify exact matching OFF receipt. Then run sequence:
```sh
A=/Volumes/ArvectumSSD/Arvectum/worktrees/proxy-launcher/native-artifacts
B=$(cat /tmp/apl-native-physical-peer-path)
PYTHON=python3.14 mobile/ios/Tools/NativeTunnelLab/run_clean_wg_stability.sh --approved "$A/wg-reference-20261114/wg-reference-peer-clean" "$B/wg-preflight" "$B/preflight"
```
Abort and retain evidence on any failure, cleanup-only and uninstall
if appropriate, confirm owner parity, Keychain3 and APL OFF. Initial
diagnostic candidate's two no-witness events remain unresolved; do
not promote patch before stable physical acceptance. No AWG new
signing IDs, production release or account changes.

## 22:25–22:27 MSK — owner-authorized supervised attempt

14.11 22:27 MSK: Mirroring connected, owner authorized normal UI disconnect completed, no active extension, isolated signed clean host/NE verified and installed, prepare-only launched. Allow on Mirroring triggered OS Mac login authentication. No test tunnel or peer started. Canceled, owned cleanup confirmed, lab uninstalled, production APL restored via normal UI to Netherlands 2 Connected; owner profiles/selection/organization hashes identical before/after. Await supervised direct iPhone VPN Allow or locally authenticated Mirroring. No clean physical case executed; no egress or Keychain acceptance claimed for this session.

## 22:34–22:35 MSK — clean physical stability PASS

Permission-only prepared OFF confirmed by matching runner precondition. Exact previously verified isolated signed clean artifact, independent clean reference, no retries. Sequence EXIT=0 and CLEAN_WG_STABILITY_AND_VLESS_REGRESSION_PASS.

| Case | Exact witness | Handshake | Result |
|---|---:|---|---|
| TCP4 | 1 | 1/1 | PASS |
| UDP4/UDP6, three fresh pairs | 1 each | 1/1 each | 6/6 PASS |
| TCP6 | 1 | 1/1 | PASS |
| Wrong WG key | 0 | 1/0, data 0/0 | PASS (negative) |
| VLESS positive regression | 1 | two LAN preflights PASS | PASS |

Provider RSS range 46,252,032–47,497,216 bytes. All cases bounded and isolated; no production backend promotion. Owned cleanup independently confirmed, lab app uninstalled, production tunnel restarted through normal UI with same selected profile; owner profiles/selection/organization hash equality verified. Public egress and Keychain were not independently retested in this session. This closes the clean physical stability gate, not universal protocol/production release acceptance.
