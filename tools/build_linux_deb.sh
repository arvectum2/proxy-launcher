#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

artifact="${1:-dist/Arvectum Proxy Launcher}"
out_dir="${2:-dist/deb}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "APL-LNX-007: .deb packaging is Linux-only" >&2
  exit 2
fi
for cmd in dpkg dpkg-deb install python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required tool: $cmd" >&2; exit 2; }
done
[[ -f "$artifact" ]] || { echo "Missing Linux application artifact: $artifact" >&2; exit 2; }

version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+~-][A-Za-z0-9.+:~-]+)?$ ]] || {
  echo "VERSION is not Debian-package compatible: $version" >&2
  exit 2
}
arch="${DEB_ARCH:-$(dpkg --print-architecture)}"
package="arvectum-proxy-launcher"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
root="$work/${package}_${version}_${arch}"
license_bundle="$work/THIRD_PARTY_LICENSES"
mkdir -p "$root/DEBIAN" "$root/usr/bin" "$root/usr/share/applications" "$out_dir"

python3 tools/third_party_license_bundle.py --build --output "$license_bundle"
python3 tools/third_party_license_bundle.py --verify --output "$license_bundle"

install -Dm755 "$artifact" "$root/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher"
install -Dm644 assets/arvectum-icon-0.2.2-transparent.png \
  "$root/usr/share/icons/hicolor/256x256/apps/arvectum-proxy-launcher.png"
install -Dm644 LICENSE "$root/usr/share/doc/$package/copyright"
install -Dm644 THIRD_PARTY_NOTICES.txt "$root/usr/share/doc/$package/THIRD_PARTY_NOTICES.txt"
mkdir -p "$root/usr/share/doc/$package/THIRD_PARTY_LICENSES"
cp -a "$license_bundle/." "$root/usr/share/doc/$package/THIRD_PARTY_LICENSES/"

cat > "$root/usr/bin/arvectum-proxy-launcher" <<'EOF'
#!/usr/bin/env sh
exec "/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher" "$@"
EOF
chmod 0755 "$root/usr/bin/arvectum-proxy-launcher"

cat > "$root/usr/share/applications/arvectum-proxy-launcher.desktop" <<'EOF'
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
chmod 0644 "$root/usr/share/applications/arvectum-proxy-launcher.desktop"

installed_size="$(du -sk "$root" | awk '{print $1}')"
cat > "$root/DEBIAN/control" <<EOF
Package: $package
Version: $version
Section: net
Priority: optional
Architecture: $arch
Maintainer: Arvectum
Installed-Size: $installed_size
Depends: network-manager, libglib2.0-bin
Description: Arvectum Proxy Launcher
 Cross-platform system proxy launcher with explicit ownership, rollback and
 diagnostics boundaries. Linux/Astra integration uses NetworkManager/nmcli and desktop GSettings PAC state.
EOF
chmod 0644 "$root/DEBIAN/control"

# Package installation must never mutate proxy state or per-user XDG state.
# Therefore APL-LNX-007 deliberately ships no maintainer scripts (postinst,
# prerm, postrm) and no system-wide autostart unit.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || echo 0)}"
out="$out_dir/${package}_${version}_${arch}.deb"
rm -f "$out"
dpkg-deb --build --root-owner-group "$root" "$out"

echo "$out"
