# APL-MAC-004 — macOS `.app` packaging

Status: implemented with dual-architecture GitHub-hosted CI; real host launch acceptance remains APL-MAC-008.

The canonical app bundle is produced by `tools/build_macos_app.sh` from `proxy_gui.py` using the frozen build lock and canonical `.icns` asset. Bundle identity is `ru.arvectum.proxylauncher`. Packaging is non-privileged and does not invoke `networksetup` mutations.

CI uses explicit macOS 15 arm64 and Intel runner labels, Python 3.12, runs the macOS unit/contract suite, validates `Info.plist`, and captures codesign inspection as evidence. After governed product/license resources are embedded, the builder re-seals the final bundle with an ad-hoc signature and requires strict `codesign` verification so local/CI artifacts are internally valid. Production signing/notarization is not silently claimed by this task.

- [x] deterministic `.app` bundle name and identifier;
- [x] canonical icon/resources bundled;
- [x] arm64 and x64 build lanes;
- [x] plist validation and signing-state inspection;
- [x] packaging contract tests;
- [ ] production identity signing/notarization, if chosen for international distribution — separate release debt;
- [ ] real GUI launch — APL-MAC-008.
