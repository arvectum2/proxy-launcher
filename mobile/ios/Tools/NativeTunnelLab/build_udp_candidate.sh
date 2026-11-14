#!/bin/bash
set -euo pipefail
umask 077
[[ $# == 1 && ! -e "$1" ]]
root="$(cd "$(dirname "$0")/../.." && pwd)"
destination="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-loopback-udp-candidate.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp -R "$root/Tools" "$work/Tools"
cp "$root/Tools/NativeTunnelLab/tun2proxy-connected-udp-loopback-candidate.patch" "$work/Tools/tun2proxy-connected-udp.patch"
python="${PYTHON:-python3}"
"$python" - "$work/Tools/fetch_tun2proxy.py" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]);s=p.read_text()
assert s.count("sameflow-retry-connected-udp")==1
p.write_text(s.replace("sameflow-retry-connected-udp","sameflow-retry-loopback-binding-candidate-connected-udp"))
PY
"$python" -u "$work/Tools/fetch_tun2proxy.py"
"$python" "$root/Tools/verify_tun2proxy_lab_artifact.py" "$work/Frameworks/tun2proxy.xcframework" ios-arm64 --require-connected-udp
mkdir "$destination"
cp -R "$work/Frameworks/tun2proxy.xcframework" "$destination/"
cp "$work/Frameworks/.tun2proxy-version" "$destination/"
