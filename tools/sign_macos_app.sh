#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
[[ "$(uname -s)" == Darwin ]] || { echo "APL-MAC-010: macOS required" >&2; exit 2; }

app="${1:-}"
identity="${APL_MACOS_SIGN_IDENTITY:-Developer ID Application: LLC ARVECTUM (VML75VY94V)}"
[[ -d "$app" && -f "$app/Contents/Info.plist" ]] || { echo "Usage: $0 <app-bundle>" >&2; exit 2; }
[[ "$identity" == Developer\ ID\ Application:* ]] || {
  echo "APL-MAC-006: production signing requires Developer ID Application identity" >&2
  exit 4
}
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
[[ "$bundle_id" == "ru.arvectum.proxylauncher" ]] || {
  echo "APL-MAC-011: unexpected bundle id: $bundle_id" >&2
  exit 5
}
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$bundle_version" == "${version%%[-+]*}" ]] || {
  echo "APL-MAC-012: app version $bundle_version does not match repository VERSION $version" >&2
  exit 5
}

codesign --force --deep --timestamp --options runtime --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
details="$(codesign -dv --verbose=4 "$app" 2>&1)"
grep -q 'Authority=Developer ID Application:' <<<"$details"
grep -q 'TeamIdentifier=VML75VY94V' <<<"$details"
grep -q 'Runtime Version=' <<<"$details"
grep -q 'Timestamp=' <<<"$details"
echo "$app"
