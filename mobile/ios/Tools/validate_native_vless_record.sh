#!/bin/bash
# Exact asset and offline config acceptance only. Never starts Xray.
set -euo pipefail
umask 077
[[ $# == 2 && "$(uname -m)" == arm64 ]]
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$root/Tools/verify_xray_apple_provenance.py" --asset "$1" --go-mod "$2"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-vless-record.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
python3 - "$1" "$work" <<'PY'
import sys,zipfile
from pathlib import Path
with zipfile.ZipFile(sys.argv[1]) as z:
 names=[n for n in z.namelist() if '/macos-' in n and n.endswith('/libXray.a')];assert len(names)==1
 prefix=names[0].rsplit('/',1)[0]+'/'
 for item in ('libXray.a','Headers/libXray.h','Headers/module.modulemap'):
  p=Path(sys.argv[2])/item;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(prefix+item))
PY
xcrun --sdk macosx swiftc -target arm64-apple-macos13.0 -I "$work/Headers" -L "$work" -lXray -lresolv -framework SystemConfiguration "$root"/SharedCore/{NativeCredentialRecord,NativeWireGuardRuntimeConfig,NativeTunnelRoutePlan,TransportBackendContract,WGQuickConfigurationPreview,ManagedProfileContract,ProxyModel,VLESSRealityShareLink,XrayVLESSRuntimeConfig}.swift "$root/Tools/NativeVLESSRecordValidation.swift" -o "$work/validate"
"$work/validate"
