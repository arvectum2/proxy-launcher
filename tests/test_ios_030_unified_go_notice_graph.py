import importlib.util
from pathlib import Path
import pytest

p=Path(__file__).resolve().parents[1]/'mobile/ios/Tools/audit_unified_go_notices.py'
s=importlib.util.spec_from_file_location('unified_notice_graph',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)

def test_graph_only_permits_original_versions_and_awg_additions():
    old={'existing':{'Module':{'Path':'example.org/dep','Version':'v1.0.0'}},'stdlib':{}}
    awg={'Module':{'Path':m.AWG_MODULE,'Version':'v3.1.20260828'}}
    assert m.compare(old,{**old,'new':awg})==['new']
    with pytest.raises(ValueError,match='changed package'):
        m.compare(old,{**old,'existing':{'Module':{'Path':'example.org/dep','Version':'v2.0.0'}},'new':awg})
    with pytest.raises(ValueError,match='unreviewed additional'):
        m.compare(old,{**old,'new':{'Module':{'Path':'example.org/unknown','Version':'v1.0.0'}}})
    with pytest.raises(ValueError,match='removed packages'):
        m.compare(old,{'new':awg})
