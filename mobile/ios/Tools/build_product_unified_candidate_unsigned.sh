#!/bin/bash
# Compile actual product provider sources in a separate unsigned target.
# No signing, installation, simulator/device launch, or default project edits.
set -euo pipefail
umask 077
[[ $# == 3 ]] || { echo 'usage: build_product_unified_candidate_unsigned.sh UNIFIED_RECEIPT RUST_FRAMEWORK NEW_OUTPUT_DIR' >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
source="$1"; rust="$2"; out="$3"
[[ ! -e "$out" ]] || { echo OUTPUT_EXISTS >&2; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-product-unified.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/Lib/Unified/Headers" "$work/Lib/Rust/Headers"
python3 - "$source" "$work/Lib/Unified" <<'PYVERIFY'
import hashlib,json,pathlib,shutil,sys
p,d=map(pathlib.Path,sys.argv[1:]);m=p/'manifest.json'
def sha(f):
 with f.open('rb') as r:return hashlib.file_digest(r,'sha256').hexdigest()
if sha(m)!='57b279f366b47fd27a46b201088a997fb03f68205f5189dc2931ae43f00011e6':raise SystemExit('unreviewed unified receipt')
r=json.loads(m.read_text());assert r['release_authorized'] is False
for name,digest in r['files'].items():
 assert pathlib.Path(name).name==name and sha(p/name)==digest
for name,target in [('libAPLUnified.a',d/'libAPLUnified.a'),('libAPLUnified.h',d/'Headers/libAPLUnified.h')]:
 shutil.copyfile(p/name,target);assert sha(target)==r['files'][name]
(d/'Headers/module.modulemap').write_text('module APLUnifiedGo { header "libAPLUnified.h" export * }\n')
PYVERIFY
python3 "$root/Tools/verify_tun2proxy_lab_artifact.py" "$rust" ios-arm64 --require-connected-udp
cp "$rust/ios-arm64/libtun2proxy.a" "$work/Lib/Rust/"
cp "$rust/ios-arm64/Headers/"* "$work/Lib/Rust/Headers/"
[[ $(shasum -a 256 "$work/Lib/Rust/libtun2proxy.a" | cut -d' ' -f1) == e81642cf494e218aeb3314289f235eeff8dff21dc8d72b8bd23ded8b41c0b852 ]] || { echo WRONG_RUST_VARIANT >&2; exit 2; }
runtime_flag="${APL_COMPILE_SYNTHETIC_RUNTIME:-0}"
[[ "$runtime_flag" == 0 || "$runtime_flag" == 1 ]]
mkdir -p "$work/FixtureSupport"
if [[ "$runtime_flag" == 1 ]]; then
    cp "$root/Tools/XrayWireGuardLabConfig.swift" "$work/FixtureSupport/XrayWireGuardLabConfig.swift"
    cp "$root/Tools/NativeTunnelLab/ExactLabTUNDescriptor.swift" "$work/FixtureSupport/ExactLabTUNDescriptor.swift"
    cp "$root/Tools/AWGNativeLab/PacketTunnel/AWGPacketFlowPump.swift" "$work/FixtureSupport/AWGPacketFlowPump.swift"
fi
cp -R "$root/PacketTunnel" "$root/Shared" "$root/SharedCore" "$work/"
cp "$root/Config/PacketTunnel-Info.plist" "$work/Info.plist"
cat > "$work/project.yml" <<'YAML'
name: APLProductUnifiedCompileOnly
options:
  deploymentTarget:
    iOS: '15.0'
targets:
  PacketTunnelCandidate:
    type: app-extension
    platform: iOS
    sources:
      - PacketTunnel
      - Shared
      - SharedCore
      - FixtureSupport
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.proxylauncher.lab.productunifiedcompile.PacketTunnel
        PRODUCT_NAME: PacketTunnelCandidate
        INFOPLIST_FILE: Info.plist
        MARKETING_VERSION: '0.2.0'
        CURRENT_PROJECT_VERSION: '48'
        SWIFT_VERSION: '5.9'
        APPLICATION_EXTENSION_API_ONLY: YES
        ENABLE_DEBUG_DYLIB: NO
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGNING_REQUIRED: NO
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: 'DEBUG APL_NATIVE_PROVIDER_INTEGRATION APL_NATIVE_XRAY_CANDIDATE APL_NATIVE_AWG_CANDIDATE APL_NATIVE_UNIFIED_GO_CANDIDATE'
        SWIFT_INCLUDE_PATHS: '$(PROJECT_DIR)/Lib/Unified/Headers $(PROJECT_DIR)/Lib/Rust/Headers'
        LIBRARY_SEARCH_PATHS: '$(PROJECT_DIR)/Lib/Unified $(PROJECT_DIR)/Lib/Rust'
        OTHER_LDFLAGS: '-lAPLUnified -ltun2proxy -lresolv -framework NetworkExtension -framework SystemConfiguration -framework Security -framework CoreFoundation'
schemes:
  PacketTunnelCandidate:
    build:
      targets:
        PacketTunnelCandidate: all
YAML
if [[ "$runtime_flag" == 1 ]]; then
    sed -i '' "s/APL_NATIVE_XRAY_CANDIDATE APL_NATIVE_AWG_CANDIDATE APL_NATIVE_UNIFIED_GO_CANDIDATE'/APL_NATIVE_XRAY_CANDIDATE APL_NATIVE_AWG_CANDIDATE APL_NATIVE_UNIFIED_GO_CANDIDATE APL_NATIVE_SYNTHETIC_RUNTIME'/" "$work/project.yml"
fi
(cd "$work" && xcodegen generate >/dev/null)
if ! xcodebuild -project "$work/APLProductUnifiedCompileOnly.xcodeproj" -scheme PacketTunnelCandidate -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO COMPILER_INDEX_STORE_ENABLE=NO -derivedDataPath "$work/Build" build > "$work/build.log" 2>&1; then
    grep -E 'error:|BUILD FAILED' "$work/build.log" | tail -25; exit 1
fi
app="$work/Build/Build/Products/Debug-iphoneos/PacketTunnelCandidate.appex"
test -f "$app/PacketTunnelCandidate"
[[ -z "$(find "$app" -name embedded.mobileprovision -o -name '*.dylib')" ]]
xcrun nm "$app/PacketTunnelCandidate" > "$work/symbols.txt"
for name in CGoInvoke CGoFree aplAWGBridgeValidateConfig aplAWGBridgeStartLAN aplAWGBridgePush aplAWGBridgePull aplAWGBridgeStop tun2proxy_run_with_cli_args; do grep -E " [Tt] _${name}$" "$work/symbols.txt"; done
grep 'NativeXrayRuntimeDriver' "$work/symbols.txt" | head -4 || true
grep -q 'NativeXrayRuntimeDriver' "$work/symbols.txt"
grep -q 'NativeAWGValidationDriver' "$work/symbols.txt" || [[ "$runtime_flag" == 1 ]]
if [[ "$runtime_flag" == 1 ]]; then
    grep -q 'NativeAWGPacketSession' "$work/symbols.txt"
    grep -q 'NativeSyntheticProviderOwner' "$work/symbols.txt"
fi
# Receipt only; no runnable bundle is exported from this compile lane.
mkdir -m 700 "$out"
cp "$work/build.log" "$out/build.log"
cp "$work/symbols.txt" "$out/symbols.txt"
python3 - "$root" "$work" "$app/PacketTunnelCandidate" "$out" <<'PY'
import hashlib,json,pathlib,sys,subprocess
root,work,binary,out=map(pathlib.Path,sys.argv[1:])
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
sources={}
for folder in ('PacketTunnel','Shared','SharedCore'):
    for f in sorted((work/folder).rglob('*.swift')):
        rel=str(f.relative_to(work));sources[rel]=sha(f)
        assert sources[rel]==sha(root/rel)
fixture_origins={'XrayWireGuardLabConfig.swift': 'Tools/XrayWireGuardLabConfig.swift', 'ExactLabTUNDescriptor.swift': 'Tools/NativeTunnelLab/ExactLabTUNDescriptor.swift','AWGPacketFlowPump.swift':'Tools/AWGNativeLab/PacketTunnel/AWGPacketFlowPump.swift'}
for f in sorted((work/'FixtureSupport').glob('*.swift')):
    sources[str(f.relative_to(work))]=sha(f);assert sha(f)==sha(root/fixture_origins[f.name])
report={'schema':1,'unified_go_receipt_sha256':'57b279f366b47fd27a46b201088a997fb03f68205f5189dc2931ae43f00011e6','synthetic_runtime_compiled':bool(list((work/'FixtureSupport').glob('*.swift'))),'scope':'actual product extension sources; unsigned compile/link only; no install/runtime authorization','release_authorized':False,'base_commit':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),'sources':sources,'binary_sha256':sha(binary),'inputs':{str(p.relative_to(work)):sha(p) for p in sorted((work/'Lib').rglob('*')) if p.is_file()},'build_log_sha256':sha(out/'build.log'),'symbol_table_sha256':sha(out/'symbols.txt')}
(out/'manifest.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print('UNIFIED_PRODUCT_COMPILE_LINK_ONLY_PASS',report['binary_sha256'],len(sources),'sources')
PY
