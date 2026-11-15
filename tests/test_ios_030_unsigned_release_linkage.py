import hashlib
import importlib.util
from pathlib import Path
import subprocess

import pytest

SCRIPT=Path(__file__).resolve().parents[1]/'mobile/ios/Tools/audit_unsigned_release_linkage.py'
spec=importlib.util.spec_from_file_location('release_linkage',SCRIPT)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


def test_link_map_header_bound_to_artifact_and_bytes_after_section_are_opaque(tmp_path):
    exe=tmp_path/'App';exe.write_bytes(b'fixture');receipt=tmp_path/'map'
    receipt.write_bytes(f'# Path: {exe}\n# Arch: arm64\n# Object files:\n[  0] linker synthesized\n[  1] /fixture/lib.a(x.o)\n# Sections:\n'.encode()+b'\xff')
    assert m.link_objects(receipt,exe)==['linker synthesized','/fixture/lib.a(x.o)']
    with pytest.raises(ValueError,match='identity'):m.link_objects(receipt,tmp_path/'Other')
    receipt.write_bytes(receipt.read_bytes().replace(b'arm64',b'x86_64'))
    with pytest.raises(ValueError,match='identity'):m.link_objects(receipt,exe)


def test_preserves_actual_git_notice_bytes_and_rejects_dirty_checkout(tmp_path):
    checkout=tmp_path/'checkout';checkout.mkdir();out=tmp_path/'out';out.mkdir()
    def git(*args):return subprocess.check_output(['git','-C',str(checkout),*args])
    git('init','-q');git('config','user.email','fixture@example.invalid');git('config','user.name','Fixture');git('config','commit.gpgsign','false')
    raw=b'original fixture\r\n';(checkout/'LICENSE.txt').write_bytes(raw);(checkout/'README.md').write_text('not a notice')
    git('add','.');git('commit','-qm','fixture');rev=git('rev-parse','HEAD').decode().strip()
    pin={'identity':'fixture','state':{'revision':rev}};rows=m.collect_notices(checkout,pin,out)
    assert len(rows)==1 and (out/rows[0]['path']).read_bytes()==raw
    assert rows[0]['sha256']==hashlib.sha256(raw).hexdigest()
    (checkout/'LICENSE.txt').write_bytes(b'changed')
    with pytest.raises(ValueError,match='checkout drift'):m.collect_notices(checkout,pin,out)
