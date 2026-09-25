#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
[[ "$(uname -s)" == Darwin ]] || { echo "APL-MAC-007: macOS required" >&2; exit 2; }

app="${1:-}"
[[ -d "$app" ]] || { echo "Usage: $0 <signed.app>" >&2; exit 2; }

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

codesign --verify --deep --strict "$app"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
zip="$tmp/app.zip"
/usr/bin/ditto -c -k --keepParent "$app" "$zip"
result="$tmp/notary.json"
"${notary[@]}" submit "$zip" "${auth[@]}" --wait --output-format json > "$result"
python3 - "$result" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1],encoding="utf-8"))
print(f"notary_submission_id={payload.get('id')}")
print(f"notary_status={payload.get('status')}")
if payload.get("status") != "Accepted":
    raise SystemExit("APL-MAC-009: notarization was not accepted")
PY
"${stapler[@]}" staple "$app"
"${stapler[@]}" validate "$app"
spctl -a -vv -t exec "$app"
echo "$app"
