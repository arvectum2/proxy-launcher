# APL iOS 0.3.0 — isolated AmneziaWG source/build/packet gate

Status: standalone lab, no active production backend, no real iPhone
or OS tunnel. This is not an AmneziaWG product compatibility claim.

## Source and architecture decision

* Official amnezia-vpn/amneziawg-go v3.1.20260828, commit
  b5928efb6ca19f0153958460c3d141f04abc5c2e.
  go.mod SHA256 9fd0084da2acc4f96225daee85c0f866a0ec1079d5bdc4cf98c50e8a8fa0baf6;
  go.sum SHA256 eab202288b6f879fe1f6b0d9da0c528cfb310d74a7a4d409c7268c2b26b98a0a.
  MIT license. Source: https://github.com/amnezia-vpn/amneziawg-go/tree/b5928efb6ca19f0153958460c3d141f04abc5c2e
* Apple reference source inspected at
  3bca528aca844bbe6b665d8ab5c6724cd261fd54:
  https://github.com/amnezia-vpn/amneziawg-apple/tree/3bca528aca844bbe6b665d8ab5c6724cd261fd54 .
  Its combined bridge has AWG3.1.20260814, Go1.26 and an Amnezia fork of
  Xray/libXray, rather than APL's already tested upstream Xray release.
  Do not replace the established Xray dependency or link two independently
  built Go C archives into one extension. Choose a separate AWG native
  PacketTunnel process; production manager/backend selection, routing
  parity and transactional handoff still need design/QA.
* Official Go toolchain 1.25.0 darwin-arm64 archive SHA256
  544932844156d8172f7a28f77f2ac9c15a23046698b6243f633b0a0b00c0749c,
  verified against https://go.dev/dl/?mode=json&include=all .
  Exact toolchain chosen for this prototype's module baseline, not a
  security-approved shipping compiler. Upgrade to current supported
  patched Go and re-run before commercial packaging.
* The separate AWG bridge uses upstream device API and ChannelTUN
  (private test packet input/output), a custom loopback-only UDP Bind,
  and no Xray, Rust, actual utun or OS network configuration. The
  input/output is exact raw IPv4/IPv6 ICMP, not app TCP/UDP. No
  packet or credential data logged; synthetic keys per case.

## Preliminary dependency/license inventory

Measured iOS package graph of lab (not merely all upstream go.mod
entries):

| Actual source module | Pin | Root license |
| --- | --- | --- |
| amneziawg-go/v3 | v3.1.20260828 | MIT (LICENSE SHA256 9ec168d1f4af53f293be8bd2e882588f0e35af0334292d4ca4e5ede84408420e) |
| golang.org/x/crypto | v0.42.0 | BSD-style |
| golang.org/x/net | v0.44.0 | BSD-style |
| golang.org/x/sys | v0.36.0 | BSD-style |

All three x/* LICENSE root files hash
911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad.
Go runtime/toolchain standard-library notices also apply. Go module graph
and lockfiles retained; modules such as gVisor and wintun appear in
module resolution but not in this measured Apple lab's package graph.
This is an initial license inventory, not a distributing-product SBOM
or comprehensive license clearance. Final per-file/embedded notices,
security updates, reproducibility, export compliance and platform
review remain. No source or binaries of third parties committed here.

## Measured evidence

First standalone local build 11:05–11:06 MSK: source checkout exact
commit and clean; upstream module checksum files recorded. Official
verified Go installed entirely in separate research directory. ARM64
macOS, iOS simulator and iPhoneOS static C archives compiled. Native
macOS and fresh ARM64 iOS27 Simulator each returned
APL_AWG_NATIVE_PACKET_QA_RC_0, two unique complete IPv4 ICMP frames
exchanged in opposite directions through actual localhost UDP.
Unsigned iPhoneOS executable linked and nm verified aplAWGSelfTest.
No actual physical execution; initial macOS archive had host SDK
deployment warning, corrected target flags in later reproducible runner.
The fixed matching legacy fixture is understood by this pinned v3
engine; do not infer broad interop across AWG1/2/3 releases from it.

Expanded runner:
`mobile/ios/Tools/AWGNativeLab/build_and_test.sh PINNED_AWG_CHECKOUT PINNED_GO_TAR com.apple.CoreSimulator.SimRuntime.iOS-27-0`.
Checks exact clean AWG source, Go archive and module file hashes,
uses locked Go modules, builds independent ARM64 libraries and
executables for three Apple targets, checks exported C ABI and no
Xray symbol, runs macOS and a fresh simulator, cleans temporary
artifacts. Modes: correct credentials/PSK: unique IPv4 and IPv6
frames bidirectional; wrong responder public key and wrong PSK:
bounded no receipt, with actual client send and peer UDP receive.
The two traffic peers are within a single lab process; receiver
side compares exact independent input and output byte arrays, not
an independently implemented server. No app TCP/UDP, kernel TUN,
underlay network switch, hardware extension or production failover.

Persistent reference source/toolchain directory:
 /Volumes/ArvectumSSD/Arvectum/worktrees/proxy-launcher/native-artifacts/awg-source-20261114
contains pinned clean upstream source and toolchain and the initial
prototype binaries (not the expanded runner output). Neither production
project nor the corrected Rust symlink is modified. Use runner for
fresh evidence, do not ship cached prototype libraries.

## Remaining
* Separate signed lab extension, actual OS-owned tunnel descriptor
  bridge with lifecycle, bounded fail-closed, startup/cancellation,
  memory/restart and traffic/route parity. No second Go runtime.
* Full secure AWG profile parsing and explicit version/format selection;
  legacy preview has no secret storage. No silent WG fallback.
* Test independently implemented AWG peers and version-specific
  interoperability (including ranges and new fields), IPv4/IPv6
  application TCP/UDP, DNS, radio handoff, physical iPhone and legal gate.
* No change to production ProxyType or Apple Developer account.

## Expanded fresh runner receipt, 11:08 MSK

Exit 0, go mod verify PASS, three ARM64 archive/executable link
checks PASS (no Xray symbol). Both fresh macOS and iOS27 Simulator
native runs: CASE_0_RC_0 (IPv4 and IPv6 each way), CASE_1_RC_0
(wrong responder key: no receipt), CASE_2_RC_0 (wrong PSK: no receipt).
The negative cases confirm UDP send and receive, not merely an
unconfigured device. Each case verifies both loopback sockets closed
on device.Close. Archive SHA256 for this measured compilation:
macOS 44887e5f62218efa6fc326f5dc8daea053d76d27f1111c9763fd05c85c23c9e9,
simulator 3b4a9b3dd2d455918f47cace9e5c94fc46ae4f3274235350b4aca34eb0618a77,
iPhoneOS fc9a042185c5127cb875e9498ccdce1fe916aef02479600f466bce6d3a0ffe8e.
These are measured hashes, not independent bit-for-bit reproducibility.
Focused source/contract tests 23/23 PASS. Actual physical iOS
execution, full compatibility and production acceptance remain pending.
