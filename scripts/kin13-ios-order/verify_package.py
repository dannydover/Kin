#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path

root = Path(os.environ['RUNNER_TEMP']) / 'KinCI-retained'
manifest = json.loads((root / 'manifest.json').read_text())
archive = root / 'KinTests-xcresult.zip'
if (manifest.get('status') != 'finalized' or
    hashlib.sha256(archive.read_bytes()).hexdigest() != manifest.get('result_sha256') or
    (root / 'source-commit.txt').read_text().strip() != os.environ['EXPECTED_SOURCE']):
    raise SystemExit('Retained result is incomplete or its hash/source differs')
print('Finalized result hash and source verified')
