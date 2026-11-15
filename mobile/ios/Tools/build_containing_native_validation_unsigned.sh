#!/bin/bash
# Build the actual containing iOS app and its ordinary provider with both
# reviewed engines linked. Native starts still fail closed. Never install/sign.
set -euo pipefail
umask 077
[[ $# == 5 ]] || { echo 'usage: build_containing_native_validation_unsigned.sh GO_RECEIPT CLEAN_RUST_XCFRAMEWORK NO_TPROXY_RECEIPT PACKAGE_CACHE NEW_EVIDENCE_DIR' >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
go="$1"; rust="$2"; research="$3"; cache="$4"; out="$5"
[[ ! -e "$out" && -d "$cache/checkouts" ]] || exit 2
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-native-containing.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
# Read only the tracked product source from one immutable commit.
repo="$(git -C "$root" rev-parse --show-toplevel)"
commit="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" archive "$commit" mobile/ios | tar -xf - -C "$work"
p="$work/mobile/ios"
mkdir -p "$p/Lib/Unified/Headers" "$p/Frameworks"
product_flag="${APL_COMPILE_AWG_PRODUCT_BRIDGE:-0}"
[[ "$product_flag" == 0 || "$product_flag" == 1 ]]
runtime_flag="${APL_COMPILE_NATIVE_RUNTIME_REVIEW:-0}"
[[ "$runtime_flag" == 0 || ( "$runtime_flag" == 1 && "$product_flag" == 1 ) ]]
python3 - "$go" "$p/Lib/Unified" "$p" "$product_flag" <<'PY'
import hashlib,json,pathlib,shutil,sys
g,d,p=map(pathlib.Path,sys.argv[1:4]);product=sys.argv[4]=="1"
def sha(p):
    assert p.is_file() and not p.is_symlink()
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
assert sha(g/'manifest.json')==('2a318308d5bad67e1f00f8cd0027844537eea4b32ea33f574a56a9609811425a' if product else '57b279f366b47fd27a46b201088a997fb03f68205f5189dc2931ae43f00011e6')
m=json.loads((g/'manifest.json').read_text());assert m['release_authorized'] is False
assert m.get('product_awg_bridge',False)==product
if product:
    assert m['product_bridge_sha256']=={f.name:sha(f) for f in sorted((p/'Tools/AWGProductRuntime').glob('*.go')) if not f.name.endswith('_test.go')}
    assert m['original_bridge_sha256']=={f.name:sha(f) for f in sorted((p/'Tools/AWGNativeLab').glob('*.go')) if not f.name.endswith('_test.go')}
for n,h in m['files'].items():assert pathlib.Path(n).name==n and sha(g/n)==h
for n,t in [('libAPLUnified.a',d/'libAPLUnified.a'),('libAPLUnified.h',d/'Headers/libAPLUnified.h')]:
    shutil.copyfile(g/n,t);assert sha(t)==m['files'][n]
(d/'Headers/module.modulemap').write_text('module APLUnifiedGo { header "libAPLUnified.h" export * }\n')
PY
python3 "$root/Tools/verify_tun2proxy_lab_artifact.py" "$rust" ios-arm64 --require-connected-udp
cp -R "$rust" "$p/Frameworks/tun2proxy.xcframework"
r="$p/Frameworks/tun2proxy.xcframework/ios-arm64"
[[ "$(shasum -a 256 "$r/libtun2proxy.a" | cut -d' ' -f1)" == e81642cf494e218aeb3314289f235eeff8dff21dc8d72b8bd23ded8b41c0b852 ]]
python3 "$root/Tools/verify_ios_no_tproxy_receipt.py" "$research" "$r"
python3 - "$p/project.yml" "$product_flag" "$runtime_flag" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text()
for target,flags in [
 ('ArvectumProxyLauncher','DEBUG APL_NATIVE_PROVIDER_INTEGRATION APL_NATIVE_PERSISTENT_LIBRARY APL_NATIVE_IP_ROUTE_REVIEW APL_NATIVE_DOMAIN_POLICY_REVIEW'),
 ('PacketTunnel','DEBUG APL_NATIVE_PROVIDER_INTEGRATION APL_NATIVE_XRAY_CANDIDATE APL_NATIVE_AWG_CANDIDATE APL_NATIVE_UNIFIED_GO_CANDIDATE')]:
    start=s.index('  '+target+':\n',s.index('targets:\n'));i=s.index('      base:\n',start)+len('      base:\n')
    extra='        ENABLE_DEBUG_DYLIB: NO\n'
    # Only the Debug configuration exists in this candidate build.
    if target=='PacketTunnel' and sys.argv[2]=='1':flags+=' APL_NATIVE_AWG_PRODUCT_BRIDGE'
    if sys.argv[3]=='1':flags+=' APL_NATIVE_PRODUCT_RUNTIME_REVIEW'
    extra+='        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "'+flags+'"\n'
    if target=='PacketTunnel':
        extra+='        SWIFT_INCLUDE_PATHS: "$(PROJECT_DIR)/Lib/Unified/Headers"\n        LIBRARY_SEARCH_PATHS: "$(PROJECT_DIR)/Lib/Unified"\n        OTHER_LDFLAGS: "$(inherited) -lAPLUnified -lresolv"\n'
    s=s[:i]+extra+s[i:]
assert 'APL_NATIVE_SYNTHETIC_RUNTIME' not in s
p.write_text(s)
PY
(cd "$p" && xcodegen generate >/dev/null)
# Package versions remain the exact tracked lock. Do not update resolutions.
lock='ArvectumProxyLauncherIOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
git -C "$repo" show "$commit:mobile/ios/$lock" > "$p/$lock"
if ! xcodebuild -project "$p/ArvectumProxyLauncherIOS.xcodeproj" -scheme ArvectumProxyLauncher -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath "$cache" -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO COMPILER_INDEX_STORE_ENABLE=NO LD_GENERATE_MAP_FILE=YES -derivedDataPath "$work/Build" build > "$work/build.log" 2>&1; then
    grep -E 'error:|BUILD FAILED' "$work/build.log" | tail -25
    exit 1
fi
products="$work/Build/Build/Products/Debug-iphoneos"
app="$products/Arvectum Proxy Launcher.app"
extension="$app/PlugIns/Arvectum Packet Tunnel.appex/Arvectum Packet Tunnel"
host="$app/Arvectum Proxy Launcher"
[[ -f "$extension" && -f "$host" ]]
xcrun nm "$extension" > "$work/provider-symbols.txt"
for symbol in CGoInvoke CGoFree aplAWGBridgeValidateConfig tun2proxy_run_with_cli_args tun2proxy_stop; do
    grep -E " [Tt] _${symbol}$" "$work/provider-symbols.txt"
done
! grep -q 'NativeSyntheticProviderOwner\|tproxy_config' "$work/provider-symbols.txt"
grep -q NativeXrayRuntimeDriver "$work/provider-symbols.txt"
grep -q NativeAWGValidationDriver "$work/provider-symbols.txt"
if [[ "$product_flag" == 1 ]]; then
    for symbol in aplAWGProductPrepare aplAWGProductStart aplAWGProductPush aplAWGProductPull aplAWGProductStop; do grep -Eq " [Tt] _${symbol}$" "$work/provider-symbols.txt"; done
    grep -q NativeAWGProductFlow "$work/provider-symbols.txt"
fi
if [[ "$runtime_flag" == 1 ]]; then
    grep -q NativeProductRuntimeOwner "$work/provider-symbols.txt"
    grep -q NativeExactTunnelDescriptor "$work/provider-symbols.txt"
fi
mkdir -m 700 "$out"
cp "$work/build.log" "$work/provider-symbols.txt" "$p/project.yml" "$out/"
python3 - "$p" "$work/Build" "$host" "$extension" "$out" "$commit" "$root/Tools" "$product_flag" "$runtime_flag" <<'PY'
import hashlib,json,pathlib,plistlib,re,sys,shutil
p,build,host,ext,out=map(pathlib.Path,sys.argv[1:6]);commit=sys.argv[6];sys.path.insert(0,sys.argv[7])
from audit_unsigned_release_linkage import link_objects
def sha(f):
    with f.open('rb') as r:return hashlib.file_digest(r,'sha256').hexdigest()
h=plistlib.loads((host.parent/'Info.plist').read_bytes());e=plistlib.loads((ext.parent/'Info.plist').read_bytes())
assert h['CFBundleIdentifier']=='ru.arvectum.proxylauncher.ios' and e['CFBundleIdentifier']==h['CFBundleIdentifier']+'.PacketTunnel'
assert not list(host.parent.rglob('embedded.mobileprovision')) and not list(host.parent.rglob('_CodeSignature'))
original=ext.parent.parent.parent.parent/ext.parent.name/ext.name
assert original.is_file() and sha(original)==sha(ext)
maps=list((build/'Build/Intermediates.noindex').rglob('Arvectum Packet Tunnel-LinkMap-normal-arm64.txt'))
assert len(maps)==1,maps
rows={}
for obj in link_objects(maps[0],original):
    m=re.fullmatch(r'(.+)\(([^()]+)\)',obj)
    if m and pathlib.Path(m[1]).name in ('libAPLUnified.a','libtun2proxy.a'):
        rows.setdefault(pathlib.Path(m[1]).name,[]).append(m[2])
assert set(rows)=={'libAPLUnified.a','libtun2proxy.a'} and all(rows.values())
shutil.copyfile(maps[0],out/'provider-link-map.txt')
sources={str(f.relative_to(p)):sha(f) for folder in ('App','PacketTunnel','Shared','SharedCore','Config','Resources') for f in sorted((p/folder).rglob('*')) if f.is_file()}
report={'schema':1,'source_commit':commit,'scope':('actual product containing app + separate native runtime-review provider, unsigned; no install or runtime performed' if sys.argv[9]=='1' else 'actual product app + ordinary provider, validation-only, unsigned; no install or runtime'),'runtime_authorized':False,'release_authorized':False,'synthetic_runtime':False,'product_awg_bridge':sys.argv[8]=='1','product_runtime_review':sys.argv[9]=='1','host_sha256':sha(host),'provider_sha256':sha(ext),'host_info_sha256':sha(host.parent/'Info.plist'),'provider_info_sha256':sha(ext.parent/'Info.plist'),'go_archive_sha256':sha(p/'Lib/Unified/libAPLUnified.a'),'rust_archive_sha256':sha(p/'Frameworks/tun2proxy.xcframework/ios-arm64/libtun2proxy.a'),'sources':sources,'linked_archive_objects':{k:sorted(v) for k,v in rows.items()},'evidence':{f.name:sha(f) for f in out.iterdir() if f.is_file()}}
(out/'manifest.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print('CONTAINING_NATIVE_VALIDATION_LINK_PASS',report['provider_sha256'],{k:len(v) for k,v in rows.items()})
PY
