"""Validate real iPhone ASO screenshots using only the Python standard library.

This suite is also discovered by Windows and Linux offline/portable CI where Pillow
is intentionally not installed, so importing PIL would break unrelated builds.
"""
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'mobile/ios/ASO'


def _jpeg_info(path):
    """Return (width, height, components) from a well-framed JPEG SOF segment."""
    data = path.read_bytes()
    assert data.startswith(b'\xff\xd8') and data.endswith(b'\xff\xd9'), path
    offset = 2
    while offset + 4 <= len(data):
        assert data[offset] == 0xff, (path, offset)
        while data[offset] == 0xff:
            offset += 1
        marker = data[offset]
        offset += 1
        if marker in (0xd8, 0xd9, 0x01) or 0xd0 <= marker <= 0xd7:
            continue
        assert offset + 2 <= len(data), path
        length = struct.unpack_from('>H', data, offset)[0]
        assert length >= 2 and offset + length <= len(data), (path, marker)
        if marker in (0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf):
            assert length >= 8, path
            height, width, components = struct.unpack_from('>HHB', data, offset + 3)
            return width, height, components
        if marker == 0xda:
            break
        offset += length
    raise AssertionError(f'No JPEG Start-of-Frame segment in {path}')


def test_all_supported_apple_locales_have_two_opaque_real_ios_screenshots():
    entries = json.loads((ROOT / 'localizations.json').read_text(encoding='utf-8'))['localizations']
    assert len(entries) == 47
    for row in entries:
        locale = row['locale']
        folder = ROOT / 'screenshots' / locale
        assert folder.is_dir(), locale
        paths = [folder / '01-first-connection.jpg', folder / '02-local-privacy.jpg']
        for path in paths:
            assert path.is_file() and path.stat().st_size > 15000, (locale, path)
            assert _jpeg_info(path) == (1206, 2622, 3), (locale, path)
        assert paths[0].read_bytes() != paths[1].read_bytes(), locale


def test_screenshots_are_not_replaced_with_invented_product_mockups():
    metadata = json.loads((ROOT / 'localizations.json').read_text(encoding='utf-8'))['localizations']
    screenshots = set((ROOT / 'screenshots').glob('*/*.jpg'))
    assert len(screenshots) == 94
    assert {p.parent.name for p in screenshots} == {r['locale'] for r in metadata}
