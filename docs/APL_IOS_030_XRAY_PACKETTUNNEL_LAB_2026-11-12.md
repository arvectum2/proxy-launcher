# iOS 0.3.0 — отдельный PacketTunnel native Xray lab (12.11.2026)

**Статус: isolated research branch, NOT in production main, NOT functional VPN.** Исследование разрешает только типобезопасную компоновку Rust tun2proxy и официальной Go libXray в одном PacketTunnel; не запускалось и не устанавливалось на реальный iPhone.

- Lab branch: `research/ios-030-xray-native-link-20261112` on Mac mini; independent worktree `/Volumes/ArvectumSSD/Arvectum/worktrees/apl-ios-030-xray-packet-tunnel-lab-20261112`.
- Pinned libXray: official `XTLS/libXray v26.11.9` Apple cgo asset sha256 `7c58346709f1856782a48d8f9926fb815c8ad1bbaf9e5d9dec4ee0cd1f41ed6f`. Artifacts symlinked from separate research worktree, **not added to Git and not bundled in production**.
- Existing pinned `tun2proxy.xcframework` and `LibXray.xcframework` both static; ordinary dual `framework:` Xcode build FAILED due to duplicate output `include/module.modulemap` (two ProcessXCFramework tasks). Isolated lab works when Xray is linked as manually selected static `libXray` via platform-specific `LIBRARY_SEARCH_PATHS`, explicit `module.modulemap`, and `-lresolv`; `tun2proxy` stays normal XCFramework dependency.
- `PacketTunnel/XrayNativeLabBridge.swift` compiled only under `APL_XRAY_LAB` in laboratory Debug; exposes test-only `APL_Xray_Lab_Version_Attestation`, which invokes `CGoInvoke` apiVersion3 method `xrayVersion`, frees returned buffers. It is never invoked during normal tunnel start; no VPN options changed.
- [x] Unsigned **iOS Simulator Debug ARM64** App+PacketTunnel BUILD PASS.
- [x] Unsigned **iPhoneOS Debug ARM64** App+PacketTunnel BUILD PASS.
- [x] `nm` on both binaries confirms `_CGoInvoke`, `_tun2proxy_stop` and `_APL_Xray_Lab_Version_Attestation`. PacketTunnel debug dylib ~43 MB.
- [x] Independent Simulator libXray earlier returned `xrayVersion=26.11.9`, synthetic REALITY config conversion and local SOCKS HTTP receipt; see `docs/APL_IOS_030_XRAY_RESEARCH_2026-11-11.md`.
- [ ] No PacketTunnel captured-flow -> local Xray SOCKS -> real VLESS/REALITY server correlation. Prevent loopback capture, DNS leak, Go scheduler/process lifecycle leaks, memory/Go runtime conflicts, and ensure stop/rollback.
- [ ] No legal source/dependency/SBOM acceptance, no signed test-device IPA, no production protocol advertisement.
- [ ] Next: isolated debug-only bridge start/stop/health with timeouts; real physical iPhone egress receipt, IPv4/IPv6, QUIC/DNS, Wi-Fi/LTE, fail-closed recovery.


## Обновление исследования 12.11: код лабораторного handoff без изменений production

- Изолированный local commit: `d0e17ad8d5f627c99f4dc5132de48bdcac41240c` (плюс проверенный internal APFS Git bundle, ссылка в [device acceptance handoff](APL_IOS_030_DEVICE_ACCEPTANCE_HANDOFF_2026-11-12.md)).
- `XrayDebugTunRunner` и `XrayNativeLabBridge.startBlackholeLocal/stopBlackholeLocal`: запустить localhost SOCKS blackhole → валидированный `XraySocksHandoffPlan` → Rust TUN runner на отдельной queue → остановить Rust и дождаться drain → остановить Xray; fail-closed для аварий/устаревшего generation.
- Unsigned iOS Simulator/iPhoneOS ARM64 Debug App+PacketTunnel builds PASS; отдельный Swift CGo blackhole в iOS Simulator: четыре start/stop цикла, duplicate-start fail-closed и idempotent-stop PASS.
- Внимание: `XrayDebugTunRunner` **не вызывается** действующим `PacketTunnelProvider`, original-flow/TUN outbound не доказан; никакого внешнего VPN или пользовательских Apple-операций. Для этой проверки нужен физический iPhone.

## 14.11.2026 — Typed VLESS runtime configuration gate

Added inactive `SharedCore/XrayVLESSRuntimeConfig.swift` on the integrated
QA branch. It takes the validated `VLESSRealityShareLink` and the actual
pinned converter response. It checks the candidate's endpoint, UUID,
encryption, REALITY server name, fingerprint, public key, short ID and
optional Vision flow; rejects multiple outbounds, supplied routing or
listeners, unrecognized transport fields, invalid listener port and
oversize response. It rebuilds a minimal JSON configuration in memory
with a loopback-only SOCKS5 inlet, exactly one VLESS/REALITY RAW outbound,
fixed routing tag, no freedom/DIRECT fallback, no UDP inlet, and logging
disabled in the config. No persistence, activation or production runtime
dependency. The zero-key preview remains available for old import tests,
but cannot form a runtime configuration.

### Measured evidence

- Verified the cached upstream archive and go.mod again against the
  fixed SHA256 pin (28 members, 60 declared Go modules). Freshly extracted
  only the simulator library/header/module map into a private temp directory.
- Built and ad-hoc signed the standalone synthetic Swift harness
  `Tools/XrayVLESSConfigSimulatorQA.swift` against that exact library.
  New, disposable ARM64 iPhone13 iOS27 Simulator (not the real phone).
- Actual pinned CGo API v3 returned version 26.11.9. Two independently
  generated ephemeral Curve25519 key/UUID fixtures, TCP/REALITY without
  Vision and with xtls-rprx-vision, both used
  `convertShareLinksToXrayJson -> strict validated config -> testXray ->
  runXray -> running=true -> local SOCKS greeting [5,0] -> stopXray ->
  running=false -> local port closed`.
- **2/2 PASS**, native executable exit 0. Synthetic VLESS peer was
  loopback port 39882 with no server listening. No real VLESS handshake,
  remote egress, packet capture or WireGuard transport is claimed.
- Swift Core **255/255 PASS**, including 5 new configuration tests;
  iOS Python **373 + 1527 subtests PASS**. Unsigned generic iPhoneOS
  Release App+PacketTunnel BUILD SUCCEEDED. Production project unchanged
  except inclusion of inactive SharedCore file; confirmed no CGoInvoke,
  CGoFree or lab symbols in release PacketTunnel, no LibXray asset in app.
- Added standalone reproducible runner
  `Tools/run_xray_vless_config_simulator_qa.sh` (bash syntax checked;
  the compile/boot/spawn steps were executed individually in this run).
  It requires explicit local pinned asset/go.mod and iOS Simulator runtime
  ID, creates/removes only its own QA simulator/temp files.

### Still not accepted

Real authorized VLESS/REALITY peer and authenticated application-data
receipt, isolated signed PacketTunnel traffic bridge and physical device
memory/egress/stop-drain, support for actual WG transport, AWG provenance,
full SBOM/licensing/reproducible source build. No native protocol added
to production ProxyType, no libXray packaging or installation on real
iPhone. No owner VPN, radio, profile or CloudKit mutation.

## 14.11.2026 — Authenticated isolated VLESS/REALITY application receipt

New standalone lab: `Tools/XrayVLESSPeerSimulatorQA.swift` and
`Tools/run_xray_vless_peer_qa.py`. Two separately built and ad-hoc signed
executables use the same SHA256-pinned libXray v26.11.9 Apple asset:
macOS arm64 server and iOS arm64 Simulator client. Both are outside app
and extension targets. The client imports the synthetic share link,
invokes the real CGo converter, validates via XrayVLESSRuntimeConfig,
and starts its local SOCKS. The server listens on 127.0.0.1:39882,
with ephemeral X25519 key and two random UUIDs (with/without Vision).
OpenSSL local TLS 1.3 decoy and independent HTTP witness bind only
127.0.0.1:39884 and :39883. The synthetic requested host is
apl-receipt.invalid; only that exact domain and target port is routed
to the witness, otherwise default blackhole. Exact finalRules allow
TCP to 127.0.0.1/32:39883 in the test server's receipt-only outbound,
then block everything else. No public listener, external endpoint,
user profile or user data. No global routing/production policy changes.

Initial combined-simulator lab timed out before receipt; moving the
server onto macOS allowed server-side logs to confirm authenticated
VLESS acceptance, but built-in Freedom finalRule blocked the local
witness. Corrected laboratory-only routing by permitting ONLY that
loopback target (not blanket allow). See upstream source
https://github.com/XTLS/Xray-core/blob/main/infra/conf/freedom.go and
https://github.com/XTLS/Xray-core/blob/main/proxy/freedom/freedom.go .
Pinned binary accepted this configuration.

Actual successful run at 10:16 MSK: per-test fresh random 160-bit
HTTP path, exact response body compared on client, independent witness
counts with lock. Client and server state running, bounded lifetime,
explicit stop, state false and port closed checked by each harness.

| Probe | Exact response | Independent witness count |
| --- | --- | ---: |
| Valid UUID/REALITY, no Vision | PASS | 1 |
| Valid UUID/REALITY + Vision | PASS | 1 |
| Incorrect UUID | no response | 0 |
| Incorrect REALITY public key | no response | 0 |
| Correct credentials after server stopped | no response | 0 |

Final set of seen paths exactly equals the two successful paths. No
assumption based simply on SOCKS greeting or startup. Native runtime
and protocol exercised on actual Simulator, with separate native
macOS process and exact application receipt. No independent encrypted
packet-byte analysis; no actual PacketTunnel, external-network,
production backend, signed physical device, Wi-Fi/LTE, resource or
legal acceptance asserted.

Reproduction:
`PYTHON=python3.14 mobile/ios/Tools/run_xray_vless_config_simulator_qa.sh /path/to/libxray-apple-cgo.zip /path/to/pinned-go.mod com.apple.CoreSimulator.SimRuntime.iOS-27-0 --peer`.
Runner verifies pins, extracts only named platform libraries/headers,
compiles and signs both lab executables, creates/deletes own simulator,
uses private temporary directory and local-only owned listeners.
Diagnostic logs from initial troubleshooting were synthetic only;
normal repeated run uses the original config without debug logging.
No raw test key, nonce, config, binary or capture committed.

**Reproduction confirmed at 10:17 MSK:** complete one-command
`--peer` runner from freshly extracted pinned macOS/Simulator libraries
on a new dedicated iOS27 Simulator, with production config logging none:
all five scenarios PASS again; exactly two independent receipts,
zero across the three negative cases. Exit 0. The runner removed its
new simulator and private extraction directory; no listeners remain.

## 14.11.2026 — Real Rust TUN-descriptor to authenticated VLESS peer

Standalone ARM64 iOS27 Simulator linker includes the existing Rust
tun2proxy static library and pinned libXray v26.11.9. The Rust archive
used in this measured run has SHA256
01b829b1bafaa1377eb0d7120725547d92280c55350b0e6d7463e562b824fe53.
This is a digest of the installed artifact, not a new reproducible
source build or a signed provenance attestation (the local version
stamp is missing). The new runner checks that exact artifact before
compiling. No app/extension build settings or system routes changed.

XrayTunPacketQA injects IPv4/TCP packets into a private Unix datagram
socketpair with Darwin four-byte AF_INET packet information, not a
system utun or a NetworkExtension packetFlow. Synthetic source
10.77.0.2 and TEST-NET-2 target 198.51.100.77:39883, TCP SYN,
SYN-ACK, ACK, PSH+ACK, response and ACK/FIN. IPv4 and TCP checksums
are calculated. No direct SOCKS greeting or curl on the client
data path. The macOS server retains only an exact lab IP/port route
or the preceding exact synthetic domain/port, and finalRules restrict
the receipt outbound to the local independent HTTP witness.
The real Rust CLI comes from XraySocksHandoffPlan, using local SOCKS,
virtual DNS, packet information true, and caller-owned descriptor.
The Rust engine runs on a serial blocking queue; actual
TunnelEngineHandoff.stopAndDrain completes before the caller closes
the descriptor and stops Xray. Unexpected Rust exit before planned
stop fails the test. Each case uses a new isolated process.

Measured 10:29 MSK, native execution exit 0:
- Without Vision: exact nonce response, independent count 1.
- With Vision: exact nonce response, independent count 1.
- Wrong UUID, wrong REALITY key, stopped server: no exact response,
  independent count 0 each. All five cases independently report
  SYN-ACK, Rust return code 0, queue drained, caller-owned descriptor
  still open before explicit close, Xray stopped and SOCKS port closed.
- Peak Darwin ru_maxrss of the five isolated client processes:
  66093056, 66617344, 65978368, 68780032, 64536576 bytes.
  This is 61.5–65.6 MiB in this simulator, not a physical extension
  memory limit, no leak trend from repeated processes, nor a
  jetsam/NetworkExtension entitlement test.

The new single-command mode is
`PYTHON=python3.14 mobile/ios/Tools/run_xray_vless_config_simulator_qa.sh /path/to/libxray-apple-cgo.zip /path/to/pinned-go.mod com.apple.CoreSimulator.SimRuntime.iOS-27-0 --tun`.
Requires the measured local Rust artifact and both pinned Apple slices.
It creates and cleans its own simulator, keys, fixtures and listeners.
This closes the synthetic original IP/TCP descriptor handoff gate.
Still outstanding: actual signed NEPacketTunnelProvider original-flow
integration, whole-device capture, unexpected process exit during
active flow and repeated same-process cycles/resource regression on
the real extension, external peer, physical device and legal gates.

Fresh one-command --tun reproduction completed at 10:30 MSK:
same five cases PASS; SYN-ACK and exact independent witness counts
1/1/0/0/0; Rust exit 0, drain, caller descriptor close and stopped
Xray on every case. Both native artifact digests verified. Peak RSS
65503232/65830912/65748992/68288512/64372736 bytes. Runner exit 0,
fresh simulator and temp files removed, no listeners remain.
Focused VLESS inactive/handoff/provenance contract tests: 12 PASS.

## 14.11.2026 — Restart regression: stale Rust artifact detected and rebuilt

Six successive original TCP packet receipts in one client process passed
on the previously measured local Rust archive, but unpaced FD samples
grew 8 -> 18 and RSS 59,736,064 -> 64,880,640 bytes. Longer paced
12-cycle runs then failed unexpectedly after 2–3 completed cycles,
simctl child exit 255, including a traced failure just after beginning
Rust in cycle 4. Xray had started successfully. This was not an
accepted repeatability result.

Both prior Rust archives (sim 01b829b1... / device 8cdbad61e...)
contained the exact upstream `Forcing exit now.` literal and lacked
the source-build manifest. The source-pinned fetch script already
removes the forced process-exit watchdog from general_api.rs. Exit
255 is consistent with exit(-1); combined with the before/after
experiment, stale binaries are the likely cause. No claim about the
actual installed physical iPhone binary follows from inspection of
these local archives.

Built from scratch in a separate directory: v0.8.3 commit
e271de19683937f23d3f8f0eb4df0a61fc4a6e50, upstream archive hash
7f09f01a11fef6d57477df8c32ad3d86ea7fa98ba3aa60099680785ca637ecfd,
Rust1.98.1, locked dependencies and repository patches. Xcode lives
on SSD; initial discovery failed and was corrected with
DEVELOPER_DIR from xcode-select. Both device and simulator slices
compiled, local manifest generated, forced-exit literal absent.
Device SHA256 d95f6075ca3c926c2c329789f0da3abe376b8e55466e86d7713f43a5d979707a
and simulator 5c41479cdb10066f23a17d2fe876ec1a4daec6f5b2e897a564bf49c077b5e00c.
This is a verified local source build, not an independent bit-for-bit
reproducible or externally signed attestation.

Added artifact guard requiring exact local source metadata, patch flag,
digest and absence of the watchdog literal; both old slices rejected.
Fetcher now detects selected Xcode and rejects the unsafe literal in
built archives. Fresh --cycles run with corrected simulator archive:
12/12 same-process start/flow/drain/stop, independent unique receipts
12/12, Rust exit0 every time, process exit0. RSS start 59,916,288,
peak 66,568,192, final 63,291,392 bytes; sampled FDs 8 at startup,
12 from cycle1 through12 (six sockets, of which two INET),
10 after 3s settle (four sockets, zero INET, four UNIX). Counts sampled
first4096 FDs; no monotonic post-warmup growth in this bounded test,
not long-run or physical extension memory proof.

Persisted only the verified rebuilt artifacts in
/Volumes/ArvectumSSD/Arvectum/worktrees/proxy-launcher/native-artifacts/tun2proxy-v0.8.3-20261114.
Rewired only the active QA worktree's ignored Frameworks symlink.
Original shared libraries and main remain untouched.

### Isolated NetworkExtension compile gate
Added Tools/NativeTunnelLab (outside app targets), separate bundle ID
ru.arvectum.proxylauncher.lab.nativeqa.PacketTunnel, explicit synthetic
opt-in and ephemeral candidate only, exact TEST-NET /32 route
198.51.100.77, no default route, DNS, IPv6 or owner profile access.
Strict exact-assigned-address utun descriptor match, no first-utun
fallback. Existing native gate and stopAndDrain, OS-owned descriptor
not closed by caller, 20s timeout after ready, retired provider instance
cannot restart. Actual extension startup/stop race behavior remains
untested. The separate build_unsigned.sh verifies Rust and pinned
Xray archives, generates independent XcodeGen project, compiles ARM64
iPhoneOS extension with CODE_SIGNING_ALLOWED=NO and verifies both
_CGoInvoke and _tun2proxy_run_with_cli_args in the actual executable.
Fresh rebuilt Rust device archive build/link PASS. An initial parallel
build was SIGKILLed, not counted; sequential recheck passed.
No matching local provisioning profile for the lab ID (0 found), no
Apple account registration or install attempted. Signed host app and
lab provisioning, actual NE original-flow, unexpected exit cancellation
and resource testing still required. No physical device change.
Focused contract tests 20/20 and CI/fetch+guard+isolated-lab subset
10/10 PASS; full core unchanged. No production backend activation.

Final post-rebuild --tun regression, 10:44 MSK: 5/5 PASS,
independent witness counts 1/1/0/0/0 (valid without/with Vision, bad
UUID/key, stopped server), every Rust exit0/drain/descriptor close and
Xray stop confirmed, exit0 on fresh simulator. This rules out a
regression of those bounded cases from the new Rust archive.
