import importlib.util, json, os, pathlib, subprocess, sys, tempfile, unittest, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
def load(name):
    spec=importlib.util.spec_from_file_location('observe',ROOT/'scripts'/name); module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
class ObservabilityTests(unittest.TestCase):
    def test_allowlist_drops_private_payloads(self):
        m=load('ci-observe.py');ids={'KinUITests/KinUITests/testFoo'}
        self.assertEqual(m.parse("Test Case '-[KinUITests.KinUITests testFoo]' started. SECRET",ids),{'kind':'test','id':'KinUITests/KinUITests/testFoo','event':'started'})
        self.assertIsNone(m.parse("Test Case '-[Private.Secret testName]' started. SECRET",ids))
        self.assertEqual(m.parse('t = 5.0s Type PRIVATE_FIELD SECRET',ids),{'kind':'action','stage':'type'})
        self.assertEqual(m.parse('KIN_CI_AUTH authorized SECRET',ids),{'kind':'authorization','state':'authorized'})
    def test_retention_distinguishes_partial_and_complete(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d);env=dict(os.environ,RUNNER_TEMP=d);bundle=root/'KinTests.xcresult';bundle.mkdir()
            (root/'KinTests-progress.jsonl').write_text('{"kind":"heartbeat"}\n')
            subprocess.run([sys.executable,str(ROOT/'scripts/ci-retain.py')],env=env,check=True)
            out=root/'KinCI-retained';self.assertEqual(json.loads((out/'manifest.json').read_text())['status'],'partial')
            (bundle/'Info.plist').write_text('synthetic');(bundle/'.hidden').write_text('synthetic')
            subprocess.run([sys.executable,str(ROOT/'scripts/ci-retain.py')],env=env,check=True)
            self.assertEqual(json.loads((out/'manifest.json').read_text())['status'],'partial')
            (root/'KinTests-summary.json').write_text(json.dumps({'result':'Failed','totalTestCount':1,'passedTests':0,'failedTests':1,'skippedTests':0}))
            subprocess.run([sys.executable,str(ROOT/'scripts/ci-retain.py')],env=env,check=True)
            self.assertEqual(json.loads((out/'manifest.json').read_text())['status'],'finalized')
            with zipfile.ZipFile(out/'KinTests-xcresult.zip') as z:self.assertIn('KinTests.xcresult/.hidden',z.namelist());self.assertIsNone(z.testzip())
    def test_missing_authorization_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d);fake=p/'xcodebuild';fake.write_text('#!/bin/sh\necho "KIN_CI_AUTH denied"\nexit 0\n');fake.chmod(0o755)
            env=dict(os.environ,PATH=d+':'+os.environ['PATH'],RUNNER_TEMP=d,KIN_CI_SIMULATOR='synthetic')
            run=subprocess.run([sys.executable,str(ROOT/'scripts/ci-observe.py'),'ui-2'],cwd=ROOT,env=env,capture_output=True,text=True)
            self.assertNotEqual(run.returncode,0);self.assertIn('authorization was not verified',run.stderr)
            events=[json.loads(x) for x in (p/'KinTests-progress.jsonl').read_text().splitlines()];self.assertIn({'kind':'authorization','state':'denied','elapsed':events[0]['elapsed']},events)
if __name__=='__main__':unittest.main()
