#!/bin/zsh
set -euo pipefail

CONFIG="${APL_ASC_CONFIG:-$HOME/.config/arvectum/appstore-connect.env}"
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
  "$ALTOOL" --list-providers     --api-key "$ASC_KEY_ID"     --api-issuer "$ASC_ISSUER_ID"
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
