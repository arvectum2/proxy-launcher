# IPv6 and DNS guarded loss candidate — 24 Nov 2026

Resumed from accepted UDP4 loss and independent RVI. Extended existing isolated lane only to UDP6 and DNS wire. Corrected scope-specific RVI DNS destination: VLESS uses 198.51.100.77:53, not WireGuard's 192.0.2.53:53. Peer compares exact first and second DNS challenges, cuts relay after first reply; host sends distinct second challenge through same connected session. OFF control and active observation separately checked. A missing OFF positive control (e.g. no native IPv6 route) cannot be interpreted as a leak PASS.

201 checks passed: 93 receipt/RVI, 22 focused, 21 parser, 15 guard, 50 release; release preflight, ARM64 compilation and strict local signatures passed. Independent Mac reference positive preflight passed for both udp6 and dnsWire4 loss scopes, no remaining TCP/UDP listeners. Previous head 1a8093e4 five CI checks success, unsigned-device-build cancelled, not a six-check pass.

Signed artifact native-artifacts/ios-030-provider-full-route-ipv6-dns-loss-signed-20261124/NativeLabHost.app. Host SHA256 2538aac1d84f9cd34b89440f28a93303c39bf07ac903f612621c58c35ff54998; extension dd4564882aabf4d97b3baeafed6538b93e66b421cd5d1202e870c617f45e1b2e.

Installed once with provider absent. Initial read-only census launch failed: CoreDevice 10002, SBMainWorkspace Locked, passcodeRequired true. One explicit launch diagnostic confirmed same. No manager prepared, no synthetic fixture generated on device, no RVI attached or physical traffic trial started. Restored prior signed NativeLab in place, no product change. Only staged input was a benign inspect-only request (not credentials), local copy removed; next launch runner overwrites it. Other Mac GUI work left undisturbed. Physical acceptance blocked until device unlocked or Mirroring available. Runner stored in native-artifacts/ios-030-ipv6-dns-loss-physical-20261124/run.py; use fresh evidence directory, no rebuild. Preserve original profiles and check baseline before mutation. Owner deferred Основной. No release enablement or Apple changes.

## Physical acceptance after owner unlocked device, 19:51 local

Reused signed candidate in fresh evidence directory native-artifacts/ios-030-ipv6-dns-loss-physical-resume-20261124. No active product provider before install. Both protocol-specific OFF controls and established loss trials completed (runner exit0), with independent RVI on exact synthetic tuple only.

| Probe | OFF run | Established loss run | First send/receive bytes | Relay cut after first witness | OFF physical/tunnel | Active physical/tunnel |
|---|---|---|---|---|---|---|
| UDP6 | DB57ACA2-B3BB-4B76-BB18-19EF13BC5358 | 4E2F0011-CCA1-4AFC-9811-F66863C484AF | 48/52 | 575ms | 1/0 | 0/2 |
| DNS wire UDP53 | D1A422F5-EAD3-4FB7-9CBA-10A89D043155 | 73C437AD-EB15-475C-A6B3-C8534180360F | 70/86 | 613ms | 1/0 | 0/2 |

First exact reply, second distinct nonce sent once after relay cut, timeout errno60, provider connected both before/after second challenge; peer secondWitnessCount0, active relay sockets0; exact independent run/challenge/response bindings. All four RVI observations complete, zero ambiguous/kernel drop, RVI removed. Historical manager census identical, owned managers removed, Rust drained and Xray stopped. Previous NativeLab 0.2.0(48) restored; product 0.3.0(49) unchanged, no active provider, no QA sockets or RVI, synthetic key inputs and temporary headers scrubbed. Original selected profile not visually inspected; no profile edits. Основной excluded per owner.

PASS for guarded synthetic UDP4/UDP6/DNS wire fail-closed and non-escape during established peer loss. Not general system DNS, TCP leak, all-destination kill-switch, dynamic underlay, WAN or production acceptance. Remaining product-specific acceptance, WAN/network-switch tests, CloudKit capabilities and release review.
