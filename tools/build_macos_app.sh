#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
[[ "$(uname -s)" == Darwin ]] || { echo "APL-MAC-004: macOS required" >&2; exit 2; }
python_bin="${PYTHON_BIN:-python3}"
"$python_bin" -m PyInstaller --version >/dev/null
icon="$repo_root/assets/arvectum.icns"
[[ -f "$icon" ]] || { echo "Missing canonical macOS icon: $icon" >&2; exit 2; }
rm -rf "dist/Arvectum Proxy Launcher.app" build/macos-app
"$python_bin" -m PyInstaller --noconfirm --clean --onedir --windowed \
  --name "Arvectum Proxy Launcher" \
  --osx-bundle-identifier "ru.arvectum.proxylauncher" \
  --icon "$icon" \
  --add-data "$repo_root/no_proxy.txt:." \
  --add-data "$repo_root/assets:assets" \
  --workpath "$repo_root/build/macos-app" \
  --specpath "$repo_root/build/macos-app" \
  "$repo_root/proxy_gui.py"
app="dist/Arvectum Proxy Launcher.app"
[[ -d "$app/Contents/MacOS" && -f "$app/Contents/Info.plist" ]] || { echo "Invalid .app bundle" >&2; exit 3; }
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" | grep -qx 'ru.arvectum.proxylauncher'

# PyInstaller defaults the bundle version to 0.0.0 unless a spec overrides it.
# Bind bundle metadata to the canonical repository VERSION before final signing.
product_version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
[[ "$product_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || {
  echo "Invalid canonical VERSION for macOS bundle: $product_version" >&2
  exit 3
}
bundle_version="${product_version%%[-+]*}"
set_plist_string() {
  local key="$1" value="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
  fi
}
set_plist_string CFBundleShortVersionString "$bundle_version"
set_plist_string CFBundleVersion "$bundle_version"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" | grep -qx "$bundle_version"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" | grep -qx "$bundle_version"

resources="$app/Contents/Resources"
licenses="$resources/THIRD_PARTY_LICENSES"
mkdir -p "$resources"
install -m644 LICENSE "$resources/LICENSE.txt"
install -m644 THIRD_PARTY_NOTICES.txt "$resources/THIRD_PARTY_NOTICES.txt"
"$python_bin" tools/third_party_license_bundle.py --build --output "$licenses"
"$python_bin" tools/third_party_license_bundle.py --verify --output "$licenses"

# PyInstaller signs the bundle before these governed license resources are added.
# Re-seal after the final resource mutation. Default CI/private builds remain
# ad-hoc; production builds opt in explicitly with a Developer ID identity.
sign_identity="${APL_MACOS_SIGN_IDENTITY:-}"
if [[ -n "$sign_identity" ]]; then
  [[ "$sign_identity" == Developer\ ID\ Application:* ]] || {
    echo "APL-MAC-006: production signing requires Developer ID Application identity" >&2
    exit 4
  }
  codesign --force --deep --timestamp --options runtime --sign "$sign_identity" "$app"
  codesign --verify --deep --strict "$app"
  signature_details="$(codesign -dv --verbose=4 "$app" 2>&1)"
  grep -q 'Runtime Version=' <<<"$signature_details"
  grep -q 'Authority=Developer ID Application:' <<<"$signature_details"
  grep -q 'TeamIdentifier=VML75VY94V' <<<"$signature_details"
  grep -q 'Timestamp=' <<<"$signature_details"
else
  codesign --force --deep --sign - "$app"
  codesign --verify --deep --strict "$app"
fi

echo "$app"
