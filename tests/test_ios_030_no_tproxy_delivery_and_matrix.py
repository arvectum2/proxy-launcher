import sys, pathlib, hashlib, json
import pytest
T=pathlib.Path(__file__).resolve().parents[1]/'mobile/ios/Tools';sys.path.insert(0,str(T))
import unified_acceptance_matrix as a
import unified_synthetic_fixture as f
import unified_split_route_fixture as s
import stage_no_tproxy_source_review as kit
from validate_unified_synthetic_receipt import Invalid

def fake(c):
    return {'id':c['id'],'runID':f.uid(),'owner':f.uid(),'challengeSHA256':f.digest(f.uid().encode()),'evidence':[f.digest(f.uid().encode()) for _ in range(4 if c['splitCase'] else 1)],'status':'split_route_receipts_correlated_only' if c['splitCase'] else 'correlated_receipt_only','candidateManifestSHA256':c['candidateManifestSHA256']}

def test_matrix_exact_new_candidates_and_no_implicit_acceptance():
    rows=a.cases();assert len(rows)==30
    assert sum(r['candidateManifestSHA256']==f.NO_TPROXY_CANDIDATE for r in rows)==22
    assert sum(r['candidateManifestSHA256']==f.NO_TPROXY_SPLIT_CANDIDATE for r in rows)==8
    assert a.summarize([])['correlated']==0
    records=[fake(c) for c in rows];r=a.summarize(records)
    assert r['correlated']==30 and not r['missing'] and r['release_authorized'] is False and r['runtime_authorized'] is False
    for field in ('id','runID','owner','challengeSHA256','evidence'):
        bad=records.copy();bad[1]=dict(bad[1],**{field:bad[0][field]})
        with pytest.raises(Invalid):a.summarize(bad)
    with pytest.raises(Invalid):a.summarize([dict(records[0],candidateManifestSHA256=f.CONTAINING_CANDIDATE)])
    with pytest.raises(Invalid):a.summarize([dict(records[0],status='PASS')])

@pytest.mark.parametrize('row',a.cases(),ids=lambda r:r['id'])
def test_each_case_generates_exact_private_fixture(row,tmp_path):
    p=tmp_path/'fixture';local=0xc0a80122 if row['kind']=='amneziaWG1' else None
    if row['splitCase']:
        m=s.write(p,row['splitCase'],row['probe'],local,no_tproxy=True)
    else:m=f.write(p,row['kind'],row['probe'],row['mode'],local,candidate=row['candidateManifestSHA256'])
    for k in ('kind','probe','mode','candidateManifestSHA256'):assert m[k]==row[k]
    assert m.get('splitCase')==row['splitCase'] and m['runtime_authorized'] is False
    assert all(x.stat().st_mode&0o777==0o600 for x in p.iterdir())
    with pytest.raises(FileExistsError):p.mkdir()

def test_missing_or_tampered_source_kit_fails(tmp_path):
    p=tmp_path/'private';p.mkdir(mode=0o700);(p/'manifest.json').write_text(json.dumps({'schema':1,'release_authorized':False,'runtime_authorized':False,'files':{}}));(p/'manifest.json').chmod(0o600)
    with pytest.raises(ValueError):kit.verify_review(p)
    src=tmp_path/'source';src.mkdir();(src/'unexpected').symlink_to('/etc/passwd')
    with pytest.raises(ValueError):kit.archive_tree(src,tmp_path/'archive.zip')
