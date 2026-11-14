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
