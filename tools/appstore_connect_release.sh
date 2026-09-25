#!/bin/zsh
set -euo pipefail

CONFIG="${ARVECTUM_ASC_CONFIG:-${APL_ASC_CONFIG:-$HOME/.config/arvectum/appstore-connect.env}}"
if [[ ! -r "$CONFIG" ]]; then
  echo "Missing App Store Connect config: $CONFIG" >&2
  exit 2
fi

source "$CONFIG"
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"

KEY_DIR="${ASC_KEY_DIR:-$HOME/.appstoreconnect/private_keys}"
KEY_FILE="$KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
if [[ ! -r "$KEY_FILE" ]]; then
  echo "Missing private key: $KEY_FILE" >&2
  exit 2
fi

XCODE="${ASC_XCODE:-/Applications/Xcode.app}"
ALTOOL="${ASC_ALTOOL:-$XCODE/Contents/SharedFrameworks/ContentDelivery.framework/Versions/A/Resources/altool}"
if [[ ! -x "$ALTOOL" ]]; then
  echo "altool not executable: $ALTOOL" >&2
  exit 2
fi

export API_PRIVATE_KEYS_DIR="$KEY_DIR"

usage() {
  echo "Usage: $0 auth | validate <ipa-or-pkg> | upload <ipa-or-pkg> | doctor"
}

run_auth() {
  local jwt_file body token code
  jwt_file=$(mktemp)
  body=$(mktemp)
  chmod 600 "$jwt_file" "$body"
  trap "rm -f '$jwt_file' '$body'" EXIT

  "$ALTOOL" --generate-jwt \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" >/dev/null 2>"$jwt_file"

  token=$(python3 - "$jwt_file" <<'PYJWT'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', s)
if not m:
    raise SystemExit(2)
print(m.group(0), end='')
PYJWT
  )

  code=$(curl -sS -o "$body" -w '%{http_code}' \
    -H "Authorization: Bearer $token" \
    'https://api.appstoreconnect.apple.com/v1/apps?limit=1')
  if [[ "$code" != "200" ]]; then
    echo "App Store Connect API auth failed (HTTP $code)" >&2
    exit 1
  fi
  echo "AUTH PASS: App Store Connect API HTTP 200"
}

run_file_action() {
  local action="$1"
  local artifact="${2:-}"
  [[ -n "$artifact" && -f "$artifact" ]] || {
    echo "Artifact not found: $artifact" >&2
    exit 2
  }
  if [[ "$action" == "validate" ]]; then
    "$ALTOOL" --validate-app "$artifact"       --api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID"
  else
    "$ALTOOL" --upload-package "$artifact"       --api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID"
  fi
}

case "${1:-}" in
  auth)
    run_auth
    ;;
  validate|upload)
    run_file_action "$1" "${2:-}"
    ;;
  doctor)
    echo "Config: $CONFIG"
    echo "Key ID: $ASC_KEY_ID"
    echo "Issuer configured: yes"
    echo "Private key: $KEY_FILE"
    echo "Private key mode: $(stat -f '%Sp' "$KEY_FILE" 2>/dev/null || echo unknown)"
    echo "altool: $ALTOOL"
    ;;
  *)
    usage
    exit 2
    ;;
esac
