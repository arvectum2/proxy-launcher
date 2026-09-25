#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
[[ "$(uname -s)" == Darwin ]] || { echo "APL-MAC-007: macOS required" >&2; exit 2; }

dmg="${1:-}"
[[ -f "$dmg" ]] || { echo "Usage: $0 <signed.dmg>" >&2; exit 2; }

developer_dir="${DEVELOPER_DIR:-/Applications/Xcode-26.6.0.app/Contents/Developer}"
notary=(env DEVELOPER_DIR="$developer_dir" xcrun notarytool)
stapler=(env DEVELOPER_DIR="$developer_dir" xcrun stapler)

auth=()
if [[ -n "${APL_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  auth=(--keychain-profile "$APL_NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${APL_NOTARY_KEY_PATH:-}" && -n "${APL_NOTARY_KEY_ID:-}" && -n "${APL_NOTARY_ISSUER_ID:-}" ]]; then
  auth=(--key "$APL_NOTARY_KEY_PATH" --key-id "$APL_NOTARY_KEY_ID" --issuer "$APL_NOTARY_ISSUER_ID")
else
  echo "APL-MAC-008: configure APL_NOTARY_KEYCHAIN_PROFILE or API-key credentials" >&2
  exit 3
fi

codesign --verify --strict "$dmg"
result="$(mktemp)"
trap 'rm -f "$result"' EXIT
"${notary[@]}" submit "$dmg" "${auth[@]}" --wait --output-format json > "$result"
python3 - "$result" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
status = payload.get("status")
submission_id = payload.get("id")
print(f"notary_submission_id={submission_id}")
print(f"notary_status={status}")
if status != "Accepted":
    raise SystemExit("APL-MAC-009: notarization was not accepted")
PY

"${stapler[@]}" staple "$dmg"
"${stapler[@]}" validate "$dmg"
spctl -a -vv -t open --context context:primary-signature "$dmg"
echo "$dmg"
