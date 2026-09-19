# Arvectum Proxy Launcher for iOS — personal build

This target follows the accepted Android 0.1.19 scope and intentionally does not implement per-app routing.

## Implemented scope

- native SwiftUI iPhone client;
- multiple proxy profiles with Auto, HTTP/HTTPS CONNECT and SOCKS5 transport selection;
- credentials in the shared Keychain, profile metadata in the App Group;
- NETunnelProviderManager + NEPacketTunnelProvider;
- pinned tun2proxy v0.8.3 iOS XCFramework, fetched with SHA-256 verification;
- Auto pool ordering, health checks, failover and optional return to the primary proxy;
- exact host/IP site exclusions, up to 32 entries, using packet-tunnel excluded routes;
- pool/tunnel journal;
- version 0.1.19 / build 20.

HTTPS-proxy transport is wrapped by a local TLS relay before traffic is passed to tun2proxy, matching the Android architecture.

## Reproduce the project

Run these commands from the repository root:

    python3 mobile/ios/Tools/fetch_tun2proxy.py
    xcodegen generate --spec mobile/ios/project.yml
    open mobile/ios/ArvectumProxyLauncherIOS.xcodeproj

## Personal-device signing

A full Xcode installation and an Apple Developer team with the Network Extensions capability are required for a real-device build. Configure the same team for both ArvectumProxyLauncher and PacketTunnel; keep the existing App Group, Keychain sharing and Network Extension entitlements unchanged. With automatic signing enabled, Xcode can create/update the matching development profiles and install the app on a connected trusted iPhone.

Bundle IDs:

- ru.arvectum.proxylauncher.ios
- ru.arvectum.proxylauncher.ios.PacketTunnel

App Group:

- group.ru.arvectum.proxylauncher.ios

The repository CI deliberately builds without signing; certificates and provisioning profiles must never be committed.
