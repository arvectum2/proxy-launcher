# APL-LNX-008 — AppImage portable package

Status: implemented, CI-verifiable, and admitted to the generic release pipeline for the next release after v0.2.9. The immutable v0.2.9 release is not modified.

The AppImage is built from the same frozen Linux application used by the Debian package. The package creates a standards-shaped AppDir with `AppRun`, one desktop entry, a matching icon and `.DirIcon`, then invokes a hash-pinned `appimagetool` with an explicitly supplied hash-pinned type-2 runtime.

## Supply-chain boundary

`tools/appimage-toolchain.lock` records the exact appimagetool version, source/runtime provenance and SHA-256 digests. `tools/fetch_appimage_toolchain.sh` is the only network-fetch step. `tools/build_linux_appimage.sh` performs no network download and refuses a tool/runtime whose digest does not match the lock.

These are build-only dependencies; they are not required on the end-user host and are recorded for APL-IP-002-LNX. The AppImage embeds `APPIMAGE_RUNTIME_LICENSE.txt`, copied from the exact pinned upstream type-2 runtime license notice, plus the product `THIRD_PARTY_NOTICES.txt` and third-party license bundle. The pinned runtime source commit remains recorded in `tools/appimage-toolchain.lock`.

## Safety boundary

The AppImage contains application files only. Packaging does not invoke `sudo`, PolicyKit or NetworkManager, does not change proxy state, and does not create or remove user configuration/autostart/recovery state.

## Acceptance

- [x] Standard AppDir structure with `AppRun`, desktop entry and icon.
- [x] Portable x86_64 AppImage output versioned from repository `VERSION`.
- [x] appimagetool and runtime are explicit build-only dependencies with SHA-256 verification.
- [x] Build does not rely on an implicit latest runtime download.
- [x] CI extracts and inspects the image without FUSE.
- [x] Packaging cannot mutate proxy or user state.
- [x] Real graphical Linux baseline is already covered by the completed Astra Gate R8 application acceptance; AppImage CI additionally verifies its own extracted package structure.
- [x] Generic tagged-release publication reuses the exact successful main AppImage artifact and adds it to `SHA256SUMS.txt`.

## Release scope

`v0.2.9` remains immutable and does not gain a retroactive AppImage asset. AppImage publication starts with the next product release whose tagged commit has green exact-main AppImage CI. DEB remains the preferred Astra package and RPM remains the preferred RED OS package; AppImage is the portable generic Linux option.
