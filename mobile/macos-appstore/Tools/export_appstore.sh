#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h:h:h}
CONFIG="${ARVECTUM_ASC_CONFIG:-${APL_ASC_CONFIG:-$HOME/.config/arvectum/appstore-connect.env}}"
[[ -r "$CONFIG" ]] || { echo "Missing App Store Connect config: $CONFIG" >&2; exit 2; }
source "$CONFIG"
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"

KEY_DIR="${ASC_KEY_DIR:-$HOME/.appstoreconnect/private_keys}"
KEY_FILE="$KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
[[ -r "$KEY_FILE" ]] || { echo "Missing App Store Connect private key" >&2; exit 2; }

XCODE="${ASC_XCODE:-/Applications/Xcode-26.6.0.app}"
export DEVELOPER_DIR="$XCODE/Contents/Developer"

ARCHIVE="${1:-$ROOT/build/macos-appstore-release/ArvectumProxyLauncherMac.xcarchive}"
EXPORT_DIR="${2:-$ROOT/build/macos-appstore-release/automatic-export}"
OPTIONS="$ROOT/build/macos-appstore-release/ExportOptionsAutomatic.plist"

[[ -d "$ARCHIVE" ]] || { echo "Missing archive: $ARCHIVE" >&2; exit 2; }
mkdir -p "${OPTIONS:h}"

cat >"$OPTIONS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>VML75VY94V</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
PLIST

rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$OPTIONS" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_FILE" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

find "$EXPORT_DIR" -maxdepth 2 -type f -print
