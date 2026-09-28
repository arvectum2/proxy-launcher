#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h:h:h}
ARCHIVE="${1:-$ROOT/build/macos-appstore-release/ArvectumProxyLauncherMac.xcarchive}"
EXPORT_DIR="${2:-$ROOT/build/macos-appstore-release/export}"
INSTALLER_STATE="${APL_MAC_INSTALLER_STATE:-$HOME/.config/arvectum/appstore-installer.env}"

[[ -d "$ARCHIVE" ]] || { echo "Missing archive: $ARCHIVE" >&2; exit 2; }
[[ -r "$INSTALLER_STATE" ]] || {
  echo "Missing installer signing state: $INSTALLER_STATE" >&2
  echo "Run Tools/bootstrap_installer_signing.sh first." >&2
  exit 2
}
source "$INSTALLER_STATE"
: "${ASC_INSTALLER_CERT_SHA1:?ASC_INSTALLER_CERT_SHA1 is required}"
: "${ASC_INSTALLER_KEYCHAIN:?ASC_INSTALLER_KEYCHAIN is required}"
: "${ASC_INSTALLER_KEYCHAIN_PASS_FILE:?ASC_INSTALLER_KEYCHAIN_PASS_FILE is required}"
[[ -r "$ASC_INSTALLER_KEYCHAIN_PASS_FILE" ]] || { echo "Missing installer keychain password file" >&2; exit 2; }

APP="$ARCHIVE/Products/Applications/Arvectum Proxy Launcher.app"
[[ -d "$APP" ]] || { echo "Missing archived app: $APP" >&2; exit 2; }

INFO="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")

codesign --verify --deep --strict --verbose=2 "$APP"

kcpass=$(cat "$ASC_INSTALLER_KEYCHAIN_PASS_FILE")
security unlock-keychain -p "$kcpass" "$ASC_INSTALLER_KEYCHAIN"
security set-keychain-settings -lut 21600 "$ASC_INSTALLER_KEYCHAIN"
unset kcpass

rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
PKG="$EXPORT_DIR/Arvectum-Proxy-Launcher-macOS-AppStore-${VERSION}-build${BUILD}.pkg"

# The app archive is already signed with Apple Distribution + App Store
# provisioning. The outer Mac App Store installer package must use the
# separately managed Mac Installer Distribution identity.
productbuild \
  --component "$APP" /Applications \
  --sign "$ASC_INSTALLER_CERT_SHA1" \
  --keychain "$ASC_INSTALLER_KEYCHAIN" \
  "$PKG"

pkgutil --check-signature "$PKG"
shasum -a 256 "$PKG"
printf '%s\n' "$PKG"
