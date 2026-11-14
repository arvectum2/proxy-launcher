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
