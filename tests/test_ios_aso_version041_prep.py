"""Future 0.1.41 staging must leave live 0.1.40 unchanged."""
import hashlib
import importlib.util
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import Mock

ASO = Path(__file__).resolve().parents[1]/'mobile/ios/ASO'
sys.path.insert(0,str(ASO))
import import_appstore as imp
import prepare_version_041 as nxt
import build_release_041 as builder


def version(name,state,ident=None):
    return {'id':ident or name,'attributes':{'platform':'IOS','versionString':name,'appStoreState':state,
                                            'copyright':'2026 LLC ARVECTUM','releaseType':'AFTER_APPROVAL'}}


class NextReleaseTests(unittest.TestCase):
    def test_does_not_create_during_active_040_review(self):
        with self.assertRaises(imp.ImportErrorASC):
            nxt.guard_create([version('0.1.40','WAITING_FOR_REVIEW')])
        with self.assertRaises(imp.ImportErrorASC):
            nxt.guard_create([version('0.1.40','IN_REVIEW')])

    def test_can_create_after_release_but_never_duplicates(self):
        self.assertEqual((None,'CAN_CREATE'),nxt.guard_create([version('0.1.40','READY_FOR_SALE')]))
        self.assertEqual(('next','EXISTS'),nxt.guard_create([version('0.1.40','READY_FOR_SALE'),version('0.1.41','PREPARE_FOR_SUBMISSION','next')]))

    def test_new_version_request_preserves_previous_release_policy(self):
        request=nxt.build_payload(version('0.1.40','READY_FOR_SALE'))['data']
        self.assertEqual('appStoreVersions',request['type'])
        self.assertEqual('IOS',request['attributes']['platform'])
        self.assertEqual('0.1.41',request['attributes']['versionString'])
        self.assertEqual('AFTER_APPROVAL',request['attributes']['releaseType'])
        self.assertEqual('2026 LLC ARVECTUM',request['attributes']['copyright'])
        self.assertEqual(imp.APP_ID,request['relationships']['app']['data']['id'])
        self.assertNotIn('usesIdfa',request['attributes'])

    def test_isolated_candidate_version_does_not_modify_source(self):
        with TemporaryDirectory() as root:
            root=Path(root)
            src=root/'source'; src.mkdir()
            target=root/'stage';fw=root/'framework';fw.mkdir()
            (fw/'Info.plist').write_text('framework')
            spec='MARKETING_VERSION: "0.1.39"\nCURRENT_PROJECT_VERSION: "43"\n'
            (src/'project.yml').write_text(spec)
            builder.prepare(src,target,fw)
            self.assertEqual(spec,(src/'project.yml').read_text())
            self.assertIn('MARKETING_VERSION: "0.1.41"',(target/'project.yml').read_text())
            self.assertIn('CURRENT_PROJECT_VERSION: "46"',(target/'project.yml').read_text())
            self.assertTrue((target/'Frameworks'/'tun2proxy.xcframework').is_symlink())
            with self.assertRaises(RuntimeError):builder.prepare(src,target,fw)

    def test_processing_verification_fails_closed_and_checks_md5(self):
        lang='en-US';file='01-first-connection.jpg';root=imp.ROOT/'screenshots'/lang
        def asset(name,state='COMPLETE',correct=True):
            md5=hashlib.md5((root/name).read_bytes()).hexdigest() if correct else '0'*32
            return {'id':name,'attributes':{'fileName':name,'sourceFileChecksum':md5,
                                             'assetDeliveryState':{'state':state}}}
        row=next(r for r in imp.load_rows() if r['locale']==lang)
        class FakeAPI:
            def __init__(self,state='COMPLETE',correct=True):self.state=state;self.correct=correct
            def list(self,path):
                if '/appStoreVersionLocalizations?' in path:return [{'id':'v-en','attributes':{'locale':lang}}]
                if '/appScreenshotSets?' in path:return [{'id':'s-en','attributes':{'screenshotDisplayType':imp.SCREEN_TYPE}}]
                return [asset('01-first-connection.jpg',self.state,self.correct),asset('02-local-privacy.jpg',self.state,self.correct)]
        imp.verify_asset_processing(FakeAPI(),'version41',[row])
        with self.assertRaises(imp.ImportErrorASC):imp.verify_asset_processing(FakeAPI(state='UPLOAD_COMPLETE'),'version41',[row])
        with self.assertRaises(imp.ImportErrorASC):imp.verify_asset_processing(FakeAPI(correct=False),'version41',[row])

if __name__=='__main__':unittest.main()
