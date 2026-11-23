# Standalone iOS native WireGuard physical UDP witness

Isolated test-only iOS host, NOT built into APL and with no PacketTunnel
extension or VPN permissions. This standalone target shares only the
already-provisioned development QA application identifier
ru.arvectum.proxylauncher.lab.httpswitness. Signing and installing require
separate explicit approval; the provided project is unsigned by default.

Its only destinations are independent synthetic targets at TCP/UDP IPv4
198.51.100.77:39883 and UDP IPv6 [2001:db8:77::77]:39883.
An explicitly launched process with --apl-product-udp-only consumes one
private JSON file in its own Documents container: runID (UUID) and nonce
(40 lowercase hexadecimal characters). It issues one TCP4 control and
UDP4/UDP6 exact APL_UDP:<nonce> requests, accepting only the
APL_RECEIPT:<nonce> response. No arbitrary domain, host or private
credential input; no NetworkExtension manager access. Unprivileged app
result booleans must always be cross-checked against server counters.

Unsigned compilation (from the directory containing this README):

    xcodegen generate
    xcodebuild -project APLNativeLabUDPOnly.xcodeproj \
      -scheme NativeLabHost -configuration Release -sdk iphoneos \
      -destination 'generic/platform=iOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
      CODE_SIGNING_ALLOWED=NO build

The signed physical iPhone13 run used this EXACT Swift source and project
YAML. Private source and receipt artifacts are located locally on Mac mini:

    native-artifacts/ios-030-udp-standalone-qa-20261123/
    native-artifacts/product-physical-wg-udp-r10-standalone-20261123/

The operator verified an iPhone TCP4 app control and UDP4/UDP6 app
replies, and an independent pinned WireGuard reference server reported
tcp4=2 udp4=1 udp6=1, valid MAC1 and bidirectional transport; r10
receiver exited normally. Its single test profile was then removed, the
preexisting signed HTTPS QA host reinstalled, original native WG and three
legacy profiles preserved, legacy Основной selected and OS VPN OFF.
Do not commit private test keys, signed binaries, app device data,
Apple provisioning or temporary test nonces.
