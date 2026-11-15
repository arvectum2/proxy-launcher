#!/bin/bash
# Offline, no signing, device, network or preference operations.
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/apl-native-network-settings.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
sources=("$root"/SharedCore/{NativeTunnelRoutePlan,NativeWireGuardRuntimeConfig,TransportBackendContract,WGQuickConfigurationPreview,ProxyModel,ManagedProfileContract}.swift "$root/Shared/NativeTunnelNetworkSettings.swift" "$root/Tools/NativeNetworkSettingsValidation.swift")
xcrun --sdk macosx swiftc -framework NetworkExtension "${sources[@]}" -o "$work/validate"
"$work/validate"
xcrun --sdk iphoneos swiftc -target arm64-apple-ios15.0 -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" -typecheck "${sources[@]}"
echo NATIVE_NETWORK_SETTINGS_IPHONEOS_TYPECHECK_PASS
