import hashlib
import json

import windows_windivert_stack as stack


SOURCE_COMMIT = "a" * 40


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
        "source_commit": SOURCE_COMMIT,
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


def test_readiness_rejects_invalid_source_commit(
    tmp_path, monkeypatch
):
    _, marker, _ = _ready_fixture(tmp_path, monkeypatch)
    payload = json.loads(marker.read_text(encoding="utf-8"))
    payload["source_commit"] = "not-a-commit"
    marker.write_text(json.dumps(payload), encoding="utf-8")
    result = stack.windows_windivert_stack_readiness()
    assert result["ready"] is False
    assert result["state"] == "invalid_marker"


def test_readiness_rejects_application_source_commit_mismatch(
    tmp_path, monkeypatch
):
    _ready_fixture(tmp_path, monkeypatch)
    monkeypatch.setattr(
        stack,
        "current_application_source_commit",
        lambda: "b" * 40,
    )
    result = stack.windows_windivert_stack_readiness()
    assert result["ready"] is False
    assert result["state"] == "source_commit_mismatch"
    assert result["installed_source_commit"] == SOURCE_COMMIT
    assert result["application_source_commit"] == "b" * 40


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



def _portable_fixture(tmp_path, monkeypatch):
    app_dir = tmp_path / "portable"
    bundle = app_dir / stack.PORTABLE_BUNDLE_DIRNAME
    bundle.mkdir(parents=True)
    exe = app_dir / "Arvectum Proxy Launcher.exe"
    exe.write_bytes(b"exe")
    monkeypatch.setattr(stack, "_is_windows", lambda: True)
    monkeypatch.setattr(stack.sys, "frozen", True, raising=False)
    monkeypatch.setattr(stack.sys, "executable", str(exe))

    service = bundle / stack.SERVICE_FILENAME
    dll = bundle / stack.WINDIVERT_DLL_FILENAME
    driver = bundle / stack.WINDIVERT_DRIVER_FILENAME
    license_file = bundle / stack.WINDIVERT_LICENSE_FILENAME
    helper = bundle / stack.PORTABLE_HELPER_FILENAME
    payloads = {
        service: b"portable-service",
        dll: b"portable-dll",
        driver: b"portable-driver",
        license_file: b"portable-license",
        helper: b"portable-helper",
    }
    for path, data in payloads.items():
        path.write_bytes(data)

    monkeypatch.setattr(
        stack, "WINDIVERT_X64_DLL_SHA256", _sha(payloads[dll])
    )
    monkeypatch.setattr(
        stack, "WINDIVERT_X64_DRIVER_SHA256", _sha(payloads[driver])
    )
    monkeypatch.setattr(
        stack, "WINDIVERT_LICENSE_SHA256", _sha(payloads[license_file])
    )

    dependency = {
        "schema": "arvectum.proxy.windivert-dependency.v1",
        "version": stack.WINDIVERT_VERSION,
        "driver_signer_thumbprint":
            stack.WINDIVERT_DRIVER_SIGNER_THUMBPRINT,
        "files": {
            stack.WINDIVERT_DLL_FILENAME: _sha(payloads[dll]),
            stack.WINDIVERT_DRIVER_FILENAME: _sha(payloads[driver]),
            stack.WINDIVERT_LICENSE_FILENAME:
                _sha(payloads[license_file]),
        },
    }
    dependency_path = (
        bundle / stack.PORTABLE_DEPENDENCY_MANIFEST_FILENAME
    )
    dependency_path.write_text(
        json.dumps(dependency), encoding="utf-8"
    )
    stack_manifest = {
        "schema": "arvectum.proxy.windows-windivert-build.v1",
        "source_commit": SOURCE_COMMIT,
        "version": stack.WINDIVERT_VERSION,
        "service": {
            "filename": stack.SERVICE_FILENAME,
            "sha256": _sha(payloads[service]),
        },
        "dependency_manifest_sha256":
            _sha(dependency_path.read_bytes()),
    }
    (bundle / stack.PORTABLE_STACK_MANIFEST_FILENAME).write_text(
        json.dumps(stack_manifest), encoding="utf-8"
    )
    build_manifest = {
        "product": "Arvectum Proxy Launcher",
        "format": "portable",
        "source_commit": SOURCE_COMMIT,
        "windivert_stack_enabled": True,
        "windivert_service_helper_sha256":
            _sha(payloads[helper]),
        "windivert_dependency_manifest_sha256":
            _sha(dependency_path.read_bytes()),
        "windivert_service_sha256":
            _sha(payloads[service]),
    }
    (app_dir / stack.PORTABLE_BUILD_MANIFEST_FILENAME).write_text(
        json.dumps(build_manifest), encoding="utf-8"
    )
    return app_dir, bundle


def test_portable_bootstrap_readiness_accepts_exact_sidecar(
    tmp_path, monkeypatch
):
    _portable_fixture(tmp_path, monkeypatch)
    result = stack.portable_windivert_bootstrap_readiness()
    assert result["portable_bootstrap_available"] is True
    assert result["state"] == "portable_bootstrap_ready"
    assert result["source_commit"] == SOURCE_COMMIT


def test_portable_bootstrap_readiness_rejects_source_commit_mismatch(
    tmp_path, monkeypatch
):
    app_dir, _ = _portable_fixture(tmp_path, monkeypatch)
    manifest = app_dir / stack.PORTABLE_BUILD_MANIFEST_FILENAME
    payload = json.loads(manifest.read_text(encoding="utf-8"))
    payload["source_commit"] = "b" * 40
    manifest.write_text(json.dumps(payload), encoding="utf-8")
    result = stack.portable_windivert_bootstrap_readiness()
    assert result["portable_bootstrap_available"] is False
    assert result["state"] == "portable_payload_invalid"


def test_portable_bootstrap_readiness_rejects_tampered_driver(
    tmp_path, monkeypatch
):
    _, bundle = _portable_fixture(tmp_path, monkeypatch)
    (bundle / stack.WINDIVERT_DRIVER_FILENAME).write_bytes(b"tampered")
    result = stack.portable_windivert_bootstrap_readiness()
    assert result["portable_bootstrap_available"] is False
    assert result["state"] == "portable_dependency_hash_mismatch"


def test_portable_bootstrap_elevates_once_and_rechecks_readiness(
    tmp_path, monkeypatch
):
    _portable_fixture(tmp_path, monkeypatch)
    calls = []
    readiness = [
        {"ready": False, "state": "not_installed"},
        {"ready": True, "state": "windivert_ready"},
    ]

    monkeypatch.setattr(
        stack,
        "windows_windivert_stack_readiness",
        lambda: readiness.pop(0),
    )
    monkeypatch.setattr(
        stack,
        "_run_elevated_powershell",
        lambda args, timeout_ms=120000: calls.append(tuple(args)) or 0,
    )

    result = stack.bootstrap_windows_windivert_stack()
    assert result["ready"] is True
    assert len(calls) == 1
    args = calls[0]
    assert "-Action" in args
    assert args[args.index("-Action") + 1] == "Install"
    assert "-SourceCommit" in args
    assert args[args.index("-SourceCommit") + 1] == SOURCE_COMMIT
