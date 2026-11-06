#!/usr/bin/env python3
"""Run one fixed synthetic test to check prebuilt-product compatibility."""
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

TEST='KinUITests/KinUITests/testEmptyStateAtLargestDynamicType'
root=Path(os.environ['RUNNER_TEMP']); result=root/'KinTests.xcresult'
cmd=['xcodebuild','test-without-building','-xctestrun',os.environ['KIN_AB_XCTESTRUN'],
     '-destination','platform=iOS Simulator,id='+os.environ['KIN_CI_SIMULATOR'],
     '-resultBundlePath',str(result),'-parallel-testing-enabled','NO',
     '-collect-test-diagnostics','never','-test-timeouts-enabled','YES',
     '-default-test-execution-time-allowance','240','-maximum-test-execution-time-allowance','600',
     '-only-testing:'+TEST]
try:
    with (root/'kin-ab-preflight-private.log').open('w') as out:
        run=subprocess.run(cmd,stdout=out,stderr=subprocess.STDOUT,timeout=600)
    print('KIN_AB_PREFLIGHT test_exit='+str(run.returncode))
    for kind,name in [('summary','KinTests-summary.json'),('tests','KinTests-test-tree.json')]:
        completed=subprocess.run(['xcrun','xcresulttool','get','test-results',kind,'--path',str(result)],
                                 capture_output=True,check=True,timeout=60)
        (root/name).write_bytes(completed.stdout)
    summary=json.loads((root/'KinTests-summary.json').read_text())
    checks=('totalTestCount','passedTests','failedTests','skippedTests','expectedFailures')
    if (run.returncode != 0 or summary.get('result')!='Passed'
        or [summary.get(k) for k in checks] != [1,1,0,0,0]):raise ValueError('Preflight test incomplete')
    spec=importlib.util.spec_from_file_location('shards',Path.cwd()/'scripts/ci-test-shards.py')
    shards=importlib.util.module_from_spec(spec);spec.loader.exec_module(shards)
    shards.verify_test_ids(json.loads((root/'KinTests-test-tree.json').read_text()),[TEST])
    print('KIN_AB_PREFLIGHT fixed_test=passed identities=verified')
except (OSError,ValueError,KeyError,subprocess.SubprocessError) as error:
    print('KIN_AB_PREFLIGHT failed='+type(error).__name__,file=sys.stderr)
    sys.exit(1)
