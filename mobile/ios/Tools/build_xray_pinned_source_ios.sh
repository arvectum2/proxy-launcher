#!/bin/bash
# Offline source build only. No dependency downloads, GOENV writes, signing or deployment.
set -euo pipefail
umask 077
[[ $# == 2 && "$(uname -m)" == arm64 ]]
a="$(cd "$1" && pwd)"
out="$2"
[[ ! -e "$out" ]]
root="$(cd "$(dirname "$0")" && pwd)"
pin="$root/xray_source_pins.json"
python3 - "$pin" "$a" <<'PY'
import hashlib,json,pathlib,subprocess,sys
p=json.load(open(sys.argv[1]));a=pathlib.Path(sys.argv[2]);src=a/'libxray'
def sha(f):
 with f.open('rb') as r:return hashlib.file_digest(r,'sha256').hexdigest()
assert (a/p['go_archive']).stat().st_size==p['go_archive_bytes']
assert sha(a/p['go_archive'])==p['go_archive_sha256']
assert sha(src/'go.mod')==p['go_mod_sha256'] and sha(src/'go.sum')==p['go_sum_sha256']
def git(*args):return subprocess.check_output(['git','-C',str(src),*args],text=True).strip()
assert git('cat-file','-t',p['annotated_tag_object'])=='tag'
assert git('rev-parse',p['annotated_tag_object']+'^{commit}')==p['source_commit']==git('rev-parse','HEAD')
assert not git('status','--porcelain')
PY
mkdir -p "$out"
out="$(cd "$out" && pwd)"
export GOTOOLCHAIN=local GOWORK=off GOENV=off GOPATH="$a/gopath" GOMODCACHE="$a/modcache" GOCACHE="$a/gocache" GOPROXY=off GOSUMDB=sum.golang.org GOPRIVATE= GONOSUMDB= GONOPROXY=
[[ "$("$a/go/bin/go" version)" == 'go version go1.27.3 darwin/arm64' ]]
cd "$a/libxray"
"$a/go/bin/go" mod verify
export GOOS=ios GOARCH=arm64 CGO_ENABLED=1
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
export CC="$(xcrun --sdk iphoneos --find clang)" CGO_CFLAGS="-target arm64-apple-ios15.0 -isysroot $sdk" CGO_LDFLAGS="-target arm64-apple-ios15.0 -isysroot $sdk -Wl,-Bsymbolic-functions"
"$a/go/bin/go" list -mod=readonly -tags=ios -deps -json ./cgo_bridge > "$out/ios-deps.json"
"$a/go/bin/go" build -mod=readonly -tags=ios -trimpath -ldflags '-s -w -buildid=' -buildmode=c-archive -o "$out/libXray.a" ./cgo_bridge
cat > "$out/link_probe.c" <<'C'
#include "libXray.h"
int main(void){char req[]="{\"apiVersion\":3,\"method\":\"xrayVersion\"}";char* r=CGoInvoke(req);if(!r)return 1;CGoFree(r);return 0;}
C
xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -isysroot "$sdk" -I "$out" "$out/link_probe.c" "$out/libXray.a" -lresolv -framework SystemConfiguration -framework CoreFoundation -framework Security -o "$out/ios-link-probe"
[[ -z "$(git status --porcelain)" ]]
xcrun vtool -show-build "$out/ios-link-probe"
shasum -a 256 "$out/libXray.a" "$out/libXray.h"
echo XRAY_PINNED_OFFLINE_IOS_BUILD_LINK_PASS
