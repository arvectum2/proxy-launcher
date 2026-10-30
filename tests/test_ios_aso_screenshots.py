"""iPhone screenshots use actual app captures at an Apple-supported pixel size."""
import json
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]/'mobile/ios/ASO'

def test_all_supported_apple_locales_have_two_opaque_real_ios_screenshots():
    entries=json.loads((ROOT/'localizations.json').read_text())['localizations']
    assert len(entries)==47
    for row in entries:
        locale=row['locale'];folder=ROOT/'screenshots'/locale
        assert folder.is_dir(),locale
        paths=[folder/'01-first-connection.jpg',folder/'02-local-privacy.jpg']
        for p in paths:
            assert p.is_file() and p.stat().st_size>15000,(locale,p)
            with Image.open(p) as im:
                assert im.format=='JPEG'
                assert im.mode=='RGB', (locale,im.mode)
                assert im.size==(1206,2622),(locale,im.size)
                im.verify()
        assert paths[0].read_bytes()!=paths[1].read_bytes(),locale

def test_screenshots_are_not_replaced_with_invented_product_mockups():
    metadata=json.loads((ROOT/'localizations.json').read_text())['localizations']
    screenshots=set((ROOT/'screenshots').glob('*/*.jpg'))
    assert len(screenshots)==94
    assert {p.parent.name for p in screenshots}=={r['locale'] for r in metadata}
