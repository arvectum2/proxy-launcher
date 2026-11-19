#!/bin/bash
# Product-only C ABI compile/link gate. No app activation or signing.
set -euo pipefail
umask 077
[[ $# == 4 && "$(uname -m)" == arm64 ]]
a="$(cd "$1" && pwd)"; awg="$(cd "$2" && pwd)"; prior="$(cd "$3" && pwd)"; out="$4"
[[ ! -e "$out" ]]
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(git -C "$a/libxray" rev-parse HEAD)" == 5a0f7d8d1c28b34afb5727b04b26a10f6dbac7e3 && -z "$(git -C "$a/libxray" status --porcelain)" ]]
[[ "$(git -C "$awg" rev-parse HEAD)" == b5928efb6ca19f0153958460c3d141f04abc5c2e && -z "$(git -C "$awg" status --porcelain)" ]]
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-product-only-go.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/src" "$work/evidence"
git -C "$a/libxray" archive HEAD | tar -xf - -C "$work/src"
E="$work/evidence"
python3 "$root/Tools/prepare_native_release_bridge.py" "$prior/manifest.json" "$work/src/cgo_bridge" > "$E/source-hashes.json"
GO="$a/go/bin/go"; [[ "$($GO version)" == 'go version go1.27.3 darwin/arm64' ]]
export GOTOOLCHAIN=local GOWORK=off GOENV=off GOPATH="$a/gopath" GOMODCACHE="$a/modcache" GOCACHE="$a/gocache" GOPROXY=off GOSUMDB=off GOPRIVATE= GONOSUMDB= GONOPROXY=
cd "$work/src"
"$GO" mod edit -require=github.com/amnezia-vpn/amneziawg-go/v3@v3.1.20260828 -replace="github.com/amnezia-vpn/amneziawg-go/v3=$awg"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
export GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$(xcrun --sdk iphoneos --find clang)" CGO_CFLAGS="-target arm64-apple-ios15.0 -isysroot $sdk" CGO_LDFLAGS="-target arm64-apple-ios15.0 -isysroot $sdk"
"$GO" list -mod=mod -tags=ios -deps -json ./cgo_bridge > "$E/ios-deps.json"
cmp go.mod "$prior/go.mod"; cmp go.sum "$prior/go.sum"
"$GO" mod verify > "$E/verify.log"
"$GO" build -mod=readonly -tags=ios -trimpath -ldflags '-s -w -buildid=' -buildmode=c-archive -o "$E/libAPLUnified.a" ./cgo_bridge
cp go.mod go.sum "$E/"
mkdir "$E/bridge-source"; cp cgo_bridge/*.go "$E/bridge-source/"
cat > "$E/link_probe.c" <<'C'
#include "libAPLUnified.h"
int main(void) {
    char req[]="{\"apiVersion\":3,\"method\":\"xrayVersion\"}";
    char *value=CGoInvoke(req); if(value) CGoFree(value);
    unsigned char b[]="fixture";
    uint64_t t=aplAWGProductPrepare(b,sizeof(b)-1,1280,b,sizeof(b)-1,1);
    if(t){aplAWGProductStart(t);aplAWGProductPush(t,b,sizeof(b)-1);aplAWGProductPull(t,b,sizeof(b)-1);aplAWGProductStop(t);}
    return 0;
}
C
xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -isysroot "$sdk" -I "$E" "$E/link_probe.c" "$E/libAPLUnified.a" -lresolv -framework SystemConfiguration -framework CoreFoundation -framework Security -o "$work/probe"
xcrun nm "$work/probe" > "$E/link-symbols.txt"
PYTHONPATH="$root/Tools" python3 - "$E" "$prior" <<'PY'
import json,pathlib,re,sys
from audit_unified_go_notices import graph
from stage_exact_native_review import identity
from stage_unified_source_review import sha
from prepare_native_release_bridge import ALLOWED_EXPORTS,GO_PIN,require
e,p=map(pathlib.Path,sys.argv[1:])
old,new=graph(p/'ios-deps.json'),graph(e/'ios-deps.json')
require(set(new)<=set(old) and all(identity(old[k])==identity(new[k]) for k in new),'dependency drift')
symbols=set(re.findall(r' [Tt] _((?:aplAWG|CGo)\w+)$',(e/'link-symbols.txt').read_text(),re.M))
require(symbols==ALLOWED_EXPORTS,'unexpected linked bridge symbols')
header=set(re.findall(r'extern\s+[^;]+?\b((?:aplAWG|CGo)\w+)\(', (e/'libAPLUnified.h').read_text()))
require(header==ALLOWED_EXPORTS,'unexpected bridge header')
sources=json.loads((e/'source-hashes.json').read_text())
require(sources=={f.name:sha(f) for f in sorted((e/'bridge-source').glob('*.go'))},'bridge source hashes')
m={'schema':1,'release_authorized':False,'runtime_authorized':False,'scope':'product-only ABI iOS arm64 link probe, not executed','prior_go_receipt_sha256':GO_PIN,'go_package_count':len(new),'removed_packages':sorted(set(old)-set(new)),'exports':sorted(symbols),'archive_sha256':sha(e/'libAPLUnified.a'),'files':{f.relative_to(e).as_posix():sha(f) for f in sorted(e.rglob('*')) if f.is_file()}}
(e/'manifest.json').write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
print('PRODUCT_ONLY_GO_LINK_PASS',m['archive_sha256'],len(new),'removed',m['removed_packages'])
PY
[[ ! -e "$out" ]]; mv "$E" "$out"
