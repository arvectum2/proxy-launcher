#!/bin/bash
# Compile isolated app extension only. No app installation or signing requests.
set -euo pipefail
umask 077
[[ $# == 2 ]] || { echo "usage: $0 PINNED_ASSET PINNED_GO_MOD" >&2; exit 2; }
root="$(cd "$(dirname "$0")/../.." && pwd)"
python="${PYTHON:-python3}"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-native-ne.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
"$python" "$root/Tools/verify_xray_apple_provenance.py" --asset "$1" --go-mod "$2"
mkdir -p "$work/Sources" "$work/Lib/Xray" "$work/Lib/Rust"
"$python" - "$1" "$work/Lib/Xray" <<'PY'
import sys,zipfile
from pathlib import Path
p=Path(sys.argv[2]);prefix="libxray-apple-cgo/LibXray.xcframework/ios-arm64/"
with zipfile.ZipFile(sys.argv[1]) as z:
    for key in ("libXray.a","Headers/libXray.h","Headers/module.modulemap"):
        dest=p/key;dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(z.read(prefix+key))
PY
framework="${APL_QA_TUN2PROXY_FRAMEWORK:-$root/Frameworks/tun2proxy.xcframework}"
"$python" "$root/Tools/verify_tun2proxy_lab_artifact.py" "$framework" ios-arm64
rust="$framework/ios-arm64"
cp "$rust/libtun2proxy.a" "$work/Lib/Rust/"
cp -R "$rust/Headers" "$work/Lib/Rust/"
echo MEASURED_RUST_DEVICE_ARTIFACT
shasum -a 256 "$work/Lib/Rust/libtun2proxy.a"
for name in ProxyModel ManagedProfileContract VLESSRealityShareLink XrayVLESSRuntimeConfig XraySocksHandoffContract TunnelEngineHandoff TunnelEngineExitGate; do
    cp "$root/SharedCore/$name.swift" "$work/Sources/"
done
cp "$root/Tools/NativeTunnelLab/"*.swift "$work/Sources/"
cat >"$work/project.yml" <<'YAML'
name: APLIsolatedNativeLab
options:
  deploymentTarget:
    iOS: "15.0"
targets:
  NativeLab:
    type: app-extension
    platform: iOS
    sources:
      - Sources
    info:
      path: Info.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.networkextension.packet-tunnel
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).NativeLabPacketTunnelProvider
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.proxylauncher.lab.nativeqa.PacketTunnel
        SWIFT_VERSION: "5.9"
        APPLICATION_EXTENSION_API_ONLY: YES
        ENABLE_DEBUG_DYLIB: NO
        CODE_SIGNING_ALLOWED: NO
        SWIFT_INCLUDE_PATHS: "$(PROJECT_DIR)/Lib/Xray/Headers $(PROJECT_DIR)/Lib/Rust/Headers"
        LIBRARY_SEARCH_PATHS: "$(PROJECT_DIR)/Lib/Xray $(PROJECT_DIR)/Lib/Rust"
        OTHER_LDFLAGS: "-lXray -ltun2proxy -lresolv -framework NetworkExtension -framework SystemConfiguration -framework Security"
schemes:
  NativeLab:
    build:
      targets:
        NativeLab: all
YAML
(cd "$work" && xcodegen generate >/dev/null)
if ! xcodebuild -project "$work/APLIsolatedNativeLab.xcodeproj" -scheme NativeLab -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath "$work/Build" CODE_SIGNING_ALLOWED=NO build >"$work/build.log" 2>&1; then
    grep -E 'error:|BUILD FAILED' "$work/build.log" | tail -20
    exit 1
fi
app="$work/Build/Build/Products/Debug-iphoneos/NativeLab.appex"
test -f "$app/NativeLab"
/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$app/Info.plist"
# Verify both exact symbols in the built extension, rather than only compiling Swift.
xcrun nm "$app/NativeLab" >"$work/symbols"
echo NATIVE_SYMBOL_CHECK
grep -E "CGoInvoke|tun2proxy_run_with_cli_args|NativeLabPacketTunnelProvider" "$work/symbols" | head -8 || true
grep -E ' [Tt] _CGoInvoke$' "$work/symbols"
grep -E ' [Tt] _tun2proxy_run_with_cli_args$' "$work/symbols"
grep -E "NativeLabPacketTunnelProvider" "$work/symbols" | head -1 || true
echo ISOLATED_UNSIGNED_DEVICE_NE_BUILD_AND_NATIVE_LINK_PASS
