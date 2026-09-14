#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

artifact="${1:-dist/Arvectum Proxy Launcher}"
out_dir="${2:-dist/rpm}"

[[ "$(uname -s)" == "Linux" ]] || { echo "APL-REG-001C: RPM packaging is Linux-only" >&2; exit 2; }
for cmd in rpmbuild rpm install python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required tool: $cmd" >&2; exit 2; }
done
[[ -x "$artifact" ]] || { echo "Missing executable Linux application artifact: $artifact" >&2; exit 2; }

version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([._+~][A-Za-z0-9._+~]+)?$ ]] || {
  echo "VERSION is not RPM-compatible: $version" >&2
  exit 2
}
package="arvectum-proxy-launcher"
arch="${RPM_ARCH:-$(rpm --eval '%{_arch}')}"
[[ "$arch" == "x86_64" ]] || { echo "APL-REG-001C: current RED OS acceptance package is x86_64-only (got $arch)" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
topdir="$work/rpmbuild"
license_bundle="$work/THIRD_PARTY_LICENSES"
mkdir -p "$topdir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "$out_dir"

python3 tools/third_party_license_bundle.py --build --output "$license_bundle"
python3 tools/third_party_license_bundle.py --verify --output "$license_bundle"

payload="$work/payload"
install -Dm755 "$artifact" "$payload/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher"
install -Dm644 assets/arvectum-icon-0.2.2-transparent.png \
  "$payload/usr/share/icons/hicolor/256x256/apps/arvectum-proxy-launcher.png"
install -Dm644 LICENSE "$payload/usr/share/doc/$package/LICENSE.txt"
install -Dm644 THIRD_PARTY_NOTICES.txt "$payload/usr/share/doc/$package/THIRD_PARTY_NOTICES.txt"
mkdir -p "$payload/usr/share/doc/$package/THIRD_PARTY_LICENSES" "$payload/usr/bin" "$payload/usr/share/applications"
cp -a "$license_bundle/." "$payload/usr/share/doc/$package/THIRD_PARTY_LICENSES/"

cat > "$payload/usr/bin/arvectum-proxy-launcher" <<'WRAPPER'
#!/usr/bin/env sh
exec "/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher" "$@"
WRAPPER
chmod 0755 "$payload/usr/bin/arvectum-proxy-launcher"

cat > "$payload/usr/share/applications/arvectum-proxy-launcher.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Arvectum Proxy Launcher
Comment=System proxy launcher with recovery-aware routing controls
Exec=arvectum-proxy-launcher
Icon=arvectum-proxy-launcher
Terminal=false
Categories=Network;Utility;
StartupNotify=true
DESKTOP
chmod 0644 "$payload/usr/share/applications/arvectum-proxy-launcher.desktop"

payload_tar="$topdir/SOURCES/${package}-${version}-payload.tar"
(
  cd "$payload"
  tar --sort=name --mtime="@${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || echo 0)}" \
      --owner=0 --group=0 --numeric-owner -cf "$payload_tar" .
)

spec="$topdir/SPECS/$package.spec"
cat > "$spec" <<SPEC
Name:           $package
Version:        $version
Release:        1%{?dist}
Summary:        Arvectum Proxy Launcher
License:        MIT
BuildArch:      $arch
Requires:       NetworkManager
Source0:        %{name}-%{version}-payload.tar

%global debug_package %{nil}
%global __strip /bin/true
%global __os_install_post %{nil}

%description
Cross-platform system proxy launcher with explicit ownership, rollback and
privacy-bounded diagnostics. The Linux runtime uses NetworkManager/nmcli.

%prep
%setup -q -c -T

%build
# Prebuilt governed Linux artifact; no compilation occurs in RPM assembly.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
tar -xf %{SOURCE0} -C %{buildroot}

%files
%license /usr/share/doc/$package/LICENSE.txt
%doc /usr/share/doc/$package/THIRD_PARTY_NOTICES.txt
%doc /usr/share/doc/$package/THIRD_PARTY_LICENSES
"/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher"
/usr/bin/arvectum-proxy-launcher
/usr/share/applications/arvectum-proxy-launcher.desktop
/usr/share/icons/hicolor/256x256/apps/arvectum-proxy-launcher.png

%changelog
* Mon Sep 14 2026 Arvectum <build@localhost> - $version-1
- Initial governed RPM packaging for RED OS acceptance preparation.
SPEC

export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || echo 0)}"
rpmbuild --define "_topdir $topdir" --define "_buildhost arvectum-reproducible" -bb "$spec"

rpm_path="$(find "$topdir/RPMS" -type f -name "${package}-${version}-1*.${arch}.rpm" -print -quit)"
[[ -n "$rpm_path" && -f "$rpm_path" ]] || { echo "RPM output not found" >&2; exit 2; }
out="$out_dir/$(basename "$rpm_path")"
cp -f "$rpm_path" "$out"
printf '%s\n' "$out"
