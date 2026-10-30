"""Release 0.1.41 staged binary upload must preserve the active 0.1.40 review."""
import hashlib
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
ASO=Path(__file__).resolve().parents[1]/'mobile/ios/ASO'
sys.path.insert(0,str(ASO))
import import_appstore as imp
import upload_release_041 as uploader

class UploadSafety(unittest.TestCase):
    def test_candidate_requires_matching_content_and_version(self):
        with TemporaryDirectory() as root:
            root=Path(root)
            ipa=root/'app.ipa';ipa.write_bytes(b'local signed IPA test stub')
            manifest={'version':'0.1.41','build':'46','ipa':str(ipa),'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),
                      'iosLocalizations':50,'packetTunnelExtensions':1}
            (root/'candidate-manifest.json').write_text(json.dumps(manifest))
            self.assertEqual(ipa,uploader.candidate(root)[1])
            ipa.write_bytes(b'corrupted')
            with self.assertRaises(imp.ImportErrorASC):uploader.candidate(root)
            ipa.write_bytes(b'local signed IPA test stub')
            manifest['build']='45';(root/'candidate-manifest.json').write_text(json.dumps(manifest))
            with self.assertRaises(imp.ImportErrorASC):uploader.candidate(root)

    def test_active_040_review_blocks_new_build_upload(self):
        class FakeAPI:
            def list(self,path):
                return [{'id':'v40','attributes':{'platform':'IOS','versionString':'0.1.40','appStoreState':'WAITING_FOR_REVIEW'}},
                        {'id':'v41','attributes':{'platform':'IOS','versionString':'0.1.41','appStoreState':'PREPARE_FOR_SUBMISSION'}}]
        with self.assertRaises(imp.ImportErrorASC):uploader.check_release(FakeAPI(),'0.1.41')

    def test_build_number_must_match_exact_ios_version(self):
        class FakeAPI:
            def __init__(self,version):self.version=version
            def list(self,path):return [{'id':'b46','attributes':{'version':'46','processingState':'VALID'}}]
            def call(self,method,path):return {'data':{'attributes':{'version':self.version}}}
        self.assertEqual('b46',uploader.find_processed_build(FakeAPI('0.1.41'))['id'])
        with self.assertRaises(imp.ImportErrorASC):uploader.find_processed_build(FakeAPI('0.1.40'))

    def test_unprocessed_build_never_attaches(self):
        class FakeAPI:
            def list(self,path):return [{'id':'b46','attributes':{'version':'46','processingState':'PROCESSING'}}]
        with self.assertRaises(imp.ImportErrorASC):uploader.find_processed_build(FakeAPI())

if __name__=='__main__':unittest.main()
