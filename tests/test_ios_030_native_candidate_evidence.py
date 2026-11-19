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


def test_supplemental_notice_receipt_preserves_historical_missing_set(tmp_path):
    lock=SCRIPT.with_name('tun2proxy-v0.8.3.Cargo.lock')
    rows=[]
    for name,version,status in [('tun','0.8.14','original_source_header_preserved'),('tproxy-config','7.0.9','declared_only_original_text_missing')]:
        folder=tmp_path/name;folder.mkdir();archive=folder/'original.crate';archive.write_bytes(b'fixture')
        files=[]
        if name=='tun':
            notice=folder/'LICENSE-HEADER.original.txt';notice.write_bytes(b'original header')
            files.append({'file':str(notice.relative_to(tmp_path)),'sha256':hashlib.sha256(notice.read_bytes()).hexdigest()})
        rows.append({'name':name,'version':version,'notice_status':status,'archive':str(archive.relative_to(tmp_path)),'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'files':files})
    manifest={'schema':1,'release_authorized':False,'lock_sha256':hashlib.sha256(lock.read_bytes()).hexdigest(),'components':rows,'unresolved_original_text':['tproxy-config@7.0.9']}
    path=tmp_path/'manifest.json';path.write_text(json.dumps(manifest));pin={'path':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    missing=['tun@0.8.14','tproxy-config@7.0.9']
    assert m.audit_rust_supplement(tmp_path,pin,missing)['unresolved_original_text']==['tproxy-config@7.0.9']
    with pytest.raises(ValueError,match='declaration drift'):m.audit_rust_supplement(tmp_path,pin,missing[:1])
    (tmp_path/'tun'/'LICENSE-HEADER.original.txt').write_bytes(b'modified')
    with pytest.raises(ValueError,match='digest mismatch'):m.audit_rust_supplement(tmp_path,pin,missing)
