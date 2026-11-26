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

## ZXing Core

- Project: zxing/zxing; artifact com.google.zxing:core:3.5.4
- Source: https://github.com/zxing/zxing/tree/zxing-3.5.4
- License: Apache-2.0; upstream LICENSE and NOTICE shipped in assets/licenses/zxing/
- Maven Central JAR SHA-256: 71de5d89341b5fcf5dd89da7f44e84d825d0e084cdf3ec77c9abe26b0f0ceb13
- Upstream Maven SHA-1 verified: 955fcd6bcd0723ddfb8ee6ed502d5fdf0e9676a9
- Local-only QR image decoding; no camera, upload or additional runtime permission.
