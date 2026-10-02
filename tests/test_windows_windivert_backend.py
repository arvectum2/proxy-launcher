import hashlib
import json
from pathlib import Path

import unittest

_ASSERTIONS = unittest.TestCase()

from routing_rules import ApplicationIdentity
from windows_windivert_backend import (
    WINDIVERT_DLL_FILENAME,
    WINDIVERT_DRIVER_FILENAME,
    WINDIVERT_DRIVER_SIGNER_THUMBPRINT,
    WINDIVERT_LICENSE_FILENAME,
    WINDIVERT_LICENSE_SHA256,
    WINDIVERT_X64_DLL_SHA256,
    WINDIVERT_X64_DRIVER_SHA256,
    WindowsWinDivertError,
    build_windivert_network_filter,
    build_windivert_socket_filter,
    canonical_windivert_plan_json,
    compile_windivert_application_plan,
    normalize_windows_executable_path,
    verify_windivert_bundle,
    windows_windivert_transport_scope,
)


def _identity(path=r"C:\Program Files\Example\App.exe"):
    return ApplicationIdentity(
        platform="windows",
        executable_path=path,
        display_name="Example",
    )
def test_normalize_windows_executable_path_is_case_insensitive():
    assert normalize_windows_executable_path(
        r"C:/Program Files/Example/../Example/App.EXE"
    ) == r"c:\program files\example\app.exe"


def test_normalize_windows_executable_path_rejects_non_files():
    for path in ("", "App.exe", r".\App.exe", "C:\\"):
        with _ASSERTIONS.assertRaises(WindowsWinDivertError):
            normalize_windows_executable_path(path)


def test_compile_windivert_plan_dedupes_stable_identity():
    identity = _identity()
    plans = compile_windivert_application_plan(
        (identity, identity),
        local_proxy_port=8080,
    )
    assert len(plans) == 1
    assert plans[0].executable_path == r"c:\program files\example\app.exe"
    assert plans[0].local_proxy_port == 8080
    assert plans[0].rule_id.startswith("app-exclusion-")


def test_compile_windivert_plan_rejects_non_windows_identity():
    identity = ApplicationIdentity(
        platform="linux",
        executable_path="/usr/bin/example",
    )
    with _ASSERTIONS.assertRaisesRegex(
        WindowsWinDivertError,
        "executable-backed Windows identities",
    ):
        compile_windivert_application_plan(
            (identity,),
            local_proxy_port=8080,
        )


def test_compile_windivert_plan_rejects_invalid_proxy_port():
    for port in (0, 65536, True, "nope"):
        with _ASSERTIONS.assertRaises(WindowsWinDivertError):
            compile_windivert_application_plan(
                (_identity(),),
                local_proxy_port=port,
            )


def test_canonical_plan_json_is_deterministic():
    plans = compile_windivert_application_plan(
        (
            _identity(r"C:\B\b.exe"),
            _identity(r"C:\A\a.exe"),
        ),
        local_proxy_port=8080,
    )
    first = canonical_windivert_plan_json(plans)
    second = canonical_windivert_plan_json(reversed(plans))
    assert json.loads(first)["backend"] == "windivert"
    assert first != second
    # Compiler order itself is stable regardless of input selection order.
    recomp = compile_windivert_application_plan(
        (
            _identity(r"C:\A\a.exe"),
            _identity(r"C:\B\b.exe"),
        ),
        local_proxy_port=8080,
    )
    assert first == canonical_windivert_plan_json(recomp)




def test_transport_scope_is_truthful_about_tcp_and_direct_udp():
    scope = windows_windivert_transport_scope()
    assert scope["intercepted_protocols"] == ["tcp"]
    assert scope["intercepted_path"] == "selected_app_to_local_http_proxy"
    assert scope["local_proxy_endpoint"] == "127.0.0.1"
    assert scope["external_target_families"] == ["ipv4", "ipv6"]
    assert scope["non_intercepted_protocols"] == ["udp", "quic", "dns"]
    assert scope["non_intercepted_behavior"] == "unchanged_direct"


def test_filters_limit_capture_to_loopback_proxy_translation():
    socket_filter = build_windivert_socket_filter(8080)
    network_filter = build_windivert_network_filter(8080, 49152)
    assert "loopback" in socket_filter
    assert "tcp" in socket_filter
    assert "event == CONNECT" in socket_filter
    assert "event == CLOSE" in socket_filter
    assert "remotePort == 8080" in socket_filter
    assert network_filter == (
        "loopback and tcp and ("
        "tcp.DstPort == 8080 or tcp.SrcPort == 49152)"
    )


def test_network_filter_rejects_same_proxy_and_direct_port():
    with _ASSERTIONS.assertRaisesRegex(
        WindowsWinDivertError, "must differ"
    ):
        build_windivert_network_filter(8080, 8080)
def _write_bytes_for_sha(path: Path, target_sha: str):
    # This helper is intentionally not a preimage generator. Tests monkeypatch
    # module constants to the hashes of deterministic fixture bytes instead.
    data = ("fixture:" + path.name).encode("utf-8")
    path.write_bytes(data)
    return hashlib.sha256(data).hexdigest()


def test_verify_bundle_accepts_exact_hashes_and_valid_signature(
    tmp_path,
    monkeypatch,
):
    dll = tmp_path / WINDIVERT_DLL_FILENAME
    driver = tmp_path / WINDIVERT_DRIVER_FILENAME
    license_file = tmp_path / WINDIVERT_LICENSE_FILENAME
    dll_hash = _write_bytes_for_sha(dll, WINDIVERT_X64_DLL_SHA256)
    driver_hash = _write_bytes_for_sha(driver, WINDIVERT_X64_DRIVER_SHA256)
    license_hash = _write_bytes_for_sha(license_file, WINDIVERT_LICENSE_SHA256)

    monkeypatch.setattr(
        "windows_windivert_backend.WINDIVERT_X64_DLL_SHA256",
        dll_hash,
    )
    monkeypatch.setattr(
        "windows_windivert_backend.WINDIVERT_X64_DRIVER_SHA256",
        driver_hash,
    )
    monkeypatch.setattr(
        "windows_windivert_backend.WINDIVERT_LICENSE_SHA256",
        license_hash,
    )
    result = verify_windivert_bundle(
        str(tmp_path),
        driver_signature_status="Valid",
        driver_signer_thumbprint=WINDIVERT_DRIVER_SIGNER_THUMBPRINT,
    )
    assert result["ready"] is True
    assert result["state"] == "verified"
    assert result["driver_signature_status"] == "Valid"
    assert (
        result["driver_signer_thumbprint"]
        == WINDIVERT_DRIVER_SIGNER_THUMBPRINT
    )


def test_verify_bundle_fails_closed_on_hash_mismatch(tmp_path):
    for name in (
        WINDIVERT_DLL_FILENAME,
        WINDIVERT_DRIVER_FILENAME,
        WINDIVERT_LICENSE_FILENAME,
    ):
        (tmp_path / name).write_bytes(b"wrong")
    result = verify_windivert_bundle(str(tmp_path))
    assert result["ready"] is False
    assert result["state"] == "hash_mismatch"


def test_verify_bundle_rejects_invalid_driver_signature(
    tmp_path,
    monkeypatch,
):
    for name, attr in (
        (WINDIVERT_DLL_FILENAME, "WINDIVERT_X64_DLL_SHA256"),
        (WINDIVERT_DRIVER_FILENAME, "WINDIVERT_X64_DRIVER_SHA256"),
        (WINDIVERT_LICENSE_FILENAME, "WINDIVERT_LICENSE_SHA256"),
    ):
        path = tmp_path / name
        digest = _write_bytes_for_sha(path, "")
        monkeypatch.setattr(
            f"windows_windivert_backend.{attr}",
            digest,
        )
    result = verify_windivert_bundle(
        str(tmp_path),
        driver_signature_status="NotSigned",
    )
    assert result["ready"] is False
    assert result["state"] == "driver_signature_invalid"


def test_verify_bundle_rejects_unpinned_driver_signer(
    tmp_path,
    monkeypatch,
):
    for name, attr in (
        (WINDIVERT_DLL_FILENAME, "WINDIVERT_X64_DLL_SHA256"),
        (WINDIVERT_DRIVER_FILENAME, "WINDIVERT_X64_DRIVER_SHA256"),
        (WINDIVERT_LICENSE_FILENAME, "WINDIVERT_LICENSE_SHA256"),
    ):
        path = tmp_path / name
        digest = _write_bytes_for_sha(path, "")
        monkeypatch.setattr(
            f"windows_windivert_backend.{attr}",
            digest,
        )
    result = verify_windivert_bundle(
        str(tmp_path),
        driver_signature_status="Valid",
        driver_signer_thumbprint="00" * 20,
    )
    assert result["ready"] is False
    assert result["state"] == "driver_signer_mismatch"
