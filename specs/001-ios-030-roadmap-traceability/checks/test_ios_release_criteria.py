import copy
import importlib.util
import json
import subprocess
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location("gate",ROOT/"scripts/check_ios_release_criteria.py")
gate=importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
D=ROOT/"specs/001-ios-030-roadmap-traceability"


class ReleaseCriterionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw=subprocess.check_output(["git","-C",str(ROOT),"show",gate.PIN+":"+gate.SOURCE])
        cls.base=json.loads((D/"release-criteria.json").read_text())
        cls.board=(D/"tasks.md").read_text()
    def test_valid(self):
        self.assertEqual(gate.validate(self.base,self.raw,self.board,self.raw),[])
    def test_deleted(self):
        d=copy.deepcopy(self.base);d["rows"].pop()
        self.assertTrue(gate.validate(d,self.raw,self.board,self.raw))
    def test_rewritten(self):
        d=copy.deepcopy(self.base);d["rows"][0]["source_text"]="changed"
        self.assertTrue(gate.validate(d,self.raw,self.board,self.raw))
    def test_deleted_task(self):
        b="\n".join(l for l in self.board.splitlines() if "APL-VERIFY-009" not in l)
        self.assertTrue(gate.validate(self.base,self.raw,b,self.raw))
    def test_checked_without_evidence(self):
        d=copy.deepcopy(self.base);d["rows"][0]["state"]="verified"
        b=self.board.replace("[ ] APL-VERIFY-009","[x] APL-VERIFY-009")
        self.assertTrue(any("no criterion-specific" in e for e in gate.validate(d,self.raw,b,self.raw)))
    def test_wrong_criterion(self):
        d=copy.deepcopy(self.base);r=d["rows"][0];r["state"]="verified";r["acceptance_evidence"]=[{"criterion":"APL-REL-010","outcome":"pass","source_commit":"a"*40,"artifact_sha256":"b"*64,"receipt_ref":"receipt","review_ref":"review"}]
        b=self.board.replace("[ ] APL-VERIFY-009","[x] APL-VERIFY-009")
        self.assertTrue(any("no criterion-specific" in e for e in gate.validate(d,self.raw,b,self.raw)))
    def test_release_self_authorization(self):
        d=copy.deepcopy(self.base);d["release_authorized"]=True
        self.assertTrue(gate.validate(d,self.raw,self.board,self.raw))
    def test_changed_current_source(self):
        self.assertTrue(any("current source differs" in e for e in gate.validate(self.base,self.raw,self.board,self.raw+b"\n")))
    def test_source_hash(self):
        self.assertTrue(gate.validate(self.base,self.raw+b"\n",self.board,self.raw))
