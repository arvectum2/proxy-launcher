"""Regression checks for the product-only Go bridge source selection."""
import json
from pathlib import Path
import shutil
import sys

import importlib.util as _pytest_import_util
import unittest as _pytest_unittest

# These fixtures run in the dedicated iOS pytest CI lane, not unittest-only Windows builds.
if _pytest_import_util.find_spec("pytest") is None:
    raise _pytest_unittest.SkipTest("pytest-only iOS contract; run the iOS pytest CI lane")
import pytest

IOS=Path(__file__).resolve().parents[1]/"mobile/ios"
sys.path.insert(0,str(IOS/"Tools"))
import prepare_native_release_bridge as b

def inputs(tmp_path,monkeypatch):
    root=tmp_path/"source";root.mkdir()
    for name in ("AWGNativeLab","AWGProductRuntime"):
        shutil.copytree(IOS/"Tools"/name,root/name)
    dest=tmp_path/"bridge";dest.mkdir()
    main=dest/"main.go"
    main.write_text("package main\n//export CGoInvoke\nfunc CGoInvoke() {}\n//export CGoFree\nfunc CGoFree() {}\n")
    m={"product_awg_bridge":True,"release_authorized":False,
       "unified_bridge_sha256":{"main.go":b.sha(main.read_bytes())},
       "product_bridge_sha256":{p.name:b.sha(p.read_bytes()) for p in (root/"AWGProductRuntime").glob("*.go") if not p.name.endswith("_test.go")},
       "original_bridge_sha256":{p.name:b.sha(p.read_bytes()) for p in (root/"AWGNativeLab").glob("*.go") if not p.name.endswith("_test.go")}}
    receipt=tmp_path/"manifest.json";receipt.write_text(json.dumps(m))
    monkeypatch.setattr(b,"GO_PIN",b.sha(receipt.read_bytes()))
    return root,dest,receipt

def test_only_product_abi_and_validation_support_selected(tmp_path,monkeypatch):
    root,dest,receipt=inputs(tmp_path,monkeypatch)
    hashes=b.prepare(receipt,dest,root)
    assert set(hashes)=={"main.go","awg_product_product_bind.go","awg_product_product_bridge.go","awg_product_product_tun.go","awg_product_support.go","awg_product_validation.go"}
    text="\n".join(p.read_text() for p in dest.glob("*.go"))
    assert "type bridgePeer struct" not in text and "type scopedBind struct" not in text
    assert "func awgSyntheticCLI(" not in text and "//export aplAWGBridge" not in text
    assert "func validateProductUAPI(" in text and "type validationOnlyBind struct" in text

def test_modified_source_rejected_before_copy(tmp_path,monkeypatch):
    root,dest,receipt=inputs(tmp_path,monkeypatch)
    p=root/"AWGNativeLab"/"packet_bridge.go";p.write_text(p.read_text()+"\n// changed\n")
    with pytest.raises(ValueError,match="source mismatch"):
        b.prepare(receipt,dest,root)
    assert list(dest.glob("*.go"))==[dest/"main.go"]

def test_preexisting_bridge_rejected(tmp_path,monkeypatch):
    root,dest,receipt=inputs(tmp_path,monkeypatch)
    (dest/"unexpected.go").write_text("package main")
    with pytest.raises(ValueError,match="unexpected upstream bridge files"):
        b.prepare(receipt,dest,root)

def test_release_preparation_keeps_lab_activation_disabled():
    gate=(IOS/"PacketTunnel/NativeReleaseLinkPreparation.swift").read_text()
    assert "DEBUG || APL_NATIVE_SYNTHETIC_RUNTIME || APL_NATIVE_PRODUCT_RUNTIME_REVIEW" in gate
    assert "#error(" in gate
    assert "APL_NATIVE_RELEASE_LINK_PREPARATION" not in (IOS/"project.yml").read_text()
    provider=(IOS/"PacketTunnel/PacketTunnelProvider.swift").read_text()
    assert "APL_NATIVE_RELEASE_LINK_PREPARATION" not in provider
    assert "let validationEnabled=false" in provider
