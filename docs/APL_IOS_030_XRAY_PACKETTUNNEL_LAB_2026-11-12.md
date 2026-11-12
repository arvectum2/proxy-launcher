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
