#!/usr/bin/env python3
from __future__ import annotations
import hashlib, os, shutil, subprocess, tempfile, urllib.request, zipfile
from pathlib import Path

VERSION = "v0.8.3"
SOURCE_COMMIT = "e271de19683937f23d3f8f0eb4df0a61fc4a6e50"
RUST_TOOLCHAIN = "1.98.1"
ARCHIVE_SHA256 = "7f09f01a11fef6d57477df8c32ad3d86ea7fa98ba3aa60099680785ca637ecfd"
URL = f"https://github.com/tun2proxy/tun2proxy/releases/download/{VERSION}/tun2proxy-aarch64-apple-ios-xcframework.zip"
REPOSITORY = "https://github.com/tun2proxy/tun2proxy.git"
ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
TARGET = ROOT / "Frameworks" / "tun2proxy.xcframework"
LOCKFILE = Path(__file__).resolve().parent / "tun2proxy-v0.8.3.Cargo.lock"
CARGO_TARGET = REPO / "build" / "tun2proxy-maccatalyst"
RUST_TARGET = "aarch64-apple-ios-macabi"

FORCED_EXIT_BLOCK = """        // Spawn a std thread to force exit after timeout so it isn't cancelled
        // when the tokio runtime is dropped.
        let _h = std::thread::spawn(move || {
            // Delay some seconds then try to exit current process if not exited yet, normally this case should not happen
            std::thread::sleep(crate::FORCE_EXIT_TIMEOUT);
            log::info!(\"Forcing exit now.\");
            std::process::exit(-1);
        });
"""
PATCHED_BLOCK = """        // Arvectum Apple Network Extension patch: API callers may stop and restart
        // tun2proxy inside a long-lived Packet Tunnel process.
"""

def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def run(*args: str, cwd: Path | None = None, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(args, cwd=cwd, env=env, check=False, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.stdout:
        print(result.stdout, end="", flush=True)
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, args, output=result.stdout)
    return result.stdout

def tool(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    fallback = Path.home() / ".cargo" / "bin" / name
    if fallback.is_file():
        return str(fallback)
    raise SystemExit(f"{name} is required")

def developer_dir() -> str:
    configured = os.environ.get("DEVELOPER_DIR")
    candidates = ([Path(configured)] if configured else []) + [
        Path("/Applications/Xcode-26.6.0.app/Contents/Developer"),
        Path("/Applications/Xcode.app/Contents/Developer"),
    ]
    for candidate in candidates:
        if (candidate / "usr/bin/xcodebuild").is_file():
            return str(candidate)
    raise SystemExit("Full Xcode is required")

def main() -> None:
    env = os.environ.copy()
    env["DEVELOPER_DIR"] = developer_dir()
    env["PATH"] = str(Path.home()/".cargo/bin") + os.pathsep + env.get("PATH", "")
    env["CARGO_TARGET_DIR"] = str(CARGO_TARGET)
    rustup = tool("rustup")
    cargo = tool("cargo")
    run(rustup, "toolchain", "install", RUST_TOOLCHAIN, "--profile", "minimal", env=env)
    run(rustup, "target", "add", RUST_TARGET, "--toolchain", RUST_TOOLCHAIN, env=env)

    with tempfile.TemporaryDirectory(prefix="apl-maccatalyst-tun2proxy-") as tmp:
        tmpdir = Path(tmp)
        archive = tmpdir / "upstream.zip"
        with urllib.request.urlopen(URL, timeout=120) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
        if digest(archive) != ARCHIVE_SHA256:
            raise SystemExit("tun2proxy upstream archive SHA-256 mismatch")
        extract = tmpdir / "extract"
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(extract)
        headers = extract / "tun2proxy.xcframework" / "ios-arm64" / "Headers"
        if not headers.is_dir():
            raise SystemExit("Unexpected upstream XCFramework layout")

        source = tmpdir / "source"
        run("git", "clone", "--depth", "1", "--branch", VERSION, REPOSITORY, str(source), env=env)
        actual = run("git", "rev-parse", "HEAD", cwd=source, env=env).strip()
        if actual != SOURCE_COMMIT:
            raise SystemExit(f"tun2proxy source mismatch: {actual}")
        shutil.copy2(LOCKFILE, source / "Cargo.lock")
        general_api = source / "src/general_api.rs"
        text = general_api.read_text(encoding="utf-8")
        if text.count(FORCED_EXIT_BLOCK) != 1:
            raise SystemExit("tun2proxy forced-exit patch anchor mismatch")
        general_api.write_text(text.replace(FORCED_EXIT_BLOCK, PATCHED_BLOCK, 1), encoding="utf-8")

        run(cargo, f"+{RUST_TOOLCHAIN}", "build", "--release", "--locked",
            "--target", RUST_TARGET, cwd=source, env=env)
        library = CARGO_TARGET / RUST_TARGET / "release" / "libtun2proxy.a"
        if not library.is_file():
            raise SystemExit("Catalyst tun2proxy library was not produced")

        module_headers = tmpdir / "Headers"
        shutil.copytree(headers, module_headers)
        (module_headers / "module.modulemap").write_text(
            'module tun2proxy {\n    header "tun2proxy.h"\n    export *\n}\n',
            encoding="utf-8",
        )
        shutil.rmtree(TARGET, ignore_errors=True)
        TARGET.parent.mkdir(parents=True, exist_ok=True)
        run(
            str(Path(env["DEVELOPER_DIR"]) / "usr/bin/xcodebuild"),
            "-create-xcframework",
            "-library", str(library),
            "-headers", str(module_headers),
            "-output", str(TARGET),
            env=env,
        )
        info = TARGET / "Info.plist"
        run("/usr/bin/plutil", "-lint", str(info), env=env)
        sha = digest(library)
        (TARGET.parent / ".tun2proxy-version").write_text(
            f"{VERSION}\nsource_commit={SOURCE_COMMIT}\n"
            f"upstream_archive_sha256={ARCHIVE_SHA256}\n"
            f"rust_target={RUST_TARGET}\npatch=disable-api-forced-exit-for-network-extension-live-restart\n"
            f"rust_toolchain={RUST_TOOLCHAIN}\npatched_library_sha256={sha}\n",
            encoding="utf-8",
        )
        print(f"Installed {TARGET.relative_to(REPO)}")
        print(f"Catalyst library SHA-256: {sha}")

if __name__ == "__main__":
    main()
