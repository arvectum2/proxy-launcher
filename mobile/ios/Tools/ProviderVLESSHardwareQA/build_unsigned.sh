#!/bin/bash
set -euo pipefail
umask 077
[[ ( $# == 2 || $# == 3 || $# == 4 ) && ! -e "$2" ]]
[[ $# != 4 || "$4" == full-route || "$4" == product-runner ]]
source="$1";out="$2";rust="${3:-}";mode="${4:-}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$source" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1])
def sha(f):
    with f.open('rb') as s:return hashlib.file_digest(s,'sha256').hexdigest()
assert sha(p/'manifest.json')=='1c8f00a729dac97e7670b718d6208d8e67946ea9b2260a9f68eed4a9fa5e0c54'
m=json.loads((p/'manifest.json').read_text())
assert not m['release_authorized'] and not m['runtime_authorized']
for n,h in m['files'].items():
    f=p/n
    assert f.resolve().is_relative_to(p.resolve()) and sha(f)==h
assert sha(p/'libAPLUnified.a')==m['archive_sha256']=='45716d42d434ae6d6576d9a32f47a4ea63d4943f106cb3bb7e6af57c725ea7af'
assert sha(p/'libAPLUnified.h')=='6307e010d9be17c82e7875acf0b86c962b8b8b32bd45994f523b39a51ba33505'
PY
mkdir -m 700 "$out";mkdir -p "$out/Host" "$out/Sources" "$out/Lib/Headers"
cp "$source/libAPLUnified.a" "$out/Lib/"
cp "$source/libAPLUnified.h" "$out/Lib/Headers/"
printf 'module APLUnifiedGo { header "libAPLUnified.h" export * }\n' > "$out/Lib/Headers/module.modulemap"
cp "$root/Tools/ProviderVLESSHardwareQA/Provider.swift" "$root/Tools/NativeTunnelLab/NativeLabRuntime.swift" "$out/Sources/"
for name in ProxyModel ManagedProfileContract VLESSRealityShareLink XrayVLESSRuntimeConfig;do cp "$root/SharedCore/$name.swift" "$out/Sources/";done
cp "$root/Tools/NativeTunnelLab/Host/NativeLabHost.swift" "$out/Host/"
for name in VLESSRealityShareLink ManagedProfileContract ProxyModel WGQuickConfigurationPreview TransportBackendContract TransportBackendAdapter TransportNativeControl OwnedNativeControlSlot;do cp "$root/SharedCore/$name.swift" "$out/Host/";done
cp "$root/Tools/XrayWireGuardLabConfig.swift" "$root/Tools/NETunnelNativeControlEndpoint.swift" "$root/Tools/NativeControlLabHost.swift" "$out/Host/"
cat > "$out/project.yml" <<'YAML'
name: APLIsolatedProviderDirectQA
options:
  deploymentTarget:
    iOS: "15.0"
targets:
  NativeLabHost:
    type: application
    platform: iOS
    sources: [Host]
    dependencies:
      - target: NativeLab
        embed: true
    info:
      path: HostInfo.plist
      properties:
        CFBundleDisplayName: "APL NativeLab"
        UILaunchScreen: {}
        NSLocalNetworkUsageDescription: "Contact only the owner's synthetic private QA peer."
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.proxylauncher.lab.nativeqa
        MARKETING_VERSION: "0.2.0"
        CURRENT_PROJECT_VERSION: "48"
        SWIFT_VERSION: "5.9"
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: APL_PROVIDER_DIRECT_QA
        ENABLE_DEBUG_DYLIB: NO
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGNING_REQUIRED: NO
  NativeLab:
    type: app-extension
    platform: iOS
    sources: [Sources]
    info:
      path: Info.plist
      properties:
        NSLocalNetworkUsageDescription: "Contact only the owner's synthetic private QA peer."
        NSExtension:
          NSExtensionPointIdentifier: com.apple.networkextension.packet-tunnel
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).NativeLabPacketTunnelProvider
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.proxylauncher.lab.nativeqa.PacketTunnel
        MARKETING_VERSION: "0.2.0"
        CURRENT_PROJECT_VERSION: "48"
        SWIFT_VERSION: "5.9"
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: APL_DIRECT_PRODUCT_GO_QA
        APPLICATION_EXTENSION_API_ONLY: YES
        ENABLE_DEBUG_DYLIB: NO
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGNING_REQUIRED: NO
        SWIFT_INCLUDE_PATHS: "$(PROJECT_DIR)/Lib/Headers"
        LIBRARY_SEARCH_PATHS: "$(PROJECT_DIR)/Lib"
        OTHER_LDFLAGS: "-lAPLUnified -lresolv -framework NetworkExtension -framework SystemConfiguration -framework Security -framework CoreFoundation"
schemes:
  NativeLabHost:
    build:
      targets:
        NativeLabHost: all
YAML
if [[ -n "$rust" ]];then
  python3 - "$rust" <<'RUST'
from pathlib import Path
import hashlib,sys
p=Path(sys.argv[1])/'libtun2proxy.a'
with p.open('rb') as f:
    assert hashlib.file_digest(f,'sha256').hexdigest()=='6aea76be103f0266c54d10e049f6b9a231cc8ccaf25c59c89003bafe61b2ae16'
RUST
  cp "$rust/libtun2proxy.a" "$out/Lib/"
  cp "$rust/Headers/tun2proxy.h" "$out/Lib/Headers/"
  printf 'module tun2proxy { header "tun2proxy.h" export * }\n' >> "$out/Lib/Headers/module.modulemap"
  for n in XraySocksHandoffContract TunnelEngineHandoff TunnelEngineExitGate;do cp "$root/SharedCore/$n.swift" "$out/Sources/";done
  cp "$root/Tools/ProviderVLESSHardwareQA/ScopedTCPWitness.swift" "$root/Tools/ProviderVLESSHardwareQA/FixedWitnessKind.swift" "$out/Host/"
  cp "$root/Tools/NativeTunnelLab/ExactLabTUNDescriptor.swift" "$root/Tools/ProviderVLESSHardwareQA/ScopedTUNMetrics.swift" "$out/Sources/"
  python3 - "$out/project.yml" <<'YAML_EDIT'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text().replace('CONDITIONS: APL_PROVIDER_DIRECT_QA','CONDITIONS: "APL_PROVIDER_DIRECT_QA APL_PROVIDER_SCOPED_TUN_QA"').replace('CONDITIONS: APL_DIRECT_PRODUCT_GO_QA','CONDITIONS: "APL_DIRECT_PRODUCT_GO_QA APL_PROVIDER_SCOPED_TUN_QA"').replace('-lAPLUnified -lresolv','-lAPLUnified -ltun2proxy -lresolv')
p.write_text(s)
YAML_EDIT
fi
if [[ "$mode" == full-route || "$mode" == product-runner ]];then
  [[ -n "$rust" ]]
  cp "$root/Tools/ProviderVLESSHardwareQA/FullRouteGuard.swift" "$root/Tools/ProviderVLESSHardwareQA/FixedWitnessKind.swift" "$out/Sources/"
  cp "$root/Tools/ProviderVLESSHardwareQA/FixedUDPWitness.swift" "$root/Tools/ProviderVLESSHardwareQA/FixedDNSWire.swift" "$out/Host/"
  cp "$root/PacketTunnel/NativeExactTunnelDescriptor.swift" "$out/Sources/"
  python3 - "$out/project.yml" <<'FULL_MODE'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text().replace('APL_PROVIDER_SCOPED_TUN_QA"','APL_PROVIDER_SCOPED_TUN_QA APL_PROVIDER_FULL_ROUTE_QA"')
s=s.replace('APL_DIRECT_PRODUCT_GO_QA APL_PROVIDER_SCOPED_TUN_QA APL_PROVIDER_FULL_ROUTE_QA"','APL_DIRECT_PRODUCT_GO_QA APL_PROVIDER_SCOPED_TUN_QA APL_PROVIDER_FULL_ROUTE_QA APL_NATIVE_PROVIDER_INTEGRATION APL_NATIVE_PRODUCT_RUNTIME_REVIEW DEBUG"')
p.write_text(s)
FULL_MODE
fi
if [[ "$mode" == product-runner ]];then
  rm "$out/Sources/Provider.swift"
  cp "$root/SharedCore/"*.swift "$out/Sources/"
  cp "$root/PacketTunnel/NativeXrayPacketSession.swift" "$root/PacketTunnel/NativeXrayRuntimeDriver.swift" "$root/Shared/NativeTunnelNetworkSettings.swift" "$root/Tools/ProviderVLESSHardwareQA/ProductRunnerProvider.swift" "$out/Sources/"
  python3 - "$out/project.yml" <<'PRODUCT_RUNNER_MODE'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
old='APL_DIRECT_PRODUCT_GO_QA APL_PROVIDER_SCOPED_TUN_QA APL_PROVIDER_FULL_ROUTE_QA APL_NATIVE_PROVIDER_INTEGRATION APL_NATIVE_PRODUCT_RUNTIME_REVIEW DEBUG'
new='APL_DIRECT_PRODUCT_GO_QA APL_PROVIDER_SCOPED_TUN_QA APL_PROVIDER_FULL_ROUTE_QA APL_NATIVE_PROVIDER_INTEGRATION APL_NATIVE_PRODUCT_RUNTIME APL_NATIVE_EXACT_DNS APL_NATIVE_XRAY_CANDIDATE APL_NATIVE_UNIFIED_GO_CANDIDATE APL_VLESS_PHYSICAL_QA APL_ISOLATED_PRODUCT_RUNNER_QA DEBUG'
assert s.count(old)==1
s=s.replace(old,new)
p.write_text(s)
PRODUCT_RUNNER_MODE
fi
(cd "$out" && xcodegen generate >/dev/null)
if ! xcodebuild -project "$out/APLIsolatedProviderDirectQA.xcodeproj" -scheme NativeLabHost -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO COMPILER_INDEX_STORE_ENABLE=NO -derivedDataPath "$out/Build" build > "$out/build.log" 2>&1;then grep -E 'error:|BUILD FAILED' "$out/build.log" | tail -25;exit 1;fi
app="$out/Build/Build/Products/Debug-iphoneos/NativeLabHost.app"
test -f "$app/NativeLabHost";test -f "$app/PlugIns/NativeLab.appex/NativeLab"
xcrun nm "$app/PlugIns/NativeLab.appex/NativeLab" > "$out/symbols.txt"
grep -qE ' [Tt] _CGoInvoke$' "$out/symbols.txt"
if [[ -n "$rust" ]];then
  grep -qE ' [Tt] _tun2proxy_run_with_cli_args$' "$out/symbols.txt"
else
  ! grep -qE ' [Tt] _tun2proxy_run_with_cli_args$' "$out/symbols.txt"
fi
shasum -a 256 "$app/NativeLabHost" "$app/PlugIns/NativeLab.appex/NativeLab" > "$out/sha256.txt"
echo PROVIDER_DIRECT_QA_UNSIGNED_PASS
