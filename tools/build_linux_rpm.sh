#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

artifact="${1:-dist/Arvectum Proxy Launcher}"
out_dir="${2:-dist/rpm}"
license_bundle_source="${3:-}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "APL-REG-001C: RPM packaging is Linux-only" >&2
  exit 2
fi
for cmd in rpmbuild install python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required tool: $cmd" >&2; exit 2; }
done
[[ -f "$artifact" ]] || { echo "Missing Linux application artifact: $artifact" >&2; exit 2; }

version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9._+-]+)?$ ]] || {
  echo "VERSION is not RPM-package compatible: $version" >&2
  exit 2
}
arch="${RPM_ARCH:-$(uname -m)}"
[[ "$arch" == "x86_64" ]] || { echo "Unsupported RPM architecture for APL-REG-001C: $arch" >&2; exit 2; }
package="arvectum-proxy-launcher"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/rpmbuild/BUILD" "$work/rpmbuild/BUILDROOT" "$work/rpmbuild/RPMS" \
  "$work/rpmbuild/SOURCES" "$work/rpmbuild/SPECS" "$work/rpmbuild/SRPMS" "$out_dir"

license_bundle="$work/THIRD_PARTY_LICENSES"
if [[ -n "$license_bundle_source" ]]; then
  [[ -d "$license_bundle_source" ]] || { echo "Missing supplied third-party license bundle: $license_bundle_source" >&2; exit 2; }
  python3 tools/third_party_license_bundle.py --verify --output "$license_bundle_source"
  cp -a "$license_bundle_source" "$license_bundle"
else
  python3 tools/third_party_license_bundle.py --build --output "$license_bundle"
  python3 tools/third_party_license_bundle.py --verify --output "$license_bundle"
fi

install -m755 "$artifact" "$work/rpmbuild/SOURCES/Arvectum Proxy Launcher"
install -m644 assets/arvectum-icon-0.2.2-transparent.png "$work/rpmbuild/SOURCES/arvectum-proxy-launcher.png"
install -m644 LICENSE "$work/rpmbuild/SOURCES/LICENSE"
install -m644 THIRD_PARTY_NOTICES.txt "$work/rpmbuild/SOURCES/THIRD_PARTY_NOTICES.txt"
cp -a "$license_bundle" "$work/rpmbuild/SOURCES/THIRD_PARTY_LICENSES"

cat > "$work/rpmbuild/SPECS/$package.spec" <<'SPEC'
%global debug_package %{nil}
%global __arch_install_post %{nil}
%global __os_install_post %{nil}
%global __check_files %{nil}
Name:           arvectum-proxy-launcher
Version:        __VERSION__
Release:        1.redos8
Summary:        Arvectum Proxy Launcher
License:        MIT
URL:            https://github.com/arvectum2/proxy-launcher
BuildArch:      x86_64
Requires:       NetworkManager
Requires:       glib2
AutoReqProv:    no

%description
Cross-platform system proxy launcher with explicit ownership, rollback and
diagnostics boundaries. RED OS integration uses NetworkManager/nmcli and the
supported desktop system-proxy settings plane when available.

%install
rm -rf %{buildroot}
install -Dm755 "%{_sourcedir}/Arvectum Proxy Launcher" "%{buildroot}/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher"
install -Dm644 "%{_sourcedir}/arvectum-proxy-launcher.png" "%{buildroot}/usr/share/icons/hicolor/256x256/apps/arvectum-proxy-launcher.png"
install -Dm644 "%{_sourcedir}/LICENSE" "%{buildroot}/usr/share/doc/%{name}/LICENSE"
install -Dm644 "%{_sourcedir}/THIRD_PARTY_NOTICES.txt" "%{buildroot}/usr/share/doc/%{name}/THIRD_PARTY_NOTICES.txt"
mkdir -p "%{buildroot}/usr/share/doc/%{name}/THIRD_PARTY_LICENSES"
cp -a "%{_sourcedir}/THIRD_PARTY_LICENSES/." "%{buildroot}/usr/share/doc/%{name}/THIRD_PARTY_LICENSES/"
mkdir -p "%{buildroot}/usr/bin" "%{buildroot}/usr/share/applications"
cat > "%{buildroot}/usr/bin/arvectum-proxy-launcher" <<'EOF'
#!/usr/bin/env sh
exec "/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher" "$@"
EOF
chmod 0755 "%{buildroot}/usr/bin/arvectum-proxy-launcher"
cat > "%{buildroot}/usr/share/applications/arvectum-proxy-launcher.desktop" <<'EOF'
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
chmod 0644 "%{buildroot}/usr/share/applications/arvectum-proxy-launcher.desktop"

%files
%defattr(-,root,root,-)
/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher
/usr/bin/arvectum-proxy-launcher
/usr/share/applications/arvectum-proxy-launcher.desktop
/usr/share/icons/hicolor/256x256/apps/arvectum-proxy-launcher.png
/usr/share/doc/%{name}/LICENSE
/usr/share/doc/%{name}/THIRD_PARTY_NOTICES.txt
/usr/share/doc/%{name}/THIRD_PARTY_LICENSES
SPEC
sed -i "s/__VERSION__/$version/g" "$work/rpmbuild/SPECS/$package.spec"

export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || echo 0)}"
rpmbuild -bb \
  --define "_topdir $work/rpmbuild" \
  --define "_buildhost redos-build" \
  --define "_source_filedigest_algorithm 8" \
  --define "_binary_filedigest_algorithm 8" \
  --target "$arch" \
  "$work/rpmbuild/SPECS/$package.spec"

built="$(find "$work/rpmbuild/RPMS/$arch" -maxdepth 1 -type f -name "$package-$version-1.redos8.$arch.rpm" -print -quit)"
[[ -n "$built" && -f "$built" ]] || { echo "RPM build completed without the expected package" >&2; exit 2; }
out="$out_dir/$(basename "$built")"
cp -f "$built" "$out"
echo "$out"
