#!/bin/bash
# Explicit standalone research only. Does not build/install the actual app.
set -euo pipefail
umask 077
if [[ $# != 3 && $# != 4 ]]; then
    echo "usage: $0 PINNED_ASSET PINNED_GO_MOD IOS_SIM_RUNTIME_ID [--peer|--tun]" >&2
    exit 2
fi
if [[ "$(uname -m)" != arm64 ]]; then
    echo "Apple Silicon required" >&2; exit 2
fi
asset="$1"; go_mod="$2"; runtime="$3"
mode="${4:-config}"
[[ "$mode" == config || "$mode" == --peer || "$mode" == --tun ]] || exit 2
[[ "$runtime" == com.apple.CoreSimulator.SimRuntime.iOS-* ]] || exit 2
root="$(cd "$(dirname "$0")/.." && pwd)"
python="${PYTHON:-python3}"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-xray-config.XXXXXX")"
sim=""
cleanup() {
    if [[ -n "$sim" ]]; then
        xcrun simctl shutdown "$sim" >/dev/null 2>&1 || true
        xcrun simctl delete "$sim" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT
"$python" "$root/Tools/verify_xray_apple_provenance.py" --asset "$asset" --go-mod "$go_mod"
# Extract only named files from the verified archive. The peer mode uses
# separate macOS server and iOS Simulator client processes.
"$python" - "$asset" "$work" "$mode" <<'PYEXTRACT'
import sys, zipfile
from pathlib import Path
dest = Path(sys.argv[2])
platforms = {"sim": "ios-arm64_x86_64-simulator"}
if sys.argv[3] in ("--peer", "--tun"):
    platforms["mac"] = "macos-arm64_x86_64"
with zipfile.ZipFile(sys.argv[1]) as archive:
    for directory, platform in platforms.items():
        prefix = "libxray-apple-cgo/LibXray.xcframework/" + platform + "/"
        for name in ("libXray.a", "Headers/libXray.h", "Headers/module.modulemap"):
            path = dest / directory / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(archive.read(prefix + name))
PYEXTRACT
sources=(
    "$root/SharedCore/ProxyModel.swift"
    "$root/SharedCore/ManagedProfileContract.swift"
    "$root/SharedCore/VLESSRealityShareLink.swift"
    "$root/SharedCore/XrayVLESSRuntimeConfig.swift"
)
lab="$root/Tools/XrayVLESSConfigSimulatorQA.swift"
if [[ "$mode" != config ]]; then
    lab="$root/Tools/XrayVLESSPeerSimulatorQA.swift"
    xcrun --sdk macosx swiftc -target arm64-apple-macos13.0 \
        -I "$work/mac/Headers" -L "$work/mac" -lXray -lresolv -framework SystemConfiguration \
        "${sources[@]}" "$lab" -o "$work/hostpeer"
    codesign --force --sign - "$work/hostpeer"
fi
tun_args=()
tun_sources=()
peer_args=()
if [[ "$mode" == --tun ]]; then
    rust="$root/Frameworks/tun2proxy.xcframework/ios-arm64-simulator"
    expected="01b829b1bafaa1377eb0d7120725547d92280c55350b0e6d7463e562b824fe53"
    actual="$(shasum -a 256 "$rust/libtun2proxy.a" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || { echo "Measured Rust artifact hash mismatch" >&2; exit 2; }
    echo "TUN_QA_LIBRARY_SHA256_$actual"
    tun_args=(-D APL_TUN_PAIR_QA -I "$rust/Headers" -L "$rust" -ltun2proxy -framework Security)
    tun_sources=("$root/SharedCore/XraySocksHandoffContract.swift" "$root/SharedCore/TunnelEngineHandoff.swift" "$root/Tools/XrayTunPacketQA.swift")
    peer_args=(--tun)
fi
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios15.0-simulator \
    -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -I "$work/sim/Headers" -L "$work/sim" -lXray -lresolv -framework SystemConfiguration \
    "${sources[@]}" ${tun_sources[@]+"${tun_sources[@]}"} "$lab" ${tun_args[@]+"${tun_args[@]}"} -o "$work/qa"
codesign --force --sign - "$work/qa"
sim="$(xcrun simctl create "APL-XrayConfigQA-$$" com.apple.CoreSimulator.SimDeviceType.iPhone-13 "$runtime")"
xcrun simctl boot "$sim"
xcrun simctl bootstatus "$sim" -b >/dev/null
if [[ "$mode" != config ]]; then
    "$python" "$root/Tools/run_xray_vless_peer_qa.py" --simulator "$sim" \
        --binary "$work/qa" --host-server "$work/hostpeer" ${peer_args[@]+"${peer_args[@]}"}
else
    xcrun simctl spawn "$sim" "$work/qa"
fi
