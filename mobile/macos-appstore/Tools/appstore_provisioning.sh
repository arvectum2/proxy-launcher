#!/bin/zsh
set -euo pipefail

CONFIG="${ARVECTUM_ASC_CONFIG:-${APL_ASC_CONFIG:-$HOME/.config/arvectum/appstore-connect.env}}"
[[ -r "$CONFIG" ]] || { echo "Missing App Store Connect config: $CONFIG" >&2; exit 2; }
source "$CONFIG"
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"

KEY_DIR="${ASC_KEY_DIR:-$HOME/.appstoreconnect/private_keys}"
KEY_FILE="$KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
[[ -r "$KEY_FILE" ]] || { echo "Missing private key" >&2; exit 2; }

XCODE="${ASC_XCODE:-/Applications/Xcode-26.6.0.app}"
ALTOOL="$XCODE/Contents/SharedFrameworks/ContentDelivery.framework/Versions/A/Resources/altool"
[[ -x "$ALTOOL" ]] || { echo "altool unavailable" >&2; exit 2; }
export API_PRIVATE_KEYS_DIR="$KEY_DIR"

make_token() {
  local jwt_file token
  jwt_file=$(mktemp)
  chmod 600 "$jwt_file"
  "$ALTOOL" --generate-jwt --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" >/dev/null 2>"$jwt_file"
  token=$(python3 - "$jwt_file" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', text)
if not match:
    raise SystemExit("JWT generation failed")
print(match.group(0), end="")
PY
)
  rm -f "$jwt_file"
  print -r -- "$token"
}

api_get() {
  local endpoint="$1" token body code
  token=$(make_token)
  body=$(mktemp)
  chmod 600 "$body"
  code=$(curl -sS -o "$body" -w '%{http_code}' -H "Authorization: Bearer $token" "https://api.appstoreconnect.apple.com$endpoint")
  if [[ "$code" != 2* ]]; then
    echo "App Store Connect API GET failed: HTTP $code" >&2
    python3 - "$body" <<'PY'
import json, sys
try:
    payload=json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit(1)
for error in payload.get("errors", []):
    print(error.get("status"), error.get("code"), error.get("title"), error.get("detail"), file=sys.stderr)
PY
    rm -f "$body"
    return 1
  fi
  cat "$body"
  rm -f "$body"
}

doctor() {
  local tmp
  tmp=$(mktemp)
  chmod 600 "$tmp"
  api_get '/v1/bundleIds?limit=200' >"$tmp"
  python3 - "$tmp" <<'PY'
import json, sys
wanted={"ru.arvectum.proxylauncher.macos","ru.arvectum.proxylauncher.macos.PacketTunnel","ru.arvectum.proxylauncher.ios","ru.arvectum.proxylauncher.ios.PacketTunnel"}
payload=json.load(open(sys.argv[1]))
for item in payload.get("data", []):
    attrs=item.get("attributes", {})
    if attrs.get("identifier") in wanted:
        print("BUNDLE", item.get("id"), attrs.get("identifier"), attrs.get("platform"))
        if attrs.get("identifier") in {"ru.arvectum.proxylauncher.ios","ru.arvectum.proxylauncher.ios.PacketTunnel"}:
            print("CAPABILITY_URL", item.get("id"))
PY
  for bundle_id in $(python3 - "$tmp" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1]))
wanted={"ru.arvectum.proxylauncher.ios","ru.arvectum.proxylauncher.ios.PacketTunnel"}
for item in payload.get("data", []):
    if item.get("attributes", {}).get("identifier") in wanted:
        print(item.get("id"))
PY
  ); do
    api_get "/v1/bundleIds/$bundle_id/bundleIdCapabilities" >"$tmp"
    python3 - "$tmp" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1]))
for item in payload.get("data", []):
    a=item.get("attributes", {})
    print("CAP", a.get("capabilityType"), json.dumps(a.get("settings") or [], separators=(",",":")))
PY
  done
  api_get '/v1/certificates?limit=200' >"$tmp"
  python3 - "$tmp" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1]))
for item in payload.get("data", []):
    a=item.get("attributes", {})
    if a.get("activated", True):
        print("CERT", item.get("id"), a.get("certificateType"), a.get("displayName"), a.get("platform"), a.get("expirationDate"))
PY
  api_get '/v1/devices?limit=200' >"$tmp"
  python3 - "$tmp" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1]))
for item in payload.get("data", []):
    a=item.get("attributes", {})
    if a.get("status") == "ENABLED":
        udid=str(a.get("udid") or "")
        print("DEVICE", item.get("id"), a.get("name"), a.get("platform"), a.get("deviceClass"), ("…"+udid[-8:]) if udid else "")
PY
  rm -f "$tmp"
}

case "${1:-}" in
  doctor) doctor ;;
  *) echo "Usage: $0 doctor" >&2; exit 2 ;;
esac
