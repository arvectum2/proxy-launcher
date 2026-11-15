#!/usr/bin/env python3
"""Check the exact already-built, locally reviewed source candidate. Not an attestation."""
import hashlib
import json
from pathlib import Path
import sys

PIN = Path(__file__).with_name('xray_source_pins.json')

def verify(directory: Path, pin: Path = PIN):
    candidate=json.loads(pin.read_text())['validated_ios_source_candidate']
    if candidate['scope'] != 'unsigned NativeLab only' or candidate['platform'] != 'ios-arm64':
        raise ValueError('source candidate scope mismatch')
    for name,key,limit in [('libXray.a','library_sha256',150*1024*1024),('libXray.h','header_sha256',65536)]:
        path=directory/name
        if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= limit:
            raise ValueError('missing or invalid source candidate file')
        with path.open('rb') as stream: actual=hashlib.file_digest(stream,'sha256').hexdigest()
        if actual != candidate[key]: raise ValueError('source candidate digest mismatch: '+name)
    return candidate

if __name__=='__main__':
    if len(sys.argv)!=2:raise SystemExit('usage: verify_xray_source_candidate.py CANDIDATE_DIR')
    print(json.dumps(verify(Path(sys.argv[1])),sort_keys=True))
