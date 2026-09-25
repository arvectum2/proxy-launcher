#!/usr/bin/env python3
from __future__ import annotations

import hashlib
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


def build_patched_library(tmpdir: Path) -> Path:
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

    rustup = rustup_path()
    run(rustup, "toolchain", "install", RUST_TOOLCHAIN, "--profile", "minimal")
    run(rustup, "target", "add", "aarch64-apple-ios", "--toolchain", RUST_TOOLCHAIN)

    cargo = cargo_path()
    env = os.environ.copy()
    cargo_home_bin = str(Path.home() / ".cargo" / "bin")
    env["PATH"] = cargo_home_bin + os.pathsep + env.get("PATH", "")
    env["DEVELOPER_DIR"] = developer_dir()
    print(f"Using DEVELOPER_DIR={env['DEVELOPER_DIR']}")
    run(
        cargo,
        f"+{RUST_TOOLCHAIN}",
        "build",
        "--release",
        "--locked",
        "--target",
        "aarch64-apple-ios",
        cwd=source,
        env=env,
    )
    library = source / "target" / "aarch64-apple-ios" / "release" / "libtun2proxy.a"
    if not library.is_file():
        raise SystemExit("Patched tun2proxy library was not produced")
    return library


def main() -> None:
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

        patched_library = build_patched_library(tmpdir)
        shutil.copy2(patched_library, upstream_library)
        patched_sha256 = digest(upstream_library)

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
            f"patch=disable-api-forced-exit-for-ios-live-restart\n"
            f"rust_toolchain={RUST_TOOLCHAIN}\n"
            f"patched_library_sha256={patched_sha256}\n",
            encoding="utf-8",
        )
        print(f"Installed patched {TARGET.relative_to(ROOT)}")
        print(f"Patched library SHA-256: {patched_sha256}")


if __name__ == "__main__":
    main()
