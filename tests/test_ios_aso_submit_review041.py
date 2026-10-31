"""Fail-closed App Store review submission; no privacy or published version edits."""
import sys
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]/'mobile/ios/ASO'
sys.path.insert(0,str(ROOT))
import import_appstore as asc
import submit_review_041 as submit

class AppleReviewReleaseSafetyTests(unittest.TestCase):
    def test_explicit_version_confirmation_required(self):
        for argv in (['--submit'], ['--submit','--confirm-version','0.1.40']):
            with self.assertRaises(SystemExit) as exc:
                submit.main(argv)
            self.assertEqual(2,exc.exception.code)

    def test_draft_is_scoped_to_exact_app(self):
        api=type('API',(),{'list':lambda self,path: []})()
        self.assertIsNone(submit.existing_draft(api))
        self.assertEqual(submit.VERSION,'0.1.41')

    def test_review_submission_creates_item_then_marks_submitted(self):
        calls=[]
        version={'id':'v41','attributes':{'appStoreState':'PREPARE_FOR_SUBMISSION'}}
        class FakeAPI:
            def list(self,path):
                calls.append(('GET',path))
                if path.endswith('reviewSubmissions?limit=100'):return []
                if path.endswith('/items?limit=100'):return []
                raise AssertionError(path)
            def call(self,method,path,data=None):
                calls.append((method,path,data))
                if method=='POST' and path=='/reviewSubmissions':return {'data':{'id':'draft41','attributes':{'state':'READY_FOR_REVIEW'}}}
                if method=='POST' and path=='/reviewSubmissionItems':return {'data':{'id':'item41'}}
                if method=='PATCH' and path=='/reviewSubmissions/draft41':return {'data':{'id':'draft41','attributes':{'state':'WAITING_FOR_REVIEW'}}}
                raise AssertionError((method,path))
        api=FakeAPI()
        with patch.object(submit,'existing_version',return_value=version):
            reply=submit.send(api,version)
        self.assertEqual('WAITING_FOR_REVIEW',reply['attributes']['state'])
        post=[x for x in calls if x[0]=='POST']
        self.assertEqual(2,len(post))
        self.assertEqual('v41',post[1][2]['data']['relationships']['appStoreVersion']['data']['id'])
        patch_item=next(x for x in calls if x[0]=='PATCH')
        self.assertTrue(patch_item[2]['data']['attributes']['submitted'])
        for _,path,*_ in calls:
            self.assertNotIn('privacy',path.lower())
            self.assertNotIn('0.1.40',path)

    def test_missing_metadata_or_build_prevents_submission(self):
        class FakeAPI:
            def list(self,path):
                if '/appStoreVersions?' in path:return [{'id':'v41','attributes':{'platform':'IOS','versionString':'0.1.41','appStoreState':'PREPARE_FOR_SUBMISSION'}}]
                if '/appStoreVersionLocalizations?' in path:return []
                raise AssertionError(path)
        with self.assertRaises(asc.ImportErrorASC):submit.readiness(FakeAPI())

if __name__=='__main__':unittest.main()
