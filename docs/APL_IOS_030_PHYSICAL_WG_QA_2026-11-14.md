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
