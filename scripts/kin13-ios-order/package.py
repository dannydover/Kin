#!/usr/bin/env python3
"""Retain one batch under the runner's unmodified temporary directory."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

which = sys.argv[1]
if which not in ('first', 'second'): raise SystemExit('Unsupported batch')
batch = Path(os.environ['RUNNER_TEMP']) / ('ios-order-' + which)
out = batch / 'KinCI-retained'; out.mkdir(parents=True, exist_ok=True)
result = batch / 'KinTests.xcresult'; summary_path = batch / 'KinTests-summary.json'
manifest = {'status':'partial', 'result_sha256':None}
if result.is_dir():
    with summary_path.open('w') as output:
        try:
            subprocess.run(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)], stdout=output, stderr=subprocess.DEVNULL, timeout=60)
        except (OSError, subprocess.SubprocessError):
            pass  # The partial bundle is retained; the gate still fails below.
    archive = out / 'KinTests-xcresult.zip'
    try:
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, allowZip64=True) as z:
            for path in sorted(result.rglob('*')):
                if path.is_symlink(): raise ValueError('symlink')
                if path.is_file(): z.write(path, Path(result.name) / path.relative_to(result))
        with zipfile.ZipFile(archive) as z:
            if z.testzip(): raise ValueError('invalid_zip')
        manifest['result_sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
        try:
            summary = json.loads(summary_path.read_text())
            counts = ('totalTestCount','passedTests','failedTests','skippedTests')
            if ((result/'Info.plist').is_file() and summary.get('result') in ('Passed','Failed') and
                all(type(summary.get(k)) is int for k in counts) and summary['totalTestCount'] > 0):
                manifest['status'] = 'finalized'
        except (OSError, ValueError, AttributeError):
            pass
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        archive.unlink(missing_ok=True); manifest['error_type'] = type(error).__name__
for name in ('KinTests-progress.jsonl','KinTests-summary.json'):
    path = batch / name
    if path.is_file(): shutil.copyfile(path, out / name)
(out/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
(out/'source-commit.txt').write_text(os.environ['EXPECTED_SOURCE']+'\n')
(out/'diagnostic-commit.txt').write_text(os.environ['GITHUB_SHA']+'\n')
if manifest['status'] != 'finalized': raise SystemExit('Retained batch is partial')
if hashlib.sha256((out/'KinTests-xcresult.zip').read_bytes()).hexdigest() != manifest['result_sha256']:
    raise SystemExit('Retained result hash mismatch')
print('Finalized synthetic batch and hash retained:', which)
