# macOS App Store v0.2.18 (build 4) — split DNS exclusions

## Functional change
- Fix exact-domain exclusions for the native Network Extension VPN.
- tun2proxy retains virtual DNS (198.18.0.0/15) for proxied domains, preserving original hostnames in upstream HTTP CONNECT.
- Exact excluded hostnames return pinned real A/AAAA records resolved before startup; these records are also excluded from the VPN's IPv4/IPv6 routes.
- Exclusions saved while connected continue to trigger automatic tunnel reconnection.
- Literal IP exclusions and the upstream proxy keep their physical bypass routes.
- Exclusion screen explains exact-host behavior, no wildcard support, and automatic reconnect.

## Verification
- Pinned Rust v0.8.3 + reproducible split-DNS patch: 5/5 Rust tests passed.
- Mac Catalyst Release build and Apple Distribution archive succeeded (including embedded Packet Tunnel).
- Signed Mac App Store installer validated by Apple's ContentDelivery/Transporter.
- PENDING live QA after TestFlight/App Store installation on MacBook:
  1. Excluded zakupki.gov.ru DNS returns real IP, route via physical en0, TLS works.
  2. Non-excluded github.com DNS remains synthetic 198.18.x.x; proxy public egress unchanged.
  3. Add/remove exclusions, automatic reconnection, proxy switching, IPv6, Wi-Fi reconnection.
  4. macOS manual HTTP/HTTPS/SOCKS/PAC settings remain disabled.

## Scope
- This release prioritises safe routing and a small exclusion-screen UX improvement.
- No third-party ad SDK; provider privacy and Mac Catalyst compatibility need separate validation.
- No automatic migration from the legacy developer app's no_proxy.txt into native App Group.
