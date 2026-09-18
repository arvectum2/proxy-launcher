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
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" | grep -qx 'ru.arvectum.proxylauncher'
resources="$app/Contents/Resources"
licenses="$resources/THIRD_PARTY_LICENSES"
mkdir -p "$resources"
install -m644 LICENSE "$resources/LICENSE.txt"
install -m644 THIRD_PARTY_NOTICES.txt "$resources/THIRD_PARTY_NOTICES.txt"
"$python_bin" tools/third_party_license_bundle.py --build --output "$licenses"
"$python_bin" tools/third_party_license_bundle.py --verify --output "$licenses"

# PyInstaller signs the bundle before these governed license resources are added.
# Re-seal the final artifact so macOS sees a valid ad-hoc signature for personal/CI builds.
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"

echo "$app"
