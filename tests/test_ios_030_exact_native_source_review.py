import hashlib
import io
from pathlib import Path
import sys
import tarfile
import zipfile
import pytest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"mobile/ios/Tools"))
from stage_exact_native_review import compare_graphs,regularize_rust

def test_graph_requires_exact_package_and_module_identity():
    a={"m":{"Module":{"Path":"x","Version":"1","Sum":"h","Replace":{"Path":"local","Version":"v"}}}}
    assert compare_graphs(a,a)==1
    for b in ({},dict(a,n={}),{"m":{"Module":{"Path":"x","Version":"1","Sum":"bad","Replace":{"Path":"local","Version":"v"}}}},{"m":{"Module":{"Path":"x","Version":"1","Sum":"h","Replace":{"Path":"other"}}}}):
        with pytest.raises(ValueError):compare_graphs(a,b)

def make_tar(path,extra=None,link=".gitignore"):
    with tarfile.open(path,"w:gz") as t:
        data=b"target/\n";m=tarfile.TarInfo(".gitignore");m.size=len(data);t.addfile(m,io.BytesIO(data))
        m=tarfile.TarInfo(".dockerignore");m.type=tarfile.SYMTYPE;m.linkname=link;t.addfile(m)
        if extra:
            m=tarfile.TarInfo(extra);m.size=0;t.addfile(m,io.BytesIO())
    return {".gitignore":hashlib.sha256(data).hexdigest()}

def test_archive_only_exact_members_and_known_link(tmp_path):
    src=tmp_path/"a.tar.gz";dst=tmp_path/"out.zip";expected=make_tar(src)
    assert regularize_rust(src,expected,dst)==1
    with zipfile.ZipFile(dst) as z:assert z.read(".dockerignore")==z.read(".gitignore")
    with pytest.raises(FileExistsError):regularize_rust(src,expected,dst)
    for i,(extra,link) in enumerate((("../escape",".gitignore"),(".gitignore",".gitignore"),("unexpected",".gitignore"),(None,"/etc/passwd"))):
        bad=tmp_path/f"bad{i}.tar.gz";make_tar(bad,extra,link)
        with pytest.raises(ValueError):regularize_rust(bad,expected,tmp_path/f"bad{i}.zip")
    with pytest.raises(ValueError):regularize_rust(src,{".gitignore":"0"*64},tmp_path/"mismatch.zip")
