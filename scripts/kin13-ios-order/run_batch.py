#!/usr/bin/env python3
"""Run one explicit synthetic iOS suite batch; retain fixed hashes, not raw logs."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

control = Path(__file__).resolve().parent
manifest = json.loads((control / 'baseline.json').read_text())
which = sys.argv[1]
if which not in ('first', 'second'):
    raise SystemExit('Unsupported batch')
batch = Path(os.environ['RUNNER_TEMP']) / ('ios-order-' + which)
batch.mkdir(exist_ok=True)
suites = manifest[which + '_suites']
if not suites or any(not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', s) for s in suites):
    raise SystemExit('Invalid suite selection')
device = os.environ['KIN_CI_SIMULATOR']
cmd = ['xcodebuild', '-project', 'Kin.xcodeproj', '-scheme', 'Kin',
       '-destination', 'platform=iOS Simulator,id=' + device,
       '-derivedDataPath', os.environ['RUNNER_TEMP'] + '/KinOrderBuild',
       '-resultBundlePath', str(batch / 'KinTests.xcresult'),
       '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
       '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '240',
       '-maximum-test-execution-time-allowance', '600']
cmd += ['-only-testing:KinTests/' + s for s in suites]
cmd += ['test-without-building', 'CODE_SIGNING_ALLOWED=NO']
env = {k: os.environ[k] for k in ('PATH', 'HOME', 'TMPDIR', 'DEVELOPER_DIR', 'LANG', 'LC_ALL') if k in os.environ}
env['NSUnbufferedIO'] = 'YES'
known = set(manifest['start_title_hashes'])
with (batch / 'KinTests-progress.jsonl').open('w') as progress:
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, text=True, errors='replace', bufsize=1)
    for line in proc.stdout:
        match = re.search(r'\bTest "([^"]+)" started\.', line)
        if match:
            digest = hashlib.sha256(match.group(1).encode()).hexdigest()
            if digest in known:
                progress.write(json.dumps({'kind': 'test_start_hash', 'id': digest}) + '\n')
                progress.flush()
    status = proc.wait()
    progress.write(json.dumps({'kind': 'exit', 'code': status}) + '\n')
    progress.flush()
print('Synthetic batch', which, 'xcodebuild exit:', status)
sys.exit(status if status >= 0 else 1)
