#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import plistlib
import os
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile
from pathlib import Path

VERSION = "v0.8.3"
SOURCE_COMMIT = "e271de19683937f23d3f8f0eb4df0a61fc4a6e50"
RUST_TOOLCHAIN = "1.98.1"
ARCHIVE_SHA256 = "7f09f01a11fef6d57477df8c32ad3d86ea7fa98ba3aa60099680785ca637ecfd"
URL = f"https://github.com/tun2proxy/tun2proxy/releases/download/{VERSION}/tun2proxy-aarch64-apple-ios-xcframework.zip"
REPOSITORY = "https://github.com/tun2proxy/tun2proxy.git"

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(__file__).resolve().parent
TARGET = ROOT / "Frameworks" / "tun2proxy.xcframework"
LOCKFILE = TOOLS / "tun2proxy-v0.8.3.Cargo.lock"
SPLIT_DNS_PATCH = TOOLS / "tun2proxy-split-dns.patch"

FORCED_EXIT_BLOCK = """        // Spawn a std thread to force exit after timeout so it isn't cancelled
        // when the tokio runtime is dropped.
        let _h = std::thread::spawn(move || {
            // Delay some seconds then try to exit current process if not exited yet, normally this case should not happen
            std::thread::sleep(crate::FORCE_EXIT_TIMEOUT);
            log::info!(\"Forcing exit now.\");
            std::process::exit(-1);
        });
"""

PATCHED_BLOCK = """        // Arvectum iOS patch: library/API callers may stop and restart
        // tun2proxy inside a long-lived Packet Tunnel process. The upstream
        // forced-exit watchdog is appropriate for process-style execution but
        // would terminate the Network Extension two seconds after every live
        // proxy switch.
"""


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def run(*args: str, cwd: Path | None = None, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        args,
        cwd=cwd,
        env=env,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.stdout:
        print(result.stdout, end="", flush=True)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, args, output=result.stdout)
    return result.stdout


def cargo_path() -> str:
    found = shutil.which("cargo")
    if found:
        return found
    fallback = Path.home() / ".cargo" / "bin" / "cargo"
    if fallback.is_file():
        return str(fallback)
    raise SystemExit("cargo is required to build patched tun2proxy")


def rustup_path() -> str:
    found = shutil.which("rustup")
    if found:
        return found
    fallback = Path.home() / ".cargo" / "bin" / "rustup"
    if fallback.is_file():
        return str(fallback)
    raise SystemExit("rustup is required to build patched tun2proxy")


def developer_dir() -> str:
    configured = os.environ.get("DEVELOPER_DIR")
    if configured:
        candidate = Path(configured)
        if (candidate / "usr" / "bin" / "xcodebuild").is_file():
            return str(candidate)

    candidates = [Path("/Applications/Xcode.app/Contents/Developer")]
    candidates.extend(
        sorted(
            Path("/Applications").glob("Xcode*.app/Contents/Developer"),
            reverse=True,
        )
    )
    for candidate in candidates:
        if (candidate / "usr" / "bin" / "xcodebuild").is_file():
            return str(candidate)
    raise SystemExit("A full Xcode installation is required to link tun2proxy for iOS")


def build_patched_libraries(tmpdir: Path, *, include_simulator: bool = False) -> dict[str, Path]:
    source = tmpdir / "source"
    run("git", "clone", "--depth", "1", "--branch", VERSION, REPOSITORY, str(source))
    actual_commit = run("git", "rev-parse", "HEAD", cwd=source).strip()
    if actual_commit != SOURCE_COMMIT:
        raise SystemExit(
            f"tun2proxy source mismatch: expected {SOURCE_COMMIT}, got {actual_commit}"
        )

    shutil.copy2(LOCKFILE, source / "Cargo.lock")
    general_api = source / "src" / "general_api.rs"
    text = general_api.read_text(encoding="utf-8")
    if text.count(FORCED_EXIT_BLOCK) != 1:
        raise SystemExit("tun2proxy forced-exit patch anchor mismatch")
    general_api.write_text(
        text.replace(FORCED_EXIT_BLOCK, PATCHED_BLOCK, 1),
        encoding="utf-8",
    )

    run("git", "apply", "--check", str(SPLIT_DNS_PATCH), cwd=source)
    run("git", "apply", str(SPLIT_DNS_PATCH), cwd=source)

    rustup = rustup_path()
    run(rustup, "toolchain", "install", RUST_TOOLCHAIN, "--profile", "minimal")
    run(rustup, "target", "add", "aarch64-apple-ios", "--toolchain", RUST_TOOLCHAIN)
    if include_simulator:
        run(rustup, "target", "add", "aarch64-apple-ios-sim", "--toolchain", RUST_TOOLCHAIN)

    cargo = cargo_path()
    env = os.environ.copy()
    cargo_home_bin = str(Path.home() / ".cargo" / "bin")
    env["PATH"] = cargo_home_bin + os.pathsep + env.get("PATH", "")
    env["DEVELOPER_DIR"] = developer_dir()
    print(f"Using DEVELOPER_DIR={env['DEVELOPER_DIR']}")
    result: dict[str, Path] = {}
    for target in (["aarch64-apple-ios", "aarch64-apple-ios-sim"] if include_simulator
                   else ["aarch64-apple-ios"]):
        run(
            cargo,
            f"+{RUST_TOOLCHAIN}",
            "build",
            "--release",
            "--locked",
            "--target",
            target,
            cwd=source,
            env=env,
        )
        library = source / "target" / target / "release" / "libtun2proxy.a"
        if not library.is_file():
            raise SystemExit(f"Patched tun2proxy library for {target} was not produced")
        result[target] = library
    return result


def add_simulator_slice(framework: Path, library: Path) -> None:
    """Attach a *patched*, source-pinned ARM64 simulator slice for UI-target CI.

    The official downloaded v0.8.3 archive only has an iPhoneOS slice.
    Reusing that slice for the simulator fails to link or load on macOS.
    """
    device_headers = framework / "ios-arm64" / "Headers"
    simulator = framework / "ios-arm64-simulator"
    simulator.mkdir(parents=True, exist_ok=True)
    shutil.copytree(device_headers, simulator / "Headers", dirs_exist_ok=True)
    shutil.copy2(library, simulator / "libtun2proxy.a")
    with (framework / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    info["AvailableLibraries"] = [
        item for item in info["AvailableLibraries"]
        if item.get("LibraryIdentifier") != "ios-arm64-simulator"
    ] + [{
        "BinaryPath": "libtun2proxy.a",
        "HeadersPath": "Headers",
        "LibraryIdentifier": "ios-arm64-simulator",
        "LibraryPath": "libtun2proxy.a",
        "SupportedArchitectures": ["arm64"],
        "SupportedPlatform": "ios",
        "SupportedPlatformVariant": "simulator",
    }]
    with (framework / "Info.plist").open("wb") as stream:
        plistlib.dump(info, stream)
    (simulator / "Headers" / "module.modulemap").write_text(
        'module tun2proxy {\n    header "tun2proxy.h"\n    export *\n}\n',
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Build source-pinned, locally patched tun2proxy for iOS")
    parser.add_argument("--with-simulator", action="store_true",
                        help="Also build patched ARM64 iOS Simulator slice for UI tests")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="apl-ios-tun2proxy-") as tmp:
        tmpdir = Path(tmp)
        archive = tmpdir / "tun2proxy.zip"
        print(f"Fetching tun2proxy {VERSION} iOS XCFramework layout...")
        with urllib.request.urlopen(URL, timeout=120) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
        actual = digest(archive)
        if actual != ARCHIVE_SHA256:
            raise SystemExit(
                f"tun2proxy archive SHA-256 mismatch: expected {ARCHIVE_SHA256}, got {actual}"
            )

        extract = tmpdir / "extract"
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(extract)
        source_framework = extract / "tun2proxy.xcframework"
        upstream_library = source_framework / "ios-arm64" / "libtun2proxy.a"
        if not upstream_library.is_file():
            raise SystemExit("Unexpected tun2proxy iOS archive layout")

        patched_libraries = build_patched_libraries(tmpdir, include_simulator=args.with_simulator)
        shutil.copy2(patched_libraries["aarch64-apple-ios"], upstream_library)
        patched_sha256 = digest(upstream_library)
        if args.with_simulator:
            add_simulator_slice(source_framework, patched_libraries["aarch64-apple-ios-sim"])

        shutil.rmtree(TARGET, ignore_errors=True)
        TARGET.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source_framework, TARGET)

        headers = TARGET / "ios-arm64" / "Headers"
        (headers / "module.modulemap").write_text(
            'module tun2proxy {\n    header "tun2proxy.h"\n    export *\n}\n',
            encoding="utf-8",
        )

        (TARGET.parent / ".tun2proxy-version").write_text(
            f"{VERSION}\n"
            f"source_commit={SOURCE_COMMIT}\n"
            f"upstream_archive_sha256={ARCHIVE_SHA256}\n"
            f"patch=disable-api-forced-exit-and-exact-host-split-dns\n"
            f"rust_toolchain={RUST_TOOLCHAIN}\n"
            f"patched_library_sha256={patched_sha256}\n"
            + (f"patched_simulator_library_sha256={digest(TARGET / 'ios-arm64-simulator' / 'libtun2proxy.a')}\n"
               if args.with_simulator else ""),
            encoding="utf-8",
        )
        print(f"Installed patched {TARGET.relative_to(ROOT)}")
        print(f"Patched library SHA-256: {patched_sha256}")


if __name__ == "__main__":
    main()
