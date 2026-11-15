#!/bin/bash
# One Go main/module, one c-archive. Offline compile + link evidence only.
set -euo pipefail
umask 077
[[ $# == 3 && "$(uname -m)" == arm64 ]]
a="$(cd "$1" && pwd)"; awg="$(cd "$2" && pwd)"; out="$3"
[[ ! -e "$out" ]]
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root/Tools/xray_source_pins.json" "$a" "$awg" <<'PY'
import hashlib,json,pathlib,subprocess,sys
p=json.load(open(sys.argv[1]));a=pathlib.Path(sys.argv[2]);awg=pathlib.Path(sys.argv[3]);x=a/'libxray'
def sha(f):
 with f.open('rb') as r:return hashlib.file_digest(r,'sha256').hexdigest()
def git(d,*args):return subprocess.check_output(['git','-C',str(d),*args],text=True).strip()
assert sha(x/'go.mod')==p['go_mod_sha256'] and sha(x/'go.sum')==p['go_sum_sha256']
assert git(x,'rev-parse','HEAD')==p['source_commit'] and not git(x,'status','--porcelain')
assert git(awg,'rev-parse','HEAD')=='b5928efb6ca19f0153958460c3d141f04abc5c2e' and not git(awg,'status','--porcelain')
assert sha(awg/'go.mod')=='9fd0084da2acc4f96225daee85c0f866a0ec1079d5bdc4cf98c50e8a8fa0baf6'
assert sha(awg/'go.sum')=='eab202288b6f879fe1f6b0d9da0c528cfb310d74a7a4d409c7268c2b26b98a0a'
assert (a/p['go_archive']).stat().st_size==p['go_archive_bytes'] and sha(a/p['go_archive'])==p['go_archive_sha256']
PY
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-unified-go.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/src" "$work/evidence"
git -C "$a/libxray" archive HEAD | tar -xf - -C "$work/src"
for f in "$root/Tools/AWGNativeLab/"*.go; do case "$f" in *_test.go) continue;; esac; cp "$f" "$work/src/cgo_bridge/awg_$(basename "$f")"; done
product_flag="${APL_COMPILE_AWG_PRODUCT_BRIDGE:-0}"
[[ "$product_flag" == 0 || "$product_flag" == 1 ]]
if [[ "$product_flag" == 1 ]]; then
    for f in "$root/Tools/AWGProductRuntime/"*.go; do case "$f" in *_test.go) continue;; esac; cp "$f" "$work/src/cgo_bridge/awg_product_$(basename "$f")"; done
fi
python3 - "$work/src/cgo_bridge/awg_main.go" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();assert s.count('func main() {')==1;p.write_text(s.replace('func main() {','func awgSyntheticCLI() {',1))
PY
GO="$a/go/bin/go"; [[ "$($GO version)" == 'go version go1.27.3 darwin/arm64' ]]
export GOTOOLCHAIN=local GOWORK=off GOENV=off GOPATH="$a/gopath" GOMODCACHE="$a/modcache" GOCACHE="$a/gocache" GOPROXY=off GOSUMDB=off GOPRIVATE= GONOSUMDB= GONOPROXY=
cd "$work/src"
"$GO" mod edit -require=github.com/amnezia-vpn/amneziawg-go/v3@v3.1.20260828 -replace="github.com/amnezia-vpn/amneziawg-go/v3=$awg"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
export GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$(xcrun --sdk iphoneos --find clang)" CGO_CFLAGS="-target arm64-apple-ios15.0 -isysroot $sdk" CGO_LDFLAGS="-target arm64-apple-ios15.0 -isysroot $sdk"
"$GO" list -mod=mod -tags=ios -deps -json ./cgo_bridge > "$work/evidence/ios-deps.json"
"$GO" mod verify > "$work/evidence/verify.log"
"$GO" build -mod=readonly -tags=ios -trimpath -ldflags '-s -w -buildid=' -buildmode=c-archive -o "$work/evidence/libAPLUnified.a" ./cgo_bridge
cp go.mod go.sum "$work/evidence/"
cat > "$work/evidence/link_probe.c" <<'C'
#include "libAPLUnified.h"
int main(void) {
    char req[]="{\"apiVersion\":3,\"method\":\"xrayVersion\"}";
    char* value=CGoInvoke(req); if(value) CGoFree(value);
    unsigned char config[]="fixture";
    int result=aplAWGBridgeValidateConfig(config,sizeof(config)-1);
    return result==0 ? 0 : 1;
}
C
E="$work/evidence"
if [[ "$product_flag" == 1 ]]; then
    python3 - "$E/link_probe.c" <<'PYPROBE'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text().replace('    return result==0 ? 0 : 1;', '    uint64_t token=aplAWGProductPrepare(config,sizeof(config)-1,1280,config,sizeof(config)-1,1);\n    if(token){result+=aplAWGProductStart(token);result+=aplAWGProductPush(token,config,sizeof(config)-1);result+=aplAWGProductPull(token,config,sizeof(config)-1);result+=aplAWGProductStop(token);}\n    return result==0 ? 0 : 1;')
p.write_text(s)
PYPROBE
fi
xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -isysroot "$sdk" -I "$E" "$E/link_probe.c" "$E/libAPLUnified.a" -lresolv -framework SystemConfiguration -framework CoreFoundation -framework Security -o "$work/ios-unified-link-probe"
xcrun nm "$work/ios-unified-link-probe" > "$E/link-symbols.txt"
for sym in CGoInvoke CGoFree aplAWGBridgeValidateConfig aplAWGBridgeStartLAN aplAWGBridgePush aplAWGBridgePull aplAWGBridgeStop; do grep -Eq " [Tt] _$sym$" "$E/link-symbols.txt"; done
if [[ "$product_flag" == 1 ]]; then
    for sym in aplAWGProductPrepare aplAWGProductStart aplAWGProductPush aplAWGProductPull aplAWGProductStop; do grep -Eq " [Tt] _$sym$" "$E/link-symbols.txt"; done
fi
xcrun vtool -show-build "$work/ios-unified-link-probe" > "$E/target.txt"
python3 - "$root" "$work" "$product_flag" <<'PY'
import hashlib,json,pathlib,subprocess,sys
root,w=map(pathlib.Path,sys.argv[1:3]);e=w/'evidence'
def sha(f):
 with f.open('rb') as r:return hashlib.file_digest(r,'sha256').hexdigest()
sources={f.name:sha(f) for f in sorted((root/'Tools/AWGNativeLab').glob('*.go')) if not f.name.endswith('_test.go')}
report={'schema':1,'release_authorized':False,'scope':'offline single Go c-archive and iOS arm64 link probe only; never executed','base_commit':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),'xray_commit':'5a0f7d8d1c28b34afb5727b04b26a10f6dbac7e3','awg_commit':'b5928efb6ca19f0153958460c3d141f04abc5c2e','go_version':'1.27.3','original_bridge_sha256':sources,'unified_bridge_sha256':{f.name:sha(f) for f in sorted((w/'src/cgo_bridge').glob('*.go'))},'link_probe_sha256':sha(w/'ios-unified-link-probe'),'files':{f.name:sha(f) for f in sorted(e.iterdir()) if f.is_file()}}
if sys.argv[3]=='1':
 report['product_awg_bridge']=True
 report['product_bridge_sha256']={f.name:sha(f) for f in sorted((root/'Tools/AWGProductRuntime').glob('*.go')) if not f.name.endswith('_test.go')}
(e/'manifest.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print('UNIFIED_IOS_ARCHIVE_LINK_ONLY_PASS',report['files']['libAPLUnified.a'])
PY
# Retain the private archive and receipts, not an executable or app bundle.
[[ ! -e "$out" ]]; mv "$E" "$out"
