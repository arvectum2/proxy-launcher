#!/bin/bash
# Offline synthetic compiler acceptance, no runtime starts or device actions.
set -euo pipefail
umask 077
[[ $# == 4 && "$(uname -m)" == arm64 ]]
asset="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
mod="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
awg="$(cd "$3" && pwd)"
go_tar="$(cd "$(dirname "$4")" && pwd)/$(basename "$4")"
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(git -C "$awg" rev-parse HEAD)" == b5928efb6ca19f0153958460c3d141f04abc5c2e && -z "$(git -C "$awg" status --porcelain)" ]]
[[ "$(shasum -a256 "$awg/go.mod" | awk '{print $1}')" == 9fd0084da2acc4f96225daee85c0f866a0ec1079d5bdc4cf98c50e8a8fa0baf6 ]]
[[ "$(shasum -a256 "$awg/go.sum" | awk '{print $1}')" == eab202288b6f879fe1f6b0d9da0c528cfb310d74a7a4d409c7268c2b26b98a0a ]]
[[ "$(shasum -a256 "$go_tar" | awk '{print $1}')" == 544932844156d8172f7a28f77f2ac9c15a23046698b6243f633b0a0b00c0749c ]]
python3 "$root/Tools/verify_xray_apple_provenance.py" --asset "$asset" --go-mod "$mod"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-native-wg-config.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/mac" "$work/lab"
ln -s "$awg" "$work/awg"
python3 - "$asset" "$work/mac" <<'PY'
import sys,zipfile
from pathlib import Path
with zipfile.ZipFile(sys.argv[1]) as z:
    matches=[x for x in z.namelist() if '/macos-' in x and x.endswith('/libXray.a')]
    assert len(matches)==1
    prefix=matches[0].rsplit('/',1)[0]+'/'
    for item in ('libXray.a','Headers/libXray.h','Headers/module.modulemap'):
        p=Path(sys.argv[2])/item;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(prefix+item))
PY
xcrun --sdk macosx swiftc -target arm64-apple-macos13.0 -I "$work/mac/Headers" -L "$work/mac" -lXray -lresolv -framework SystemConfiguration "$root"/SharedCore/{TransportBackendContract,WGQuickConfigurationPreview,NativeWireGuardRuntimeConfig,ManagedProfileContract,ProxyModel}.swift "$root/Tools/NativeWGConfigValidation.swift" -o "$work/validate"
"$work/validate" "$work/awg.conf"
cp "$root"/Tools/AWGNativeLab/*.go "$root"/Tools/AWGNativeLab/go.mod "$root"/Tools/AWGNativeLab/go.sum "$work/lab/"
tar -xzf "$go_tar" -C "$work"
(cd "$work/lab" && APL_AWG_COMPILED_CONFIG="$work/awg.conf" GOTOOLCHAIN=local GOWORK=off GOPROXY=off "$work/go/bin/go" test -mod=readonly -run '^TestSwiftCompiledConfiguration$' -v)
echo NATIVE_WG_CONFIG_ACCEPTANCE_PASS
