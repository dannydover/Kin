import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class VerifyTests(unittest.TestCase):
    def test_packaging_uses_batch_path_and_retains_partial_results(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);fake=root/'xcrun'
            summary={'result':'Passed','totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0}
            fake.write_text('#!/bin/sh\n[ "$KIN_FAKE_FAIL" != 1 ] || exit 2\nprintf \'%s\\n\' '+repr(json.dumps(summary))+'\n')
            fake.chmod(0o755)
            for name in ('first','second'):
                result=root/('ios-order-'+name)/'KinTests.xcresult';result.mkdir(parents=True)
                (result/'Info.plist').write_text('synthetic')
                (result.parent/'KinTests-progress.jsonl').write_text('{"kind":"exit","code":0}\n')
            env=dict(os.environ,RUNNER_TEMP=temp,EXPECTED_SOURCE='expected',GITHUB_SHA='wrapper',PATH=str(root)+':'+os.environ['PATH'])
            def run(name,**extra):return subprocess.run(['python3',str(Path(__file__).with_name('package.py')),name],env=dict(env,**extra),capture_output=True)
            self.assertEqual(run('first').returncode,0)
            retained=root/'ios-order-first'/'KinCI-retained';m=json.loads((retained/'manifest.json').read_text());archive=retained/'KinTests-xcresult.zip'
            self.assertEqual(m['status'],'finalized');self.assertEqual(m['result_sha256'],hashlib.sha256(archive.read_bytes()).hexdigest())
            self.assertEqual((retained/'source-commit.txt').read_text().strip(),'expected')
            self.assertNotEqual(run('second',KIN_FAKE_FAIL='1').returncode,0)
            partial=root/'ios-order-second'/'KinCI-retained'
            self.assertEqual(json.loads((partial/'manifest.json').read_text())['status'],'partial')
            self.assertTrue((partial/'KinTests-xcresult.zip').is_file())
            self.assertTrue((partial/'KinTests-progress.jsonl').is_file())

    def test_batch_emits_only_known_start_hashes(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); control=root/'control';control.mkdir()
            shutil.copy(Path(__file__).with_name('run_batch.py'), control/'run_batch.py')
            title='Fixed synthetic test'; digest=hashlib.sha256(title.encode()).hexdigest()
            (control/'baseline.json').write_text(json.dumps({'first_suites':['ExampleTests'],'start_title_hashes':[digest]}))
            fake=root/'xcodebuild'
            fake.write_text('#!/bin/sh\nprintf \'Test "Fixed synthetic test" started.\\nprivate payload\\n\'\n')
            fake.chmod(0o755)
            env=dict(os.environ, RUNNER_TEMP=temp, KIN_CI_SIMULATOR='synthetic', PATH=str(root)+':'+os.environ['PATH'])
            result=subprocess.run(['python3',str(control/'run_batch.py'),'first'],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            progress=(root/'ios-order-first'/'KinTests-progress.jsonl').read_text()
            self.assertIn(digest,progress)
            self.assertNotIn('private payload',progress+result.stdout+result.stderr)
            self.assertNotIn(title,progress)

    def test_complete_changed_order_and_fail_closed_cases(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); control = root / 'control'; control.mkdir()
            shutil.copy(Path(__file__).with_name('verify.py'), control / 'verify.py')
            baseline = {'source_sha':'expected', 'identities':['A/a()', 'A/b()', 'B/c()', 'B/d()'],
                        'start_title_hashes':['a','b','c','d'],
                        'first_suites':['B'], 'second_suites':['A']}
            (control / 'baseline.json').write_text(json.dumps(baseline))
            for name, ids, starts in [('first',['B/c()','B/d()'],['c','d']),
                                      ('second',['A/a()','A/b()'],['a','b'])]:
                batch = root / ('ios-order-' + name); batch.mkdir()
                result = batch / 'KinTests.xcresult'; result.mkdir()
                (result / 'summary.json').write_text(json.dumps({'result':'Passed','passedTests':2,'totalTestCount':2,'failedTests':0,'skippedTests':0,'expectedFailures':0}))
                (result / 'tests.json').write_text(json.dumps({'testNodes':[{'nodeType':'Test Case','nodeIdentifier':x} for x in ids]}))
                (batch / 'KinTests-progress.jsonl').write_text(''.join(json.dumps({'kind':'test_start_hash','id':x})+'\n' for x in starts)+json.dumps({'kind':'exit','code':0})+'\n')
            fake = root / 'xcrun'
            fake.write_text('#!/bin/sh\nfor last; do :; done\ncase "$*" in *"test-results summary"*) cat "$last/summary.json";; *"test-results tests"*) cat "$last/tests.json";; *) exit 2;; esac\n')
            fake.chmod(0o755)
            env = dict(os.environ, RUNNER_TEMP=temp, PATH=str(root)+':'+os.environ['PATH'], EXPECTED_SOURCE='expected')
            def run(): return subprocess.run(['python3', str(control/'verify.py')], env=env, capture_output=True)
            self.assertEqual(run().returncode, 0)
            p = root/'ios-order-first'/'KinTests-progress.jsonl'; original=p.read_text()
            p.write_text(original.replace('"id": "d"','"id": "c"'))
            self.assertNotEqual(run().returncode, 0)
            p.write_text(original)
            result = root/'ios-order-first'/'KinTests.xcresult'/'summary.json'
            summary=json.loads(result.read_text());summary['skippedTests']=1;result.write_text(json.dumps(summary))
            self.assertNotEqual(run().returncode, 0)
            summary['skippedTests']=0;result.write_text(json.dumps(summary))
            baseline['start_title_hashes']=['c','d','a','b'];(control/'baseline.json').write_text(json.dumps(baseline))
            self.assertNotEqual(run().returncode, 0)

if __name__ == '__main__': unittest.main()
