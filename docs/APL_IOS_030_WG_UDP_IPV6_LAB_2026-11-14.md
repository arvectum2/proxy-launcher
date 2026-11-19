# Standard WireGuard native application UDP / IPv6 laboratory

## Scope

Separate official wireguard-go reference peer on macOS from
the previous interop gate, corrected native Rust tun2proxy and
pinned libXray26.11.9 on ARM64 iOS Simulator. New --wg-dual
mode adds two synthetic IP addresses (IPv4 /32 and IPv6 /128)
and exact synthetic destination routes. Rust receives original
Darwin-framed IPv4 UDP, IPv6 UDP, and IPv6 TCP packets over a
private socketpair, not an OS VPN. Xray SOCKS UDP explicitly
enabled only in this standalone lab; no DIRECT outbound, and
SOCKS reply IP pinned to localhost. Independent Python TCP and
UDP witnesses compare unique nonce and exact returned content.
Reference server's only application forwarding targets are
local TCP/UDP witness sockets; no public listener or arbitrary forwarding.

## Reproduced defect and source correction

Before the fix, three repeated valid-credential dual-stack runs
returned exact witness counts 0/0/1 (UDP4/UDP6/TCP6).
TCP6 native packet receipt passed each time. Both UDP flows reached
SOCKS association, but no corresponding peer handshake was observed.
Lab-only Rust log callback isolated the error:
`Socket is already connected (os error 56)` for both IP families.
The pinned tun2proxy v0.8.3 implementation connects each UDP socket,
then wraps it in udp-stream0.0.12, whose AsyncWrite uses poll_send_to
with the explicit peer. Darwin rejects this use on the connected
socket. Xray had accepted the association but the TCP control and
relay socket then closed when the Rust handler returned the error.
Explicit SOCKS reply IP alone did not fix it.

Patch mobile/ios/Tools/tun2proxy-connected-udp.patch:
retain the exact connected tokio socket; send one datagram with
UdpSocket.send and receive via recv instead of a byte-stream
adapter using sendto. Check complete send length; never redirect
to another peer. No change in TCP logic, upstream/proxy selection,
configuration or DIRECT eligibility. Applied after the existing
pinned patches; fetcher records the connected-udp patch flag.
The --wg-dual runner refuses a pre-fix local manifest; both
slices built separately with Rust1.98.1 and pinned upstream commit
e271de19683937f23d3f8f0eb4df0a61fc4a6e50. Device SHA256
dda7ce82ff60d6b44a91d7c0ef145d6eeefddce0723580c073b560944781dfe8;
simulator 37c7c2c9c3c32035bb7fe04978d160e08ce7bc4ef8bb8c05575a9c4cc235accc.
Local source-build metadata verified, not independent bit-for-bit
reproducibility. No actual iPhone installation or production activation.

31 focused contract tests pass. Fresh corrected dual-stack test uses
ordinary logging none/warn (temporary debug callbacks removed).
Scope is small unfragmented application datagrams; do not infer
QUIC, MTU, large datagram, DNS, loss, multi-session, physical NE,
all protocol or whole-device leak acceptance.

## Corrected fresh dual-stack run — 11:28 MSK

Runner `--wg-dual`, exit 0, verified device/sim artifact copies
stored at native-artifacts/tun2proxy-v0.8.3-connected-udp-20261114.

| Case | UDP4/UDP6/TCP6 exact witness counts | WG initiations | WG replies | Transport in/out |
| --- | --- | ---: | ---: | ---: |
| Valid | 1/1/1 | 3 | 3 | 7/7 |
| Incorrect public key | 0/0/0 | 6 | 0 | 0/0 |
| Incorrect PSK | 0/0/0 | 6 | 6 | 0/0 |
| Server stopped | 0/0/0 | 6 | 0 | 0/0 |

All 12 probe lifecycles: Rust exit0, actual drain and descriptor close,
Xray stopped, TCP6 SYNACK or exact UDP packet injection marker.
Exactly three positive application receipts and no negative receipt.
The observed negative PSK handshake replies are not proof of session
authentication. No transport data or witness receipts for negative
cases. This proves bounded synthetic data and routing behavior,
not general device-level leak freedom. New artifact was built in a
separate directory, old shared copies and actual phone unchanged.

Reproduce with APL_QA_TUN2PROXY_FRAMEWORK pointing to the rebuilt
connected-udp XCFramework; use the same reference checkout and Go
tarball as the --wg-reference runner but pass --wg-dual.

Post-fix fresh IPv4 TCP VLESS/REALITY regression --tun, 11:29
MSK: 5/5 PASS with/without Vision, bad UUID/key/stopped server,
exact witness counts1/1/0/0/0, all native drain/stop, runner exit0.
Both corrected artifacts persisted and verified; only active QA
worktree ignored Frameworks symlink switched to connected-udp build.
Original shared artifact paths and main unchanged. Both fresh
simulators, temporary fixtures and local listeners cleaned.
