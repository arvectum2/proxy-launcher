# AppImage runtime licensing and source provenance

This directory is the repository-owned notice set for the **distributed AppImage type-2 runtime**. It supplements the common Python/Tcl/Tk/PyInstaller bundle.

The exact runtime binary is controlled by `tools/appimage-toolchain.lock` through its SHA-256 and exact `AppImage/type2-runtime` source commit. The upstream runtime source at that commit statically links musl libc, libfuse, squashfuse, zstd, zlib and mimalloc. The upstream runtime `LICENSE` lists the first five families; Arvectum additionally records **mimalloc** because the exact runtime Makefile links `-lmimalloc`.

The checked-in texts are complete license/copyright notices used by the AppImage distribution gate. For permissive libraries, their presence is a notice-delivery control and does not claim that the notice-source tag is an independently proven binary package version. The distributed runtime identity remains its pinned SHA-256.

For the LGPL/libfuse static-link path, every promoted AppImage must be accompanied from the same release location by the exact type2-runtime source commit, the exact libfuse 3.15.0 source archive, the exact squashfuse 0.5.2 source archive, and `appimage-toolchain.lock`.

`tools/fetch_appimage_compliance_sources.sh` fetches/verifies those inputs and `tools/build_appimage_compliance_source.sh` creates the deterministic companion archive. `tools/appimage_runtime_compliance.py` builds and verifies the license manifest embedded inside the AppImage.

This is an engineering compliance control, not a legal opinion or a substitute for authorized legal review.
