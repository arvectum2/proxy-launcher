"""Integrity checks for research evidence, never production authorization."""
import hashlib
import importlib.util
import json
from pathlib import Path
import pytest

SCRIPT=Path(__file__).resolve().parents[1]/'mobile/ios/Tools/audit_native_candidate_evidence.py'
spec=importlib.util.spec_from_file_location('native_evidence',SCRIPT)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


def test_integrity_and_tamper(tmp_path):
    raw=b'original notice';path=tmp_path/'LICENSE';path.write_bytes(raw);sha=hashlib.sha256(raw).hexdigest()
    assert m.verify(tmp_path,'LICENSE',sha)==path
    path.write_bytes(b'altered notice')
    with pytest.raises(ValueError,match='digest mismatch'):m.verify(tmp_path,'LICENSE',sha)
    with pytest.raises(ValueError,match='missing file'):m.verify(tmp_path,'not-present',sha)


def test_reject_traversal_absolute_and_symlink(tmp_path):
    sha=hashlib.sha256(b'notice').hexdigest();p=tmp_path/'actual';p.write_bytes(b'notice');(tmp_path/'link').symlink_to(p)
    for name in ('../actual',str(p),'..\\actual'):
        with pytest.raises(ValueError,match='unsafe'):m.verify(tmp_path,name,sha)
    with pytest.raises(ValueError,match='symlink'):m.verify(tmp_path,'link',sha)


def test_pinned_inventory_set_and_nonrelease_boundary():
    pins=json.loads(m.PIN.read_text())
    assert set(pins['inventories'])=={'xray','mpl','awg','rust'}
    assert all(len(x['sha256'])==64 for x in pins['inventories'].values())
    assert pins['scope']=='local research evidence, not release authorization'
    assert "'release_authorized':False" in SCRIPT.read_text()
