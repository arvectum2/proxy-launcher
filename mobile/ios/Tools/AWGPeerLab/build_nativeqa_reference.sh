#!/bin/bash
# Build a loopback-only reference peer for the isolated, finite LAN relay.
set -euo pipefail
umask 077
[[ ( $# == 3 || $# == 4 ) && "$(uname -m)" == arm64 ]]
mode="${4:-loopback}"
[[ "$mode" == loopback || "$mode" == direct ]]
source_dir="$(cd "$1" && pwd)"
archive="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
output="$(cd "$3" && pwd)"
[[ "$(git -C "$source_dir" rev-parse HEAD)" == b5928efb6ca19f0153958460c3d141f04abc5c2e && -z "$(git -C "$source_dir" status --porcelain)" ]]
[[ "$(shasum -a256 "$source_dir/go.mod" | awk '{print $1}')" == 9fd0084da2acc4f96225daee85c0f866a0ec1079d5bdc4cf98c50e8a8fa0baf6 ]]
[[ "$(shasum -a256 "$source_dir/go.sum" | awk '{print $1}')" == eab202288b6f879fe1f6b0d9da0c528cfb310d74a7a4d409c7268c2b26b98a0a ]]
[[ "$(shasum -a256 "$archive" | awk '{print $1}')" == 544932844156d8172f7a28f77f2ac9c15a23046698b6243f633b0a0b00c0749c ]]
root="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-awg-nativeqa-reference.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/peer"
ln -s "$source_dir" "$work/awg"
cp "$root"/main.go "$root"/go.mod "$root"/go.sum "$work/peer/"
if [[ "$mode" == direct ]]; then
 python3 "$root/prepare_direct_reference.py" "$root/../AWGNativeLab/scoped_bind.go" "$work/peer"
 python3 - "$work/peer/main.go" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]);s=p.read_text();assert s.count("45 * time.Second")==1;p.write_text(s.replace("45 * time.Second","120 * time.Second"))
PY
else
python3 - "$root/../AWGNativeLab/scoped_bind.go" "$work/peer" <<'PY'
import sys
from pathlib import Path
d=Path(sys.argv[2])
s=Path(sys.argv[1]).read_text()
for old,new in [('192.168.1.80','127.0.0.1'),('192.168.1.0/24','127.0.0.0/24'),('192.168.1.255','127.0.0.255')]:
    assert s.count(old)==1
    s=s.replace(old,new)
(d/'scoped_bind.go').write_text(s)
p=d/'main.go';s=p.read_text();assert s.count('45 * time.Second')==1
p.write_text(s.replace('45 * time.Second','120 * time.Second'))
PY
fi
tar -xzf "$archive" -C "$work"
export PATH="$work/go/bin:$PATH" GOTOOLCHAIN=local GOWORK=off GOPROXY=off
(cd "$work/peer" && go mod verify && go test -mod=readonly ./... && go build -mod=readonly -trimpath -o "$work/awg-reference" .)
digest="$(shasum -a256 "$work/awg-reference" | awk '{print $1}')"
if [[ "$mode" == direct ]]; then
 python3 "$root/run_preflight.py" --peer "$work/awg-reference"
else
 python3 "$root/../run_awg_reference_loopback.py" "$work/awg-reference" "$digest"
fi
cp "$work/awg-reference" "$output/"
(cd "$output" && shasum -a256 awg-reference > SHA256SUMS)
