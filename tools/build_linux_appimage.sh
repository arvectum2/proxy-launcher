#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
artifact="${1:-dist/Arvectum Proxy Launcher}"
out_dir="${2:-dist/appimage}"
[[ "$(uname -s)" == Linux ]] || { echo "APL-LNX-008: Linux required" >&2; exit 2; }
[[ -x "$artifact" ]] || { echo "Missing executable Linux artifact: $artifact" >&2; exit 2; }
source tools/appimage-toolchain.lock
cache="${APPIMAGE_TOOLCHAIN_CACHE:-$repo_root/.cache/appimage}"
tool="$cache/appimagetool-x86_64.AppImage"
runtime="$cache/runtime-x86_64"
for f in "$tool" "$runtime"; do [[ -f "$f" ]] || { echo "Missing pinned AppImage toolchain: $f" >&2; exit 2; }; done
echo "$APPIMAGETOOL_SHA256  $tool" | sha256sum -c -
echo "$APPIMAGE_RUNTIME_SHA256  $runtime" | sha256sum -c -
version="$(tr -d '[:space:]' < VERSION)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
appdir="$work/ArvectumProxyLauncher.AppDir"
docdir="$appdir/usr/share/doc/arvectum-proxy-launcher"
license_bundle="$work/THIRD_PARTY_LICENSES"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/256x256/apps" "$docdir" "$out_dir"
python3 tools/third_party_license_bundle.py --build --output "$license_bundle"
python3 tools/third_party_license_bundle.py --verify --output "$license_bundle"
install -m755 "$artifact" "$appdir/usr/bin/arvectum-proxy-launcher"
install -m644 assets/arvectum-icon-0.2.2-transparent.png "$appdir/usr/share/icons/hicolor/256x256/apps/arvectum-proxy-launcher.png"
install -m644 LICENSE "$docdir/LICENSE.txt"
install -m644 THIRD_PARTY_NOTICES.txt "$docdir/THIRD_PARTY_NOTICES.txt"
install -m644 APPIMAGE_RUNTIME_LICENSE.txt "$docdir/APPIMAGE_RUNTIME_LICENSE.txt"
mkdir -p "$docdir/THIRD_PARTY_LICENSES"
cp -a "$license_bundle/." "$docdir/THIRD_PARTY_LICENSES/"
cat > "$appdir/AppRun" <<'EOF'
#!/usr/bin/env sh
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$HERE/usr/bin/arvectum-proxy-launcher" "$@"
EOF
chmod 0755 "$appdir/AppRun"
cat > "$appdir/usr/share/applications/arvectum-proxy-launcher.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Arvectum Proxy Launcher
Comment=System proxy launcher with recovery-aware routing controls
Exec=arvectum-proxy-launcher
Icon=arvectum-proxy-launcher
Terminal=false
Categories=Network;Utility;
StartupNotify=true
EOF
ln -s usr/share/applications/arvectum-proxy-launcher.desktop "$appdir/arvectum-proxy-launcher.desktop"
ln -s usr/share/icons/hicolor/256x256/apps/arvectum-proxy-launcher.png "$appdir/arvectum-proxy-launcher.png"
ln -s arvectum-proxy-launcher.png "$appdir/.DirIcon"
out="$out_dir/Arvectum_Proxy_Launcher-${version}-x86_64.AppImage"
rm -f "$out"
ARCH=x86_64 VERSION="$version" APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --runtime-file "$runtime" "$appdir" "$out"
chmod 0755 "$out"
echo "APL-LNX-008: AppImage embeds the pinned type-2 runtime notice and promoted-package third-party notices." >&2
echo "$out"
