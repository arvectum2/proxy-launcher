#!/bin/bash
# Local synthetic configuration and loopback lifecycle only, no VPN or device.
set -euo pipefail
umask 077
[[ $# == 3 && "$(uname -m)" == arm64 ]]
a="$(cd "$1" && pwd)"
asset="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
mod="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$root/Tools/verify_xray_apple_provenance.py" --asset "$asset" --go-mod "$mod"
python3 - "$root/Tools/xray_source_pins.json" "$a" <<'PY'
import hashlib,json,pathlib,subprocess,sys
pin=json.load(open(sys.argv[1]));a=pathlib.Path(sys.argv[2]);src=a/'libxray'
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def git(*args):return subprocess.check_output(['git','-C',str(src),*args],text=True).strip()
assert sha(a/pin['go_archive'])==pin['go_archive_sha256']
assert sha(src/'go.mod')==pin['go_mod_sha256'] and sha(src/'go.sum')==pin['go_sum_sha256']
assert git('cat-file','-t',pin['annotated_tag_object'])=='tag'
assert git('rev-parse',pin['annotated_tag_object']+'^{commit}')==pin['source_commit']==git('rev-parse','HEAD')
assert not git('status','--porcelain')
PY
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-xray-source-runtime.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/source/Headers" "$work/upstream/Headers"
export GOTOOLCHAIN=local GOWORK=off GOENV=off GOPATH="$a/gopath" GOMODCACHE="$a/modcache" GOCACHE="$a/gocache" GOPROXY=off GOSUMDB=sum.golang.org GOPRIVATE= GONOSUMDB= GONOPROXY=
[[ "$("$a/go/bin/go" version)" == 'go version go1.27.3 darwin/arm64' ]]
(cd "$a/libxray"; "$a/go/bin/go" mod verify; export GOOS=darwin GOARCH=arm64 CGO_ENABLED=1; sdk=$(xcrun --sdk macosx --show-sdk-path); export CC="$(xcrun --sdk macosx --find clang)" CGO_CFLAGS="-target arm64-apple-macos12.0 -isysroot $sdk" CGO_LDFLAGS="-target arm64-apple-macos12.0 -isysroot $sdk -Wl,-Bsymbolic-functions"; "$a/go/bin/go" build -mod=readonly -tags=darwin -trimpath -ldflags '-s -w -buildid=' -buildmode=c-archive -o "$work/source/libXray.a" ./cgo_bridge; [[ -z "$(git status --porcelain)" ]])
cp "$work/source/libXray.h" "$work/source/Headers/"
python3 - "$asset" "$work" <<'PY'
import zipfile,sys,pathlib
w=pathlib.Path(sys.argv[2]);
with zipfile.ZipFile(sys.argv[1]) as z:
 names=[n for n in z.namelist() if '/macos-' in n and n.endswith('/libXray.a')];assert len(names)==1
 prefix=names[0].rsplit('/',1)[0]+'/'
 for item in ('libXray.a','Headers/libXray.h','Headers/module.modulemap'):(w/'upstream'/item).write_bytes(z.read(prefix+item))
 (w/'source/Headers/module.modulemap').write_bytes(z.read(prefix+'Headers/module.modulemap'))
PY
for mode in source upstream; do
 p="$work/$mode"
 for probe in NativeVLESSRecordValidation NativeXraySourceLifecycleValidation; do
  xcrun --sdk macosx swiftc -target arm64-apple-macos13.0 -I "$p/Headers" -L "$p" -lXray -lresolv -framework SystemConfiguration -framework CoreFoundation -framework Security "$root"/SharedCore/{NativeCredentialRecord,NativeWireGuardRuntimeConfig,NativeTunnelRoutePlan,TransportBackendContract,WGQuickConfigurationPreview,ManagedProfileContract,ProxyModel,VLESSRealityShareLink,XrayVLESSRuntimeConfig}.swift "$root/Tools/$probe.swift" -o "$p/$probe"
  python3 - "$p/$probe" "$probe" <<'PY'
import subprocess,sys
marker={'NativeVLESSRecordValidation':'PINNED_VLESS_RECORD_NATIVE_CONFIG_ACCEPTED_2_OF_2','NativeXraySourceLifecycleValidation':'XRAY_LOOPBACK_WG_CONFIG_NEGATIVE_AND_LIFECYCLE_3_OF_3_PASS'}[sys.argv[2]]
r=subprocess.run([sys.argv[1]],capture_output=True,text=True,timeout=15)
assert r.returncode==0 and marker in r.stdout.splitlines(),'local validation failed'
print(marker)
PY
  echo "$mode $probe PASS"
 done
done
