import json
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[2]
PREFLIGHT=pathlib.Path(__file__).with_name('preflight.py')
class PreflightTests(unittest.TestCase):
 def test_requires_one_exact_passing_test(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);bin=root/'bin';bin.mkdir()
   xcode=bin/'xcodebuild';xcode.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$RUNNER_TEMP/preflight-args"\nexit "${FAKE_EXIT:-0}"\n');xcode.chmod(0o755)
   xcrun=bin/'xcrun';xcrun.write_text('#!/bin/sh\ncat "$RUNNER_TEMP/fake-$4.json"\n');xcrun.chmod(0o755)
   summary={'result':'Passed','totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'expectedFailures':0}
   tree={'testNodes':[{'nodeType':'Test Case','nodeIdentifier':'KinUITests/testEmptyStateAtLargestDynamicType()'}]}
   def execute(result,ident,exitcode='0'):
    (root/'fake-summary.json').write_text(json.dumps(result));(root/'fake-tests.json').write_text(json.dumps(ident))
    env=dict(os.environ,PATH=str(bin)+':'+os.environ['PATH'],RUNNER_TEMP=d,KIN_AB_XCTESTRUN='/tmp/fixed.xctestrun',KIN_CI_SIMULATOR='synthetic',FAKE_EXIT=exitcode)
    return subprocess.run([os.environ.get('PYTHON','python3'),str(PREFLIGHT)],cwd=ROOT,env=env,capture_output=True,text=True)
   self.assertEqual(execute(summary,tree).returncode,0)
   args=(root/'preflight-args').read_text().splitlines()
   self.assertIn('test-without-building',args)
   self.assertEqual([x for x in args if x.startswith('-only-testing:')],['-only-testing:KinUITests/KinUITests/testEmptyStateAtLargestDynamicType'])
   self.assertNotIn('-skip-testing',args)
   wrong=dict(summary,skippedTests=1)
   self.assertNotEqual(execute(wrong,tree).returncode,0)
   self.assertNotEqual(execute(summary,{'testNodes':[]}).returncode,0)
   self.assertNotEqual(execute(summary,tree,'65').returncode,0)
if __name__=='__main__':unittest.main()
