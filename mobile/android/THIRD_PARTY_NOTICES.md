# Android Mobile MVP — third-party notices

## tun2proxy

- Project: `tun2proxy/tun2proxy`
- Pinned version: `v0.8.3`
- License: MIT
- Source: https://github.com/tun2proxy/tun2proxy/tree/v0.8.3
- Android release asset: `tun2proxy-android-libs.zip`
- Expected SHA-256: `50706ce2b0799295b6672cf6b72ec388d02a3104ebd1195b3a9bca10d2bd80f5`

The Android dogfood build downloads the official upstream native-library archive during CI, verifies the pinned SHA-256, and packages only the required `libtun2proxy.so` files. Native binaries are not committed to this repository.

The dependency is isolated behind Arvectum's `ProxyEngineAdapter`; product UI and stored profile semantics do not depend on tun2proxy-specific configuration.
