#!/bin/bash
set -euo pipefail
umask 077
[[ $# == 4 && "$1" == --approved ]] || { echo "usage: $0 --approved REFERENCE WG_PREFLIGHT VLESS_PREFLIGHT"; exit 2; }
root="$(cd "$(dirname "$0")" && pwd)"
reference="$2"; wg="$3"; vless="$4"
python="${PYTHON:-python3}"
device=00008110-001C51810A12401E
app=ru.arvectum.proxylauncher.lab.nativeqa
tmp="$(mktemp -d "${TMPDIR:-/tmp}/apl-wg-stability.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
for item in progress result; do
  xcrun devicectl device copy from --device "$device" --domain-type appDataContainer --domain-identifier "$app" --source "Documents/native-lab-$item.json" --destination "$tmp/$item.json" >/dev/null
done
"$python" - "$tmp" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
a=json.loads((p/"progress.json").read_text())
b=json.loads((p/"result.json").read_text())
assert a["runID"]==b["runID"] and a["stage"]=="labPreparedOff" and b["prepared"] is True and b["connected"] is False
PY
assert_no_extension() {
    local listing
    listing="$(xcrun devicectl device info processes --device "$device")"
    if grep -Eq 'NativeLab.appex|Arvectum Packet Tunnel' <<<"$listing"; then
        echo LIVE_EXTENSION_ABORT >&2
        return 1
    fi
}
assert_no_extension
# No retries: any failure is retained as failed stability evidence.
# Every run uses new keys, nonce, and reference process with measurement disabled.
for kind in tcp4 udp4 udp6 udp4 udp6 udp4 udp6 tcp6; do
    echo "CLEAN_WG_CASE $kind"
    "$python" -u "$root/run_physical_wg.py" --approved --reference "$reference" --preflight "$wg" --kind "$kind" --retain-profile
    assert_no_extension
done
echo CLEAN_WG_WRONG_KEY
"$python" -u "$root/run_physical_wg.py" --approved --reference "$reference" --preflight "$wg" --kind tcp4 --wrong-key --retain-profile
assert_no_extension
echo CLEAN_VLESS_REGRESSION
"$python" -u "$root/run_physical_peer.py" --approved --peer "$vless" --mode positive
assert_no_extension
echo CLEAN_WG_STABILITY_AND_VLESS_REGRESSION_PASS
