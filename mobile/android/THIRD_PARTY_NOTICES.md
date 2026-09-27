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


## libXray / Xray-core

- Project: `XTLS/libXray`
- Pinned version: `v26.9.9`
- License: MIT
- Source: https://github.com/XTLS/libXray/tree/v26.9.9
- Android release asset: `libxray-android.zip`
- Expected SHA-256: `4998a8b56e4a78a164b5359d5690036f83da3b575465cea57ddf29c0149c345f`
- Bundled core compatibility: Xray-core `v26.9.9`

The Android build fetches the official libXray release archive, verifies the
pinned SHA-256, and installs only the AAR required at compile/package time.
The fetched AAR is not committed to this repository.

libXray is isolated behind Arvectum's managed transport runtime. Manual
HTTP/HTTPS/SOCKS profiles continue to use the existing tun2proxy path.
