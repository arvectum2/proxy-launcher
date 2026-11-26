import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile

import importlib.util as _pytest_import_util
import unittest as _pytest_unittest

# These fixtures run in the dedicated iOS pytest CI lane, not unittest-only Windows builds.
if _pytest_import_util.find_spec("pytest") is None:
    raise _pytest_unittest.SkipTest("pytest-only iOS contract; run the iOS pytest CI lane")
import pytest

SCRIPT=Path(__file__).resolve().parents[1]/'mobile/ios/Tools/export_rust_notice_gap_evidence.py'
spec=importlib.util.spec_from_file_location('rust_notice_gap',SCRIPT)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


def fixtures(tmp_path):
    cache=tmp_path/'cache';cache.mkdir();lock=tmp_path/'Cargo.lock';rows=[]
    header=b'// Version 2, December 2004\r\n// Copyleft fixture\r\n// 0. You just DO WHAT fixture\r\n'
    for name,(version,license_id) in m.EXPECTED.items():
        stem=f'{name}-{version}';archive=cache/(stem+'.crate')
        files={'Cargo.toml':f'[package]\nname="{name}"\nversion="{version}"\nlicense="{license_id}"\n'.encode(),'.cargo_vcs_info.json':json.dumps({'git':{'sha1':'a'*40}}).encode(),'src/lib.rs':(header if name=='tun' else b'')+b'pub fn fixture() {}\n'}
        with tarfile.open(archive,'w:gz') as t:
            for path,raw in files.items():
                member=tarfile.TarInfo(stem+'/'+path);member.size=len(raw);t.addfile(member,io.BytesIO(raw))
        rows.append(f'[[package]]\nname="{name}"\nversion="{version}"\nsource="registry+https://github.com/rust-lang/crates.io-index"\nchecksum="{hashlib.sha256(archive.read_bytes()).hexdigest()}"\n')
    lock.write_text('\n'.join(rows));return cache,lock,header


def test_original_header_bytes_preserved_not_invented_mit(tmp_path):
    cache,lock,header=fixtures(tmp_path);out=tmp_path/'out';result=m.collect(cache,out,lock)
    assert result['release_authorized'] is False
    assert result['unresolved_original_text']==['tproxy-config@7.0.9']
    assert (out/'tun-0.8.14/LICENSE-HEADER.original.txt').read_bytes()==header
    assert not list((out/'tproxy-config-7.0.9').glob('LICENSE*'))
    with pytest.raises(ValueError,match='output exists'):m.collect(cache,out,lock)


def test_tampered_archive_fails_without_publishing_bundle(tmp_path):
    cache,lock,_=fixtures(tmp_path);(cache/'tproxy-config-7.0.9.crate').write_bytes(b'corrupt');out=tmp_path/'out'
    with pytest.raises(ValueError,match='locked crate digest mismatch'):m.collect(cache,out,lock)
    assert not out.exists()
