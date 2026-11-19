# Standard WireGuard independent peer interoperability

## Scope and source

Client: actual ARM64 iOS Simulator pinned libXray v26.11.9 and the
corrected source-built Rust tun2proxy. Original synthetic TCP packet
injection on the private Darwin-framed datagram descriptor follows
the previously accepted --wg test.

Server: separate standalone macOS ARM64 executable built from official
WireGuard wireguard-go tag 0.0.20250522, commit
f333402bd9cbe0f3eeb02507bd14e23d7d639280. Source:
https://github.com/WireGuard/wireguard-go/tree/f333402bd9cbe0f3eeb02507bd14e23d7d639280 .
Upstream go.mod SHA256
87e5574c17f1c8d3badd9195d933237c289c07b5813f4e60ceae36c7b270e288,
go.sum 1aa8ba6a11e01ea4554607a7dd5402132b6912e6d4704474986d3044cef1ff69.
The upstream checkout is pinned, clean, locally replaced in Go module
resolution. The lab module metadata uses the commit's UTC timestamp.
Separate verified Go1.25.0 toolchain archive, locked Go modules;
CGO_ENABLED=0, no Xray or AWG dependency in server executable.
Current supported patched Go and security/license review are still
required before production; this server is research-only.

The reference server uses the upstream WireGuard device and userspace
gVisor TCP/IP netstack. Custom bind restricts UDP to the fixed
localhost relay endpoint. Synthetic in-tunnel address 198.51.100.77
has exactly one TCP listener; only the independent HTTP witness
at 127.0.0.1:39883 is reachable through that application listener.
No system utun, default route, public port, owner keys or user traffic.
No unrestricted forwarding. The loopback UDP relay records only message
header counts; independent Python HTTP witness records exact random
nonce path receipts. Both peers use ephemeral random keys and PSK.
All processes have bounded lifetime and are cleaned by the runner.

## Reproduction

```sh
APL_QA_WG_REFERENCE_CHECKOUT=/path/to/pinned/upstream \
APL_QA_GO_TARBALL=/path/to/verified/go1.25.0.darwin-arm64.tar.gz \
PYTHON=python3.14 mobile/ios/Tools/run_xray_vless_config_simulator_qa.sh \
  PINNED_ASSET PINNED_GO_MOD com.apple.CoreSimulator.SimRuntime.iOS-27-0 --wg-reference
```

New reference mode builds the macOS server from the pinned source
and verifies the Go module graph has no Xray or Amnezia dependency.
The initial graph guard accidentally matched the parent temp directory
name containing "xray"; fixed to inspect only module/dependency lines.
No network test result was claimed from that rejected preflight.

Four cases: valid keys/PSK, wrong responder public key, wrong PSK,
server stopped. Exact application receipts are the oracle; individual
UDP header counts in negative phases may include delayed previous
session packets, not authentication evidence. This is not an
independent physical NE or IPv6/application UDP proof.

## Measured fresh run 11:14 MSK

Pinned Rust simulator artifact SHA256
5c41479cdb10066f23a17d2fe876ec1a4daec6f5b2e897a564bf49c077b5e00c;
reference server measured binary SHA256
b3aef3440a1824b35746110c9e4ca909873d856e9d04149d93bf992511dcfaaf.
Go graph guard, upstream hashes, native Xray archive verification
and Rust artifact guard passed. Fresh iOS27 Simulator run exit0.

| Case | Exact HTTP response | Witness receipts | Initiations | Replies | Client data | Server data |
|---|---|---:|---:|---:|---:|---:|
| Valid key/PSK | yes | 1 | 1 | 1 | 6 | 5 |
| Wrong public key | no | 0 | 2 | 0 | 0 | 0 |
| Wrong PSK | no | 0 | 2 | 2 | 0 | 0 |
| Server stopped | no | 0 | 2 | 0 | 0 | 0 |

All four client processes confirmed SYNACK from Rust's virtual
TCP frontend, Rust exit0, drain, caller FD close and Xray stop.
Server graceful shutdown and UDP port release verified.
The incorrect PSK response headers do not represent authenticated
transport. Independent HTTP nonce oracle is authoritative.
26 focused contract checks passed. No production/device mutation.
