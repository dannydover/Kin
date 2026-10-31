import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE=Path(__file__).resolve().parent
REPO=HERE.parent if (HERE.parent/'Kin.xcodeproj').is_dir() else HERE.parents[1]/'kin-1.3-work'


class PhotosOrderTests(unittest.TestCase):
    def workspace(self, root):
        root=Path(root);(root/'scripts').mkdir();(root/'KinUITests').mkdir()
        for name in ('ci-photos-order.py','collect-photos-order.py','prepare-photos-order.py'):
            shutil.copy2(HERE/name,root/'scripts'/name)
        shutil.copy2(REPO/'scripts/ci-test-shards.py',root/'scripts/ci-test-shards.py')
        shutil.copy2(REPO/'KinUITests/KinUITests.swift',root/'KinUITests/KinUITests.swift')
        return root

    def test_instrumentation_preserves_single_assertion_and_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            root=self.workspace(directory)
            before=(root/'KinUITests/KinUITests.swift').read_text()
            subprocess.run([sys.executable,'scripts/prepare-photos-order.py'],cwd=root,check=True)
            after=(root/'KinUITests/KinUITests.swift').read_text()
            self.assertEqual(after.count('KIN_CI_PHOTOS begin'),1)
            self.assertEqual(after.count('let photosReady = app.navigationBars["Photos"].waitForExistence(timeout: 15)'),1)
            self.assertEqual(after.count('XCTAssertTrue(photosReady)'),1)
            self.assertEqual(after.count('testPhotoRemovalAlertHasVisibleCancelAndPreservesSavedPhoto'),before.count('testPhotoRemovalAlertHasVisibleCancelAndPreservesSavedPhoto'))

    def test_sanitized_failed_result_retains_identity_and_order(self):
        with tempfile.TemporaryDirectory() as directory:
            root=self.workspace(directory);runtime=root/'runtime';runtime.mkdir()
            photo='KinUITests/KinUITests/testPhotoRemovalAlertHasVisibleCancelAndPreservesSavedPhoto'
            (runtime/'KinTests-progress.jsonl').write_text(json.dumps({'kind':'test','id':photo,'event':'started'})+'\n'+json.dumps({'kind':'photos_readiness','stage':'begin','test':photo})+'\n')
            (runtime/'KinTests-summary.json').write_text(json.dumps({'result':'Failed','totalTestCount':1,'passedTests':0,'failedTests':1,'skippedTests':0,'expectedFailures':0,'testFailures':[{'testIdentifierString':photo.removeprefix('KinUITests/')+'()','failureText':'Test exceeded execution time allowance PRIVATE'}]}))
            (runtime/'KinTests-test-tree.json').write_text(json.dumps({'testNodes':[{'nodeType':'Test Case','nodeIdentifier':photo.removeprefix('KinUITests/')+'()'}]}))
            p=subprocess.run([sys.executable,'scripts/collect-photos-order.py','isolated'],cwd=root,env=dict(os.environ,RUNNER_TEMP=str(runtime),GITHUB_SHA='synthetic'),capture_output=True,text=True)
            self.assertEqual(p.returncode,0,p.stderr)
            output=runtime/'KinPhotosOrder';data=json.loads((output/'manifest.json').read_text())
            self.assertEqual(data['status'],'finalized');self.assertTrue(data['order_verified'])
            self.assertEqual(data['failures'][0]['category'],'test_timeout')
            self.assertNotIn('PRIVATE',(output/'manifest.json').read_text())
            self.assertEqual({p.name for p in output.iterdir()},{'manifest.json','progress.jsonl'})

    def test_readiness_marker_keeps_only_stage_and_monotonic_time(self):
        with tempfile.TemporaryDirectory() as directory:
            root=self.workspace(directory)
            code=('import importlib.util; s=importlib.util.spec_from_file_location("d","scripts/ci-photos-order.py");'
                  'm=importlib.util.module_from_spec(s);s.loader.exec_module(m);'
                  'print(m.parse("KIN_CI_PHOTOS begin ms=123 PRIVATE",set()))')
            p=subprocess.run([sys.executable,'-c',code],cwd=root,capture_output=True,text=True,check=True)
            self.assertEqual(p.stdout.strip(),"{'kind': 'photos_readiness', 'stage': 'begin', 'uptime_ms': 123}")


if __name__=='__main__':unittest.main()
