#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
[[ "$(uname -s)" == Darwin ]] || { echo "APL-MAC-005: macOS required" >&2; exit 2; }
app="${1:-dist/Arvectum Proxy Launcher.app}"
[[ -d "$app" ]] || { echo "Missing .app bundle: $app" >&2; exit 2; }
version="$(tr -d '[:space:]' < VERSION)"
arch="$(uname -m)"
out_dir="${2:-dist/dmg}"
mkdir -p "$out_dir"
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/Arvectum Proxy Launcher.app"
cp LICENSE "$stage/LICENSE.txt"
cp THIRD_PARTY_NOTICES.txt "$stage/THIRD_PARTY_NOTICES.txt"
[[ -d "$app/Contents/Resources/THIRD_PARTY_LICENSES" ]] || { echo "APL-IP-004: .app license bundle missing" >&2; exit 3; }
cp -R "$app/Contents/Resources/THIRD_PARTY_LICENSES" "$stage/THIRD_PARTY_LICENSES"
python3 tools/third_party_license_bundle.py --verify --output "$stage/THIRD_PARTY_LICENSES"
ln -s /Applications "$stage/Applications"
out="$out_dir/Arvectum_Proxy_Launcher-${version}-${arch}.dmg"
rm -f "$out"
/usr/bin/hdiutil create -quiet -volname "Arvectum Proxy Launcher" -srcfolder "$stage" -ov -format UDZO "$out"
/usr/bin/hdiutil verify "$out" >/dev/null
sign_identity="${APL_MACOS_SIGN_IDENTITY:-}"
if [[ -n "$sign_identity" ]]; then
  [[ "$sign_identity" == Developer\ ID\ Application:* ]] || {
    echo "APL-MAC-006: production DMG signing requires Developer ID Application identity" >&2
    exit 4
  }
  codesign --force --timestamp --sign "$sign_identity" "$out"
  codesign --verify --strict "$out"
fi
echo "$out"
