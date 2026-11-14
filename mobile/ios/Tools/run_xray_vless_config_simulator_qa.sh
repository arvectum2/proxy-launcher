#!/bin/bash
# Explicit standalone research only. Does not build/install the actual app.
set -euo pipefail
umask 077
if [[ $# != 3 ]]; then
    echo "usage: $0 PINNED_ASSET PINNED_GO_MOD IOS_SIM_RUNTIME_ID" >&2
    exit 2
fi
if [[ "$(uname -m)" != arm64 ]]; then
    echo "Apple Silicon required" >&2; exit 2
fi
asset="$1"; go_mod="$2"; runtime="$3"
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
# Extract only these three explicitly named files after pinned inspection.
"$python" - "$asset" "$work" <<'PY'
import sys, zipfile
from pathlib import Path
dest = Path(sys.argv[2])
prefix = "libxray-apple-cgo/LibXray.xcframework/ios-arm64_x86_64-simulator/"
with zipfile.ZipFile(sys.argv[1]) as archive:
    for name in ("libXray.a", "Headers/libXray.h", "Headers/module.modulemap"):
        path = dest / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(archive.read(prefix + name))
PY
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios15.0-simulator \
    -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -I "$work/Headers" -L "$work" -lXray -lresolv -framework SystemConfiguration \
    "$root/SharedCore/ProxyModel.swift" \
    "$root/SharedCore/ManagedProfileContract.swift" \
    "$root/SharedCore/VLESSRealityShareLink.swift" \
    "$root/SharedCore/XrayVLESSRuntimeConfig.swift" \
    "$root/Tools/XrayVLESSConfigSimulatorQA.swift" -o "$work/qa"
codesign --force --sign - "$work/qa"
sim="$(xcrun simctl create "APL-XrayConfigQA-$$" com.apple.CoreSimulator.SimDeviceType.iPhone-13 "$runtime")"
xcrun simctl boot "$sim"
xcrun simctl bootstatus "$sim" -b >/dev/null
# The harness itself refuses hardware and checks all private lab ports are free.
xcrun simctl spawn "$sim" "$work/qa"
