"""Hermetic hash/structure tamper tests for future Apple Xray integration."""
import hashlib
import importlib.util
import json
from pathlib import Path
import stat
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "mobile/ios/Tools/verify_xray_apple_provenance.py"
spec = importlib.util.spec_from_file_location("xray_pinned_provenance", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

REQUIRED = [
    "libxray-apple-cgo/LibXray.xcframework/ios-arm64/libXray.a",
    "libxray-apple-cgo/LibXray.xcframework/ios-arm64_x86_64-simulator/libXray.a",
]
CORE = "v1.260327.1-0.20261109052709-676eaf66f8f0"


def fixtures(tmp_path):
    asset = tmp_path / "libxray-apple-cgo.zip"
    with zipfile.ZipFile(asset, "w") as archive:
        for name in REQUIRED:
            archive.writestr(name, b"static-lib-placeholder")
    go_mod = tmp_path / "go.mod"
    deps = "".join(f"\n example.com/repo/pkg{i} v1.0.0" for i in range(30))
    go_mod.write_text("module github.com/xtls/libxray\nrequire (" +
                      "\n github.com/xtls/xray-core " + CORE +
                      deps + "\n)\n", encoding="utf-8")
    pin = tmp_path / "pin.json"
    settings = {
        "asset": asset.name,
        "sha256": hashlib.sha256(asset.read_bytes()).hexdigest(),
        "go_mod_sha256": hashlib.sha256(go_mod.read_bytes()).hexdigest(),
        "required_archive_members": REQUIRED,
        "xray_core_module": "github.com/xtls/xray-core",
        "xray_core_version": CORE,
        "tag": "v26.11.9",
        "tag_commit": "fake-only-test",
    }
    pin.write_text(json.dumps(settings))
    return asset, go_mod, pin


def test_hermetic_pinned_asset_and_modules(tmp_path):
    asset, go_mod, pin = fixtures(tmp_path)
    result = module.verify(asset, go_mod, pin)
    assert result["declared_go_modules"] == 31
    assert result["archive_members"] == 2


def test_asset_tamper_fails_closed(tmp_path):
    asset, go_mod, pin = fixtures(tmp_path)
    asset.write_bytes(asset.read_bytes() + b"tampering")
    import pytest
    with pytest.raises(ValueError, match="digest"):
        module.verify(asset, go_mod, pin)


def test_go_mod_tamper_fails_closed(tmp_path):
    asset, go_mod, pin = fixtures(tmp_path)
    go_mod.write_text(go_mod.read_text() + "\nreplace github.com/xtls/xray-core => ./bad\n")
    import pytest
    with pytest.raises(ValueError, match="go.mod digest"):
        module.verify(asset, go_mod, pin)


def test_zip_path_traversal_fails_after_resigned_fixture(tmp_path):
    asset, go_mod, pin = fixtures(tmp_path)
    with zipfile.ZipFile(asset, "a") as archive:
        archive.writestr("../escape", b"bad")
    data = json.loads(pin.read_text())
    data["sha256"] = hashlib.sha256(asset.read_bytes()).hexdigest()
    pin.write_text(json.dumps(data))
    import pytest
    with pytest.raises(ValueError, match="unsafe archive member"):
        module.verify(asset, go_mod, pin)


def test_zip_symlink_fails_after_resigned_fixture(tmp_path):
    asset, go_mod, pin = fixtures(tmp_path)
    with zipfile.ZipFile(asset, "a") as archive:
        info = zipfile.ZipInfo("libxray-apple-cgo/link")
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive.writestr(info, "target")
    data = json.loads(pin.read_text())
    data["sha256"] = hashlib.sha256(asset.read_bytes()).hexdigest()
    pin.write_text(json.dumps(data))
    import pytest
    with pytest.raises(ValueError, match="symlink"):
        module.verify(asset, go_mod, pin)


def test_actual_release_pin_does_not_embed_binary_or_enable_vpn():
    settings = json.loads(module.PIN.read_text())
    assert settings["repository"] == "XTLS/libXray"
    assert len(settings["sha256"]) == 64
    assert settings["tag"] == "v26.11.9"
    project = (ROOT / "mobile/ios/project.yml").read_text()
    assert "LibXray.xcframework" not in project
    assert "APL_XRAY_LAB" not in project
