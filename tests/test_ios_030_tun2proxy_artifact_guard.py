from pathlib import Path
import hashlib
import importlib.util

import pytest

TOOL = Path(__file__).resolve().parents[1] / "mobile/ios/Tools/verify_tun2proxy_lab_artifact.py"
spec = importlib.util.spec_from_file_location("artifact_guard", TOOL)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def fixture(tmp_path, content=b"synthetic compiled bytes", stamp=True):
    framework = tmp_path / "tun2proxy.xcframework"
    lib = framework / "ios-arm64-simulator/libtun2proxy.a"
    lib.parent.mkdir(parents=True)
    lib.write_bytes(content)
    digest = hashlib.sha256(content).hexdigest()
    if stamp:
        (tmp_path / ".tun2proxy-version").write_text(
            f"{guard.VERSION}\nsource_commit={guard.COMMIT}\n"
            f"upstream_archive_sha256={guard.UPSTREAM}\nrust_toolchain={guard.TOOLCHAIN}\n"
            f"patch=disable-api-forced-exit-and-split-dns\npatched_simulator_library_sha256={digest}\n"
        )
    return framework, lib, digest


def test_matching_local_metadata_and_digest(tmp_path):
    root, _, digest = fixture(tmp_path)
    assert guard.verify(root, "ios-arm64-simulator") == digest


def test_forced_exit_literal_fails_even_with_matching_stamp(tmp_path):
    root, _, _ = fixture(tmp_path, b"prefix" + guard.FORCED_EXIT + b"suffix")
    with pytest.raises(ValueError, match="unsafe forced-exit"):
        guard.verify(root, "ios-arm64-simulator")


def test_missing_stamp_rejected(tmp_path):
    root, _, _ = fixture(tmp_path, stamp=False)
    with pytest.raises(ValueError, match="manifest missing"):
        guard.verify(root, "ios-arm64-simulator")


def test_digest_mismatch_rejected(tmp_path):
    root, library, _ = fixture(tmp_path)
    library.write_bytes(b"substituted")
    with pytest.raises(ValueError, match="sha256 mismatch"):
        guard.verify(root, "ios-arm64-simulator")


def test_connected_udp_fix_uses_conn_bound_datagrams_and_fetcher_applies_it():
    root = Path(__file__).resolve().parents[1] / "mobile/ios/Tools"
    patch = (root / "tun2proxy-connected-udp.patch").read_text()
    assert "+async fn create_udp_stream(" in patch and "Result<UdpSocket>" in patch
    assert "+                    if udp_server.send(&s5_udp_data).await?" in patch
    assert "+            len = udp_server.recv(&mut buf2)" in patch
    assert "-                    udp_server.write_all(&s5_udp_data).await?;" in patch
    fetch = (root / "fetch_tun2proxy.py").read_text()
    assert "CONNECTED_UDP_PATCH" in fetch and "sameflow-retry-connected-udp" in fetch
    assert "--require-connected-udp" in (root / "run_xray_vless_config_simulator_qa.sh").read_text()


def test_udp_lab_refuses_pre_fix_rust_manifest(tmp_path):
    root, _, digest = fixture(tmp_path)
    with pytest.raises(ValueError, match="connected UDP patch flag missing"):
        guard.verify(root, "ios-arm64-simulator", require_connected_udp=True)
    stamp = root.parent / ".tun2proxy-version"
    stamp.write_text(stamp.read_text().replace("split-dns\n", "split-dns-connected-udp\n"))
    assert guard.verify(root, "ios-arm64-simulator", require_connected_udp=True) == digest
