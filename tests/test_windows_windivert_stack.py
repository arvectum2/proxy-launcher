import hashlib
import json

import windows_windivert_stack as stack


def _sha(data):
    return hashlib.sha256(data).hexdigest()


def _ready_fixture(tmp_path, monkeypatch):
    root = tmp_path / "WinDivert"
    root.mkdir()
    service = root / stack.SERVICE_FILENAME
    dll = root / stack.WINDIVERT_DLL_FILENAME
    driver = root / stack.WINDIVERT_DRIVER_FILENAME
    license_file = root / stack.WINDIVERT_LICENSE_FILENAME

    payloads = {
        service: b"service-fixture",
        dll: b"dll-fixture",
        driver: b"driver-fixture",
        license_file: b"license-fixture",
    }
    for path, data in payloads.items():
        path.write_bytes(data)

    monkeypatch.setattr(stack, "_is_windows", lambda: True)
    monkeypatch.setattr(stack, "install_root", lambda: str(root))
    marker = tmp_path / stack.MARKER_FILENAME
    monkeypatch.setattr(stack, "marker_path", lambda: str(marker))
    monkeypatch.setattr(
        stack, "WINDIVERT_X64_DLL_SHA256", _sha(payloads[dll])
    )
    monkeypatch.setattr(
        stack, "WINDIVERT_X64_DRIVER_SHA256", _sha(payloads[driver])
    )
    monkeypatch.setattr(
        stack, "WINDIVERT_LICENSE_SHA256", _sha(payloads[license_file])
    )

    marker_payload = {
        "schema": stack.SCHEMA,
        "version": stack.WINDIVERT_VERSION,
        "install_root": str(root),
        "service": {
            "name": stack.SERVICE_NAME,
            "filename": stack.SERVICE_FILENAME,
            "sha256": _sha(payloads[service]),
        },
        "dependency": {
            "driver_sha256": _sha(payloads[driver]),
            "dll_sha256": _sha(payloads[dll]),
            "license_sha256": _sha(payloads[license_file]),
            "driver_signer_thumbprint":
                stack.WINDIVERT_DRIVER_SIGNER_THUMBPRINT,
        },
    }
    marker.write_text(
        json.dumps(marker_payload), encoding="utf-8"
    )

    record = {
        "image_path": str(service),
        "type": 0x10,
        "start": 0x2,
        "object_name": "LocalSystem",
        "dependencies": ("BFE",),
    }
    monkeypatch.setattr(
        stack,
        "_service_registry_record",
        lambda name: dict(record),
    )
    monkeypatch.setattr(
        stack, "_service_running", lambda name: True
    )
    return root, marker, record


def test_readiness_accepts_exact_installed_stack(
    tmp_path, monkeypatch
):
    _ready_fixture(tmp_path, monkeypatch)
    result = stack.windows_windivert_stack_readiness()
    assert result["ready"] is True
    assert result["state"] == "windivert_ready"
    assert result["backend"] == "windivert"


def test_readiness_fails_closed_on_dependency_hash_mismatch(
    tmp_path, monkeypatch
):
    root, _, _ = _ready_fixture(tmp_path, monkeypatch)
    (root / stack.WINDIVERT_DLL_FILENAME).write_bytes(b"tampered")
    result = stack.windows_windivert_stack_readiness()
    assert result["ready"] is False
    assert result["state"] == "hash_mismatch"


def test_readiness_rejects_wrong_service_account(
    tmp_path, monkeypatch
):
    _, _, record = _ready_fixture(tmp_path, monkeypatch)
    record["object_name"] = r".\SomeUser"
    monkeypatch.setattr(
        stack,
        "_service_registry_record",
        lambda name: dict(record),
    )
    result = stack.windows_windivert_stack_readiness()
    assert result["ready"] is False
    assert result["state"] == "service_configuration_mismatch"


def test_readiness_requires_bfe_dependency(
    tmp_path, monkeypatch
):
    _, _, record = _ready_fixture(tmp_path, monkeypatch)
    record["dependencies"] = ()
    monkeypatch.setattr(
        stack,
        "_service_registry_record",
        lambda name: dict(record),
    )
    result = stack.windows_windivert_stack_readiness()
    assert result["ready"] is False
    assert result["state"] == "service_configuration_mismatch"


def test_readiness_requires_running_service(
    tmp_path, monkeypatch
):
    _ready_fixture(tmp_path, monkeypatch)
    monkeypatch.setattr(
        stack, "_service_running", lambda name: False
    )
    result = stack.windows_windivert_stack_readiness()
    assert result["ready"] is False
    assert result["state"] == "service_not_running"


def test_readiness_fails_when_marker_absent(
    tmp_path, monkeypatch
):
    monkeypatch.setattr(stack, "_is_windows", lambda: True)
    monkeypatch.setattr(
        stack, "marker_path", lambda: str(tmp_path / "missing.json")
    )
    result = stack.windows_windivert_stack_readiness()
    assert result["ready"] is False
    assert result["state"] == "not_installed"


def test_readiness_is_windows_only(monkeypatch):
    monkeypatch.setattr(stack, "_is_windows", lambda: False)
    result = stack.windows_windivert_stack_readiness()
    assert result["ready"] is False
    assert result["state"] == "not_windows"

