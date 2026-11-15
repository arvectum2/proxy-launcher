#!/bin/bash
# Compile actual product provider sources in a separate unsigned target.
# No signing, installation, simulator/device launch, or default project edits.
set -euo pipefail
umask 077
[[ $# == 4 ]] || { echo 'usage: build_product_xray_candidate_unsigned.sh SOURCE_CANDIDATE UPSTREAM_ASSET RUST_FRAMEWORK NEW_OUTPUT_DIR' >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
source="$1"; asset="$2"; rust="$3"; out="$4"
[[ ! -e "$out" ]] || { echo OUTPUT_EXISTS >&2; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-product-xray.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/Lib/Xray/Headers" "$work/Lib/Rust/Headers" "$work/SourceCheck"
python3 "$root/Tools/verify_xray_source_candidate.py" "$source"
python3 "$root/Tools/verify_tun2proxy_lab_artifact.py" "$rust" ios-arm64 --require-connected-udp
cp "$source/libXray.a" "$work/Lib/Xray/"
cp "$source/libXray.h" "$work/Lib/Xray/Headers/"
cp "$work/Lib/Xray/libXray.a" "$work/Lib/Xray/Headers/libXray.h" "$work/SourceCheck/"
python3 "$root/Tools/verify_xray_source_candidate.py" "$work/SourceCheck"
python3 - "$asset" "$work/Lib/Xray/Headers/module.modulemap" <<'PY'
import hashlib,sys,zipfile
from pathlib import Path
with zipfile.ZipFile(sys.argv[1]) as z:
    b=z.read('libxray-apple-cgo/LibXray.xcframework/ios-arm64/Headers/module.modulemap')
assert hashlib.sha256(b).hexdigest()=='2352d2fa3aa2107d06f3e52e6566df9e5bb09d7fd4363cfdc24c5ef3768e7d46'
Path(sys.argv[2]).write_bytes(b)
PY
cp "$rust/ios-arm64/libtun2proxy.a" "$work/Lib/Rust/"
cp "$rust/ios-arm64/Headers/"* "$work/Lib/Rust/Headers/"
[[ $(shasum -a 256 "$work/Lib/Rust/libtun2proxy.a" | cut -d' ' -f1) == e81642cf494e218aeb3314289f235eeff8dff21dc8d72b8bd23ded8b41c0b852 ]] || { echo WRONG_RUST_VARIANT >&2; exit 2; }
runtime_flag="${APL_COMPILE_SYNTHETIC_RUNTIME:-0}"
[[ "$runtime_flag" == 0 || "$runtime_flag" == 1 ]]
mkdir -p "$work/FixtureSupport"
if [[ "$runtime_flag" == 1 ]]; then
    cp "$root/Tools/XrayWireGuardLabConfig.swift" "$work/FixtureSupport/XrayWireGuardLabConfig.swift"
    cp "$root/Tools/NativeTunnelLab/ExactLabTUNDescriptor.swift" "$work/FixtureSupport/ExactLabTUNDescriptor.swift"
fi
cp -R "$root/PacketTunnel" "$root/Shared" "$root/SharedCore" "$work/"
cp "$root/Config/PacketTunnel-Info.plist" "$work/Info.plist"
cat > "$work/project.yml" <<'YAML'
name: APLProductXrayCompileOnly
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
        PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.proxylauncher.lab.productxraycompile.PacketTunnel
        PRODUCT_NAME: PacketTunnelCandidate
        INFOPLIST_FILE: Info.plist
        MARKETING_VERSION: '0.2.0'
        CURRENT_PROJECT_VERSION: '48'
        SWIFT_VERSION: '5.9'
        APPLICATION_EXTENSION_API_ONLY: YES
        ENABLE_DEBUG_DYLIB: NO
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGNING_REQUIRED: NO
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: 'DEBUG APL_NATIVE_PROVIDER_INTEGRATION APL_NATIVE_XRAY_CANDIDATE'
        SWIFT_INCLUDE_PATHS: '$(PROJECT_DIR)/Lib/Xray/Headers $(PROJECT_DIR)/Lib/Rust/Headers'
        LIBRARY_SEARCH_PATHS: '$(PROJECT_DIR)/Lib/Xray $(PROJECT_DIR)/Lib/Rust'
        OTHER_LDFLAGS: '-lXray -ltun2proxy -lresolv -framework NetworkExtension -framework SystemConfiguration -framework Security -framework CoreFoundation'
schemes:
  PacketTunnelCandidate:
    build:
      targets:
        PacketTunnelCandidate: all
YAML
if [[ "$runtime_flag" == 1 ]]; then
    sed -i '' "s/APL_NATIVE_XRAY_CANDIDATE'/APL_NATIVE_XRAY_CANDIDATE APL_NATIVE_SYNTHETIC_RUNTIME'/" "$work/project.yml"
fi
(cd "$work" && xcodegen generate >/dev/null)
if ! xcodebuild -project "$work/APLProductXrayCompileOnly.xcodeproj" -scheme PacketTunnelCandidate -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO COMPILER_INDEX_STORE_ENABLE=NO -derivedDataPath "$work/Build" build > "$work/build.log" 2>&1; then
    grep -E 'error:|BUILD FAILED' "$work/build.log" | tail -25; exit 1
fi
app="$work/Build/Build/Products/Debug-iphoneos/PacketTunnelCandidate.appex"
test -f "$app/PacketTunnelCandidate"
[[ -z "$(find "$app" -name embedded.mobileprovision -o -name '*.dylib')" ]]
xcrun nm "$app/PacketTunnelCandidate" > "$work/symbols.txt"
for name in CGoInvoke CGoFree tun2proxy_run_with_cli_args; do grep -E " [Tt] _${name}$" "$work/symbols.txt"; done
grep 'NativeXrayRuntimeDriver' "$work/symbols.txt" | head -4 || true
grep -q 'NativeXrayRuntimeDriver' "$work/symbols.txt"
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
fixture_origins={'XrayWireGuardLabConfig.swift': 'Tools/XrayWireGuardLabConfig.swift', 'ExactLabTUNDescriptor.swift': 'Tools/NativeTunnelLab/ExactLabTUNDescriptor.swift'}
for f in sorted((work/'FixtureSupport').glob('*.swift')):
    sources[str(f.relative_to(work))]=sha(f);assert sha(f)==sha(root/fixture_origins[f.name])
report={'schema':1,'synthetic_runtime_compiled':bool(list((work/'FixtureSupport').glob('*.swift'))),'scope':'actual product extension sources; unsigned compile/link only; no install/runtime authorization','release_authorized':False,'base_commit':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),'sources':sources,'binary_sha256':sha(binary),'inputs':{str(p.relative_to(work)):sha(p) for p in sorted((work/'Lib').rglob('*')) if p.is_file()},'build_log_sha256':sha(out/'build.log'),'symbol_table_sha256':sha(out/'symbols.txt')}
(out/'manifest.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print('COMPILE_LINK_ONLY_PASS',report['binary_sha256'],len(sources),'sources')
PY
