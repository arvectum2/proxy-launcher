"""Importer safety, edit-state guard and offline import plan without Apple writes."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

FILE = Path(__file__).resolve().parents[1] / 'mobile/ios/ASO/import_appstore.py'
spec = importlib.util.spec_from_file_location('apl_ios_aso_import', FILE)
imp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(imp)

class ImportContractTests(unittest.TestCase):
    def test_offline_plan_has_47_locales_and_requires_no_apple_credentials(self):
        self.assertEqual(47, len(imp.load_rows()))
        self.assertEqual(0, imp.main([]))

    def test_executing_requires_explicit_matching_version(self):
        with self.assertRaises(SystemExit) as err:
            imp.main(['--execute', '--version', '0.1.40'])
        self.assertEqual(2, err.exception.code)
        with self.assertRaises(SystemExit) as err:
            imp.main(['--execute', '--version','0.1.40','--confirm-version','0.1.41'])
        self.assertEqual(2, err.exception.code)

    def test_waiting_for_review_fails_closed(self):
        for blocked in ['WAITING_FOR_REVIEW','IN_REVIEW','READY_FOR_SALE','PENDING_DEVELOPER_RELEASE']:
            obj={'attributes': {'versionString':'0.1.40','appStoreState':blocked}}
            with self.assertRaises(imp.ImportErrorASC):
                imp.assert_editable(obj)
        imp.assert_editable({'attributes': {'versionString':'0.1.41','appStoreState':'PREPARE_FOR_SUBMISSION'}})

    def test_fake_apple_api_waiting_for_review_makes_no_writes(self):
        calls=[]
        class FakeApple:
            def list(self,path):
                calls.append(('GET',path))
                if '/appStoreVersions?' in path:
                    return [{'id':'version41','attributes':{'platform':'IOS','versionString':'0.1.41','appStoreState':'PREPARE_FOR_SUBMISSION'}}, {'id':'version40','attributes':{'platform':'IOS','versionString':'0.1.40','appStoreState':'WAITING_FOR_REVIEW'}}]
                if '/appStoreVersionLocalizations?' in path:
                    return [{'id':'r','attributes':{'locale':'ru'}},{'id':'e','attributes':{'locale':'en-US'}}]
                raise AssertionError(path)
            def call(self,*args):
                calls.append(args)
                raise AssertionError('No API writes or further requests should happen')
        with patch.object(imp,'ASC',FakeApple):
            with self.assertRaises(imp.ImportErrorASC):
                imp.main(['--execute','--version','0.1.41','--confirm-version','0.1.41'])
        self.assertEqual(['GET','GET','GET'],[c[0] for c in calls])

    def test_screenshot_reservation_uses_apple_required_md5_and_upload_blocks(self):
        uploads=[]
        class FakeApple:
            def call(self,method,path,body=None):
                uploads.append((method,path,body))
                if method=='POST':
                    return {'data': {'id':'reserved','attributes':{'uploadOperations':[]}}}
                return {'data':{'id':'reserved'}}
        img=imp.ROOT/'screenshots'/'en-US'/'01-first-connection.jpg'
        with patch.object(imp,'upload_image', wraps=imp.upload_image):
            ident=imp.upload_image(FakeApple(),'fake-set',img)
        self.assertEqual('reserved',ident)
        self.assertEqual(['POST','PATCH'],[x[0] for x in uploads])
        self.assertEqual('appScreenshots',uploads[0][2]['data']['type'])
        self.assertTrue(uploads[1][2]['data']['attributes']['uploaded'])
        self.assertEqual(32,len(uploads[1][2]['data']['attributes']['sourceFileChecksum']))

if __name__=='__main__':
    unittest.main()
