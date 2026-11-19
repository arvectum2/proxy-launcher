#!/bin/bash
# Offline source-level inventory for the isolated iOS AWG candidate only.
# Not a final linked-binary SBOM, distribution clearance or IPA mutation.
set -euo pipefail
umask 077
[[ $# == 3 && "$(uname -m)" == arm64 ]]
source_dir="$(cd "$1" && pwd)"
archive="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
dest="$(cd "$3" && pwd)"
[[ -z "$(ls -A "$dest")" ]]
[[ "$(git -C "$source_dir" rev-parse HEAD)" == b5928efb6ca19f0153958460c3d141f04abc5c2e && -z "$(git -C "$source_dir" status --porcelain)" ]]
[[ "$(shasum -a256 "$source_dir/go.mod" | awk '{print $1}')" == 9fd0084da2acc4f96225daee85c0f866a0ec1079d5bdc4cf98c50e8a8fa0baf6 ]]
[[ "$(shasum -a256 "$source_dir/go.sum" | awk '{print $1}')" == eab202288b6f879fe1f6b0d9da0c528cfb310d74a7a4d409c7268c2b26b98a0a ]]
[[ "$(shasum -a256 "$archive" | awk '{print $1}')" == 544932844156d8172f7a28f77f2ac9c15a23046698b6243f633b0a0b00c0749c ]]
root="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-awg-licenses.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/lab" "$work/bundle"
ln -s "$source_dir" "$work/awg"
cp "$root"/*.go "$root"/go.mod "$root"/go.sum "$work/lab/"
tar -xzf "$archive" -C "$work"
(cd "$work/lab"; export GOTOOLCHAIN=local GOWORK=off GOPROXY=off; "$work/go/bin/go" mod verify; GOOS=ios GOARCH=arm64 CGO_ENABLED=1 "$work/go/bin/go" list -mod=readonly -deps -f '{{with .Module}}{{.Path}}|{{.Version}}|{{if .Replace}}{{.Replace.Dir}}{{else}}{{.Dir}}{{end}}{{end}}' . | sed '/^$/d' | sort -u > "$work/modules")
python3 - "$work/modules" "$work/go" "$work/bundle" <<'PY'
import hashlib,json,sys,pathlib
modules,go,out=map(pathlib.Path,sys.argv[1:]);expected={('github.com/amnezia-vpn/amneziawg-go/v3','v3.1.20260828'),('golang.org/x/crypto','v0.42.0'),('golang.org/x/net','v0.44.0'),('golang.org/x/sys','v0.36.0')}
rows=[x.split('|') for x in modules.read_text().splitlines()];rows=[x for x in rows if x[0]!='arvectum.local/awg-native-lab'];assert {(a,b) for a,b,_ in rows}==expected,'Unexpected iOS module closure'
rows.append(('go-stdlib-runtime','go1.25.0',str(go)))
manifest={'schema':'arvectum.awg-ios-candidate-source-licenses.v1','target':'ios/arm64 cgo source dependency closure','release_authorized':False,'components':[]}
for n,v,d in rows:
 p=pathlib.Path(d);folder=out/n.replace('/','_');folder.mkdir();files=[]
 for name in ('LICENSE','PATENTS','NOTICE','COPYING','AUTHORS'):
  f=p/name
  if not f.is_file():continue
  data=f.read_bytes();assert 0<len(data)<=1000000
  dest=folder/name;dest.write_bytes(data);files.append({'path':str(dest.relative_to(out)),'sha256':hashlib.sha256(data).hexdigest()})
 assert any(x['path'].endswith('/LICENSE') for x in files),'Missing license'
 manifest['components'].append({'module':n,'version':v,'files':files})
(out/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
print('AWG_IOS_SOURCE_LICENSE_INVENTORY',len(rows),'components')
PY
cp -R "$work/bundle/." "$dest/"
