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
SPLIT_DNS_PATCH = ROOT.parent / "ios" / "Tools" / "tun2proxy-split-dns.patch"
CLOSE_WAIT_PATCH = ROOT / "Tools" / "tun2proxy-closewait-halfclose.patch"
FLOW_INTENT_PATCH = ROOT.parent / "ios" / "Tools" / "tun2proxy-flow-intent.patch"
SCOPED_DIRECT_PATCH = ROOT.parent / "ios" / "Tools" / "tun2proxy-experimental-scoped-direct.patch"
SAME_FLOW_RETRY_PATCH = ROOT.parent / "ios" / "Tools" / "tun2proxy-sameflow-scoped-retry.patch"
DIRECT_FAMILY_PATCH = ROOT.parent / "ios" / "Tools" / "tun2proxy-dual-stack-physical-family.patch"
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
        Path("/Applications/Xcode-27.0.0.app/Contents/Developer"),
        Path("/Applications/Xcode-26.6.0.app/Contents/Developer"),
        Path("/Applications/Xcode.app/Contents/Developer"),
    ]
    for candidate in candidates:
        if (candidate / "usr/bin/xcodebuild").is_file():
            return str(candidate)
    raise SystemExit("Full Xcode is required")

def install_flow_event_header(headers: Path) -> None:
    """Expose the added pinned Rust C ABI consistently across device/sim."""
    header = headers / "tun2proxy.h"
    value = header.read_text(encoding="utf-8")
    signature = "void tun2proxy_set_flow_event_callback("
    if signature not in value:
        anchor = "int tun2proxy_stop(void);"
        if value.count(anchor) != 1:
            raise SystemExit("tun2proxy public header anchor changed")
        value = value.replace(anchor, anchor + "\n\n" +
            "/* 0=CONNECT_OK, 1=TIMEOUT, 2=REFUSED, 3=OTHER, 4=UPSTREAM_DOWN */\n" +
            "void tun2proxy_set_flow_event_callback(\n" +
            "    void (*callback)(const char *host, uint64_t connection_id, int32_t event, void *ctx),\n" +
            "    void *ctx);", 1)
    signature = "int32_t tun2proxy_set_direct_exact_host("
    if signature not in value:
        value = value.replace("void tun2proxy_set_flow_event_callback(",
            "/* Experimental only: 5=DIRECT_FAIL, 6=DIRECT_TCP, 7=SAME_FLOW_RECOVERED. */\n"
            "int32_t tun2proxy_set_direct_exact_host(const char *host, bool enable);\n\n"
            "void tun2proxy_set_flow_event_callback(", 1)
    header.write_text(value, encoding="utf-8")



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
        # The upstream API implicitly drops Tokio's runtime after block_on.
        # Runtime::drop waits indefinitely for blocking workers; during active
        # HTTP keep-alive sessions this could stall NE engine shutdown forever.
        # Bound worker draining while allowing a fresh runtime to start.
        shutdown_anchor = "    let res = match res {"
        if text.count(shutdown_anchor) != 1:
            raise SystemExit("tun2proxy Tokio shutdown anchor mismatch")
        text = text.replace(FORCED_EXIT_BLOCK, PATCHED_BLOCK, 1)
        text = text.replace(shutdown_anchor,
            "    rt.shutdown_timeout(std::time::Duration::from_secs(2));\n\n" + shutdown_anchor, 1)
        stop_anchor = "        let ret = general_run_async(args_clone, tun_mtu, packet_information, shutdown_token).await;"
        if text.count(stop_anchor) != 1:
            raise SystemExit("tun2proxy cancellation anchor mismatch")
        bounded_stop = """        let stop_watch = shutdown_token.clone();
        let ret = tokio::select! {
            result = general_run_async(args_clone, tun_mtu, packet_information, shutdown_token) => result,
            _ = async {
                stop_watch.cancelled().await;
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            } => Err(std::io::Error::other("tun2proxy stopped with pending sessions")),
        };"""
        text = text.replace(stop_anchor, bounded_stop, 1)
        general_api.write_text(text, encoding="utf-8")

        # Exact-domain real-IP DNS responses must match Network Extension
        # excludedRoutes; keep default virtual DNS for all other hosts.
        run("git", "apply", "--check", str(SPLIT_DNS_PATCH), cwd=source, env=env)
        run("git", "apply", str(SPLIT_DNS_PATCH), cwd=source, env=env)
        # On upstream FIN, do not wait forever for a virtual client to FIN.
        # Keep the Smart3 flow callbacks and per-host intent already called
        # from the shared Swift PacketTunnelMac sources; prior Catalyst
        # native fetch omitted them and could not link current app sources.
        for patch in (FLOW_INTENT_PATCH, SCOPED_DIRECT_PATCH,
                      SAME_FLOW_RETRY_PATCH, DIRECT_FAMILY_PATCH, CLOSE_WAIT_PATCH):
            run("git", "apply", "--check", str(patch), cwd=source, env=env)
            run("git", "apply", str(patch), cwd=source, env=env)

        run(cargo, f"+{RUST_TOOLCHAIN}", "build", "--release", "--locked",
            "--target", RUST_TARGET, cwd=source, env=env)
        library = CARGO_TARGET / RUST_TARGET / "release" / "libtun2proxy.a"
        if not library.is_file():
            raise SystemExit("Catalyst tun2proxy library was not produced")

        module_headers = tmpdir / "Headers"
        shutil.copytree(headers, module_headers)
        install_flow_event_header(module_headers)
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
            f"rust_target={RUST_TARGET}\npatch=bounded-tokio-shutdown-full-smart3-flow-stack-and-bounded-tcp-halfclose\n"
            f"rust_toolchain={RUST_TOOLCHAIN}\npatched_library_sha256={sha}\n",
            encoding="utf-8",
        )
        print(f"Installed {TARGET.relative_to(REPO)}")
        print(f"Catalyst library SHA-256: {sha}")

if __name__ == "__main__":
    main()
