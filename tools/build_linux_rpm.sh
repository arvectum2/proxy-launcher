#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

artifact="${1:-dist/Arvectum Proxy Launcher}"
out_dir="${2:-dist/rpm}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "APL-REG-001C: RPM packaging is Linux-only" >&2
  exit 2
fi
for cmd in rpmbuild rpm install python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required tool: $cmd" >&2; exit 2; }
done
[[ -f "$artifact" ]] || { echo "Missing Linux application artifact: $artifact" >&2; exit 2; }
# rpmbuild executes %install from its BUILD directory, so every external input
# passed as a macro must be absolute. This also preserves paths containing spaces.
artifact="$(cd "$(dirname "$artifact")" && pwd)/$(basename "$artifact")"
out_dir="$(mkdir -p "$out_dir" && cd "$out_dir" && pwd)"

version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+~-][A-Za-z0-9.+:~-]+)?$ ]] || {
  echo "VERSION is not RPM-package compatible: $version" >&2
  exit 2
}
package="arvectum-proxy-launcher"
arch="${RPM_ARCH:-x86_64}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
top="$work/rpmbuild"
license_bundle="$work/THIRD_PARTY_LICENSES"
mkdir -p "$top"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

python3 tools/third_party_license_bundle.py --build --output "$license_bundle"
python3 tools/third_party_license_bundle.py --verify --output "$license_bundle"

cat > "$work/arvectum-proxy-launcher" <<'EOF'
#!/usr/bin/env sh
exec "/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher" "$@"
EOF
chmod 0755 "$work/arvectum-proxy-launcher"

cat > "$work/arvectum-proxy-launcher.desktop" <<'EOF'
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

cat > "$top/SPECS/$package.spec" <<'EOF'
Name:           arvectum-proxy-launcher
Version:        %{_apl_version}
Release:        1%{?dist}
Summary:        Arvectum Proxy Launcher
License:        Proprietary
BuildArch:      %{_apl_arch}
Requires:       NetworkManager
Requires:       glib2
Requires:       kf5-kconfig-core
Requires:       dbus-tools
%global debug_package %{nil}
%global _build_id_links none

%description
Cross-platform system proxy launcher with explicit ownership, rollback and diagnostics boundaries. RED OS integration uses NetworkManager/nmcli plus the active desktop's governed system-proxy store, including KDE/KConfig.

%install
rm -rf %{buildroot}
install -Dm755 "%{_apl_artifact}" "%{buildroot}/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher"
install -Dm755 "%{_apl_launcher}" "%{buildroot}%{_bindir}/arvectum-proxy-launcher"
install -Dm644 "%{_apl_desktop}" "%{buildroot}%{_datadir}/applications/arvectum-proxy-launcher.desktop"
install -Dm644 "%{_apl_icon}" "%{buildroot}%{_datadir}/icons/hicolor/256x256/apps/arvectum-proxy-launcher.png"
install -Dm644 "%{_apl_license}" "%{buildroot}%{_docdir}/%{name}/LICENSE"
install -Dm644 "%{_apl_notices}" "%{buildroot}%{_docdir}/%{name}/THIRD_PARTY_NOTICES.txt"
mkdir -p "%{buildroot}%{_docdir}/%{name}/THIRD_PARTY_LICENSES"
cp -a "%{_apl_license_bundle}/." "%{buildroot}%{_docdir}/%{name}/THIRD_PARTY_LICENSES/"

%files
"/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher"
%{_bindir}/arvectum-proxy-launcher
%{_datadir}/applications/arvectum-proxy-launcher.desktop
%{_datadir}/icons/hicolor/256x256/apps/arvectum-proxy-launcher.png
%{_docdir}/%{name}/LICENSE
%{_docdir}/%{name}/THIRD_PARTY_NOTICES.txt
%{_docdir}/%{name}/THIRD_PARTY_LICENSES
EOF

export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || echo 0)}"
rpmbuild -bb "$top/SPECS/$package.spec" \
  --define "_topdir $top" \
  --define "_apl_version $version" \
  --define "_apl_arch $arch" \
  --define "_apl_artifact $artifact" \
  --define "_apl_launcher $work/arvectum-proxy-launcher" \
  --define "_apl_desktop $work/arvectum-proxy-launcher.desktop" \
  --define "_apl_icon $repo_root/assets/arvectum-icon-0.2.2-transparent.png" \
  --define "_apl_license $repo_root/LICENSE" \
  --define "_apl_notices $repo_root/THIRD_PARTY_NOTICES.txt" \
  --define "_apl_license_bundle $license_bundle"

built="$(find "$top/RPMS" -type f -name "$package-$version-*.${arch}.rpm" -print -quit)"
[[ -n "$built" ]] || { echo "RPM build did not produce an artifact" >&2; exit 2; }
out="$out_dir/Arvectum-Proxy-Launcher-${version}-redos-linux-${arch}.rpm"
cp "$built" "$out"
rpm -qip "$out" >/dev/null
rpm -qlp "$out" | grep -Fx '/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher' >/dev/null

echo "$out"
