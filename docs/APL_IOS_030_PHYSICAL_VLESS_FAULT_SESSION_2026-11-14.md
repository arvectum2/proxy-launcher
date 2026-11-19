# Isolated physical VLESS fault and restart acceptance session

The previous signed physical IPv4 TCP VLESS positive case is accepted.
New work is limited to the already authorized dedicated lab App IDs,
not the production installed app or user profile store.

* Prepare once (explicit VPN permission), verify matching prepare-only
  receipt prepared=true, connected=false, stage labPreparedOff.
* Wrong public key: fresh independent same-peer TLS readiness and two
  positive LAN preflights, then real iPhone with only the wrong key.
  Require OS Connected, actual target packet and relay connection,
  no device nonce at independent witness, no HTTP receipt. Retain
  own lab profile only after confirmed OS disconnected.
* Native exit: fresh valid case must get exact physical receipt. One
  explicit start option supplies fresh six-digit challenge. Matching
  one-shot provider message invokes actual tun2proxy_stop without
  invalidating generation gate. Native run must return zero on the
  unexpected-exit path. Only that path emits challenge-specific provider
  NSError via cancelTunnelWithError. Host waits for OS disconnected and
  fetches lastDisconnectError, requires matching domain and fresh code.
  A request acknowledgment alone is insufficient; normal user stop or
  20-second watchdog cannot produce the challenge-specific receipt.
  Host callback deadlines are bounded to 2s, disconnect wait to 8s.
* Positive restart after this failure: same isolated profile, fresh
  peer/keys and exact receipt. Remove only lab manager after final
  case. Failures abort sequence, perform explicit cleanup and uninstall.
* Each case reports actual extension resident bytes from task_info
  if available. This is a bounded snapshot, not same-process stable
  memory or comprehensive jetsam/peak/leak proof.

Host retainProfile is a one-shot synthetic option, never enables
on-demand VPN. No raw logs/credential output/store; no broad routes,
no automatic fallback, no production wiring. Peer and synthetic
keys recreated per case; same exhaustive exact nonce oracle and
two preflights. Actual C return and OS error still need physical
confirmation. Initial SDK availability compilation failure fixed
with iOS16 availability guard; signed isolated ARM64 build passed.
11 focused contract checks passed.

Run with prepared, disconnected isolated manager and authorized
operator. Use pinned macOS preflight helper from previous evidence:
```sh
B=$(cat /tmp/apl-native-physical-peer-path)
R=mobile/ios/Tools/NativeTunnelLab/run_physical_peer.py
python3.14 "$R" --approved --peer "$B/preflight" --mode wrong-key --retain-profile
python3.14 "$R" --approved --peer "$B/preflight" --mode native-exit --retain-profile
python3.14 "$R" --approved --peer "$B/preflight" --mode positive
```
Abort on any nonzero result; check no live extension before next
case. Complete cleanup-only and app removal; owner fingerprints,
Keychain and APL OFF read-only gate. No new signing IDs needed.

## Actual physical acceptance — 14.11.2026 13:05 MSK

Prepared receipt matched runID, labPreparedOff, prepared=true,
connected=false. Ordered sequence completed in one permission
session (ARC job fdc5b5e9-0064-4d05-a9ff-e5ea8a2ef85c,
exit0, duration22.539s). All six same-peer LAN preflights
received exact nonce once each; each case used fresh keys.

| Case | Connected | Device receipt / independent witness | Native exit | RSS bytes |
| --- | --- | --- | --- | ---: |
| Wrong public key | true | false / 0, timeout -1001 | not requested | 49610752 |
| Native exit | true | true / 1, HTTP200 | challenge-matched OS error true | 47366144 |
| Restart | true | true / 1, HTTP200 | not requested | 47808512 |

Wrong-key case: tcp4/target4/socks1/connect1, cumulative
relay12, bytes24052/29238 including preflights. The bounded
relay reached its connection cap12; no claim about unbounded
retries or all leak paths. Native exit case: tcp1/target1/socks1,
relay3, bytes6849/7804 including preflights. Exact fresh
challenge lastDisconnectError proves actual native return0 on
the unexpected-exit path and OS disconnect, not just normal stop.
Restart: tcp1/target1/socks1, relay3, bytes6817/7804 including
preflights. No live extension observed between cases. First
two retained disconnected lab profile; final case removed it.

Separate cleanup-only receipt true, app uninstall, app/process/
local listeners absent. Owner profile list/selection/organization
hashes all true, existing three Keychain profiles readable and
APL OFF read-only2/2 PASS. Final global Settings visual list not
inspected. Focused38/38 PASS; prior exact-head CI success.
No account changes, new IDs, production activation or main merge.

This accepts bounded physical VLESS TCP data, bad-key rejection,
controlled native exit and positive restart. Resident snapshots
47.3/45.2/45.6 MiB are not peak, long-duration or same-process leak
proof; no broad system-wide kill-switch assertion. Next physical
standard WG lab using existing isolated Rust+Xray target,
then separate AWG-native process/driver, broader routing/resource
and legal/production gates. New IDs or changed scope require owner
approval before registration or installation.
