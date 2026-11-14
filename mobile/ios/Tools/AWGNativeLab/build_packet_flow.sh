#!/bin/bash
# Build-only, separate unsigned NE; no registered bundle or device changes.
set -euo pipefail
umask 077
[[ ( $# == 2 || $# == 3 ) && "$(uname -m)" == arm64 ]]
export_dir=""
if [[ $# == 3 ]]; then
  export_dir="$(cd "$3" && pwd)"
  [[ ! -e "$export_dir/AWGCompileHost.app" ]]
fi
source_dir="$(cd "$1" && pwd)"
go_tar="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
[[ "$(git -C "$source_dir" rev-parse HEAD)" == b5928efb6ca19f0153958460c3d141f04abc5c2e && -z "$(git -C "$source_dir" status --porcelain)" ]]
[[ "$(shasum -a256 "$source_dir/go.mod" | awk '{print $1}')" == 9fd0084da2acc4f96225daee85c0f866a0ec1079d5bdc4cf98c50e8a8fa0baf6 ]]
[[ "$(shasum -a256 "$source_dir/go.sum" | awk '{print $1}')" == eab202288b6f879fe1f6b0d9da0c528cfb310d74a7a4d409c7268c2b26b98a0a ]]
[[ "$(shasum -a256 "$go_tar" | awk '{print $1}')" == 544932844156d8172f7a28f77f2ac9c15a23046698b6243f633b0a0b00c0749c ]]
root="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-awg-packet-flow.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/lab" "$work/Host" "$work/Provider" "$work/Lib"
ln -s "$source_dir" "$work/awg"
cp "$root"/*.go "$root"/go.mod "$root"/go.sum "$work/lab/"
cp "$root"/PacketTunnel/*.swift "$work/Provider/"
tar -xzf "$go_tar" -C "$work"
export PATH="$work/go/bin:$PATH" GOTOOLCHAIN=local GOWORK=off
cp "$root"/Host/*.swift "$work/Host/"
cat > "$work/AWG.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.developer.networking.networkextension</key><array><string>packet-tunnel-provider</string></array></dict></plist>
PLIST
cat > "$work/project.yml" <<'YAML'
name: APLIsolatedAWG
options:
  deploymentTarget:
    iOS: "15.0"
targets:
  AWGCompileHost:
    type: application
    platform: iOS
    sources: [Host]
    dependencies:
      - target: AWGProvider
        embed: true
    info:
      path: HostInfo.plist
      properties:
        UILaunchScreen: {}
        NSLocalNetworkUsageDescription: "Connect only to the fixed local synthetic AWG peer."
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.proxylauncher.lab.awgcompile
        SWIFT_VERSION: "5.9"
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGN_ENTITLEMENTS: AWG.entitlements
  AWGProvider:
    type: app-extension
    platform: iOS
    sources: [Provider]
    info:
      path: ProviderInfo.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.networkextension.packet-tunnel
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).AWGIsolatedPacketTunnelProvider
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.proxylauncher.lab.awgcompile.PacketTunnel
        SWIFT_VERSION: "5.9"
        APPLICATION_EXTENSION_API_ONLY: YES
        ENABLE_DEBUG_DYLIB: NO
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGN_ENTITLEMENTS: AWG.entitlements
        SWIFT_INCLUDE_PATHS: "$(PROJECT_DIR)/Lib"
        LIBRARY_SEARCH_PATHS: "$(PROJECT_DIR)/Lib"
        OTHER_LDFLAGS: "-lAWG -lresolv -framework Security -framework CoreFoundation -framework NetworkExtension"
schemes:
  AWGCompileHost:
    build:
      targets:
        AWGCompileHost: all
YAML
(cd "$work" && xcodegen generate >/dev/null)
(cd "$work/lab" && go mod verify)
for sdk in iphoneos iphonesimulator; do
  if [[ "$sdk" == iphoneos ]]; then target=arm64-apple-ios15.0; dest='generic/platform=iOS'; else target=arm64-apple-ios15.0-simulator; dest='generic/platform=iOS Simulator'; fi
  sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cc="$(xcrun --sdk "$sdk" --find clang)"
  flags="-target $target -isysroot $sdkpath"
  (cd "$work/lab" && CGO_ENABLED=1 GOOS=ios GOARCH=arm64 CC="$cc" CGO_CFLAGS="$flags" CGO_LDFLAGS="$flags" go build -mod=readonly -trimpath -buildmode=c-archive -o "$work/Lib/libAWG.a" .)
  printf 'module APLAWGBridge { header "libAWG.h" export * }\n' > "$work/Lib/module.modulemap"
  if ! xcodebuild -project "$work/APLIsolatedAWG.xcodeproj" -scheme AWGCompileHost -configuration Debug -sdk "$sdk" -destination "$dest" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO -derivedDataPath "$work/Build-$sdk" build > "$work/build-$sdk.log" 2>&1; then grep -E 'error:|BUILD FAILED' "$work/build-$sdk.log" | tail -30; exit 1; fi
  binary="$work/Build-$sdk/Build/Products/Debug-$sdk/AWGCompileHost.app/PlugIns/AWGProvider.appex/AWGProvider"
  test -f "$binary"
  xcrun nm "$binary" > "$work/symbols"
  for sym in Start StartLAN Push Pull Stop; do grep -Eq " [Tt] _aplAWGBridge${sym}$" "$work/symbols"; done
  if grep -qE ' [Tt] _CGoInvoke$' "$work/symbols"; then echo unexpected-Xray; exit 1; fi
  if [[ "$sdk" == iphoneos && -n "$export_dir" ]]; then
    cp -R "$work/Build-$sdk/Build/Products/Debug-$sdk/AWGCompileHost.app" "$work/unsigned-device.app"
  fi
  echo "AWG_PACKET_FLOW_BUILD_${sdk}_PASS"
done

if [[ -n "$export_dir" ]]; then
  # Copy only after both platform builds verified; no signing or install.
  cp -R "$work/unsigned-device.app" "$export_dir/AWGCompileHost.app"
  (cd "$export_dir" && shasum -a 256 AWGCompileHost.app/AWGCompileHost AWGCompileHost.app/PlugIns/AWGProvider.appex/AWGProvider > AWG-SHA256SUMS)
  echo AWG_UNSIGNED_ARTIFACT_EXPORTED
fi
