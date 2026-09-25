# APL-MAC-004 — macOS `.app` packaging

Status: implemented with dual-architecture cloud packaging, closed real-host APL-MAC-008 acceptance, and an active exact-main Developer ID/notarization production-promotion lane.

The canonical app bundle is produced by `tools/build_macos_app.sh` from `proxy_gui.py` using the frozen build lock and canonical `.icns` asset. Bundle identity is `ru.arvectum.proxylauncher`. Packaging is non-privileged and does not invoke `networksetup` mutations.

CI uses explicit macOS 15 arm64 and Intel runner labels, Python 3.12, runs the macOS unit/contract suite, validates `Info.plist`, and captures codesign inspection as evidence. Cloud/PR artifacts remain ad-hoc QA inputs. Production promotion is a separate exact-main gate on an Arvectum-controlled Mac: the app is re-sealed with `Developer ID Application: LLC ARVECTUM (VML75VY94V)`, Hardened Runtime and secure timestamp, then the DMG is signed, notarized with the canonical Arvectum Release Bot, stapled and Gatekeeper-verified before release eligibility.

- [x] deterministic `.app` bundle name and identifier;
- [x] canonical transparent macOS squircle icon/resources bundled (arvectum.icns + arvectum-icon-macos.png);
- [x] `CFBundleShortVersionString` and `CFBundleVersion` are bound to the numeric core of canonical `VERSION` before the final signing seal;
- [x] icon artwork uses macOS system-icon optical occupancy (~80.5% of the 1024px canvas) rather than filling the canvas edge-to-edge;
- [x] arm64 and x64 build lanes;
- [x] plist validation and signing-state inspection;
- [x] packaging contract tests;
- [x] production Developer ID signing/notarization lane implemented for exact-main promotion;
- [x] real GUI launch / physical acceptance — APL-MAC-008.
