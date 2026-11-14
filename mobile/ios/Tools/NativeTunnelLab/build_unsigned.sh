#!/bin/bash
# Compile isolated QA host and embedded app extension. No app installation or signing requests.
set -euo pipefail
umask 077
[[ $# == 2 || ( $# == 3 && "$3" == --approved-sign-lab ) ]] || { echo "usage: $0 PINNED_ASSET PINNED_GO_MOD [--approved-sign-lab]" >&2; exit 2; }
signed=0
if [[ $# == 3 ]]; then signed=1; fi
root="$(cd "$(dirname "$0")/../.." && pwd)"
python="${PYTHON:-python3}"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-native-ne.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
"$python" "$root/Tools/verify_xray_apple_provenance.py" --asset "$1" --go-mod "$2"
mkdir -p "$work/Host" "$work/Sources" "$work/Lib/Xray" "$work/Lib/Rust"
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
"$python" "$root/Tools/verify_tun2proxy_lab_artifact.py" "$framework" ios-arm64 --require-connected-udp
rust="$framework/ios-arm64"
cp "$rust/libtun2proxy.a" "$work/Lib/Rust/"
cp -R "$rust/Headers" "$work/Lib/Rust/"
echo MEASURED_RUST_DEVICE_ARTIFACT
shasum -a 256 "$work/Lib/Rust/libtun2proxy.a"
for name in ProxyModel ManagedProfileContract VLESSRealityShareLink XrayVLESSRuntimeConfig XraySocksHandoffContract TunnelEngineHandoff TunnelEngineExitGate WGQuickConfigurationPreview; do
    cp "$root/SharedCore/$name.swift" "$work/Sources/"
done
cp "$root/Tools/XrayWireGuardLabConfig.swift" "$work/Sources/"
cp "$root/Tools/NativeTunnelLab/"*.swift "$work/Sources/"
cp "$root/Tools/NativeTunnelLab/Host/NativeLabHost.swift" "$work/Host/"
cp "$root/SharedCore/VLESSRealityShareLink.swift" "$root/SharedCore/ManagedProfileContract.swift" "$root/SharedCore/ProxyModel.swift" "$root/SharedCore/WGQuickConfigurationPreview.swift" "$root/Tools/XrayWireGuardLabConfig.swift" "$work/Host/"
# Only the future explicitly approved isolated signing will use these.
cat >"$work/Lab.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.networking.networkextension</key>
    <array><string>packet-tunnel-provider</string></array>
</dict>
</plist>
PLIST
cat >"$work/project.yml" <<'YAML'
name: APLIsolatedNativeLab
options:
  deploymentTarget:
    iOS: "15.0"
targets:
  NativeLabHost:
    type: application
    platform: iOS
    sources:
      - Host
    dependencies:
      - target: NativeLab
        embed: true
    info:
      path: HostInfo.plist
      properties:
        UILaunchScreen: {}
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: true
        NSLocalNetworkUsageDescription: "Connect only to the local synthetic QA peer."
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.proxylauncher.lab.nativeqa
        SWIFT_VERSION: "5.9"
        CODE_SIGN_ENTITLEMENTS: Lab.entitlements
        CODE_SIGNING_ALLOWED: NO
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
        CODE_SIGN_ENTITLEMENTS: Lab.entitlements
        CODE_SIGNING_ALLOWED: NO
        SWIFT_INCLUDE_PATHS: "$(PROJECT_DIR)/Lib/Xray/Headers $(PROJECT_DIR)/Lib/Rust/Headers"
        LIBRARY_SEARCH_PATHS: "$(PROJECT_DIR)/Lib/Xray $(PROJECT_DIR)/Lib/Rust"
        OTHER_LDFLAGS: "-lXray -ltun2proxy -lresolv -framework NetworkExtension -framework SystemConfiguration -framework Security"
schemes:
  NativeLabHost:
    build:
      targets:
        NativeLabHost: all
YAML
(cd "$work" && xcodegen generate >/dev/null)
build_args=(CODE_SIGNING_ALLOWED=NO)
if [[ "$signed" == 1 ]]; then
    # Explicit owner approval limited to the two isolated development IDs.
    # Never register a device or change production signing.
    build_args=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=VML75VY94V CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates)
fi
if ! xcodebuild -project "$work/APLIsolatedNativeLab.xcodeproj" -scheme NativeLabHost -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath "$work/Build" "${build_args[@]}" build >"$work/build.log" 2>&1; then
    grep -E 'error:|BUILD FAILED' "$work/build.log" | tail -20
    exit 1
fi
host="$work/Build/Build/Products/Debug-iphoneos/NativeLabHost.app"
app="$host/PlugIns/NativeLab.appex"
test -f "$host/NativeLabHost"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$host/Info.plist")" == ru.arvectum.proxylauncher.lab.nativeqa ]]
test -f "$app/NativeLab"
/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$app/Info.plist"
# Verify both exact symbols in the built extension, rather than only compiling Swift.
xcrun nm "$app/NativeLab" >"$work/symbols"
echo NATIVE_SYMBOL_CHECK
grep -E "CGoInvoke|tun2proxy_run_with_cli_args|NativeLabPacketTunnelProvider" "$work/symbols" | head -8 || true
grep -E ' [Tt] _CGoInvoke$' "$work/symbols"
grep -E ' [Tt] _tun2proxy_run_with_cli_args$' "$work/symbols"
grep -E "NativeLabPacketTunnelProvider" "$work/symbols" | head -1 || true
if [[ "$signed" == 1 ]]; then
    codesign --verify --deep --strict "$host"
    "$python" "$root/Tools/NativeTunnelLab/verify_signed_lab.py" "$host"
    dest="$(mktemp -d "${TMPDIR:-/tmp}/apl-signed-native-lab.XXXXXX")"
    cp -R "$host" "$dest/"
    printf '%s\n' "$dest/NativeLabHost.app" > /tmp/apl-signed-native-lab-path
    echo ISOLATED_SIGNED_HOST_AND_EMBEDDED_NE_PASS
else
    echo ISOLATED_UNSIGNED_HOST_AND_EMBEDDED_NE_BUILD_AND_NATIVE_LINK_PASS
fi
