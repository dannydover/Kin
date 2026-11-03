import importlib.util
import pathlib
import tempfile
import os
from unittest.mock import patch
import unittest

p=pathlib.Path(__file__).with_name('results.py')
s=importlib.util.spec_from_file_location('ab_results',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class ResultTests(unittest.TestCase):
    def test_fail_closed(self):
        summary={'result':'Passed','totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'expectedFailures':0}
        tree={'testNodes':[{'nodeType':'Test Case','nodeIdentifier':'NativeContactsTests/testAdult()'}]}
        selected=['KinUITests/NativeContactsTests/testNativeFullBirthdayAndPhotoImportForAdult']
        progress=[{'kind':'authorization','state':'authorized'}, {'kind':'contact_cleanup_accounting','scope':'native-adult','status':'verified'}, {'kind':'exit','code':0,'interrupted':False}]
        cleanup={'shutdown':'success','delete':'success','inventory':'absent'}
        result=m.validate(summary,tree,progress,cleanup,'ui-0',selected,lambda *a:None)
        self.assertTrue(result['comparable']);m.validate_outcome(result,'success')
        for outcome in ('failure','skipped',None):
            with self.assertRaises(ValueError):m.validate_outcome(result,outcome)
        for replacement in ({'shutdown':'failed','delete':'success','inventory':'absent'},{}):
            with self.assertRaises(ValueError):m.validate(summary,tree,progress,replacement,'ui-0',selected,lambda *a:None)
        for invalid in (progress[1:],progress[:1]+progress[2:],progress+[progress[1]],progress[:-1]+[{'kind':'exit','code':65,'interrupted':False}]):
            with self.assertRaises(ValueError):m.validate(summary,tree,invalid,cleanup,'ui-0',selected,lambda *a:None)
        for field in ('skippedTests','expectedFailures'):
            bad=dict(summary);bad[field]=1
            with self.assertRaises(ValueError):m.validate(bad,tree,progress,cleanup,'ui-0',selected,lambda *a:None)
        failed=dict(summary,result='Failed',passedTests=0,failedTests=1)
        failure_progress=progress[:-1]+[{'kind':'exit','code':65,'interrupted':False}]
        failed_result=m.validate(failed,tree,failure_progress,cleanup,'ui-0',selected,lambda *a:None)
        self.assertEqual(failed_result['failed'],1);m.validate_outcome(failed_result,'failure')
        with self.assertRaises(ValueError):m.validate(failed,tree,progress,cleanup,'ui-0',selected,lambda *a:None)
        with self.assertRaises(ValueError):m.validate(summary,{'testNodes':[]},progress,cleanup,'ui-0',selected,lambda *a:None)

    def test_main_reverts_to_noncomparable_after_late_failure(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d)
            for filename in ('KinTests-summary.json','KinTests-test-tree.json','KinTests-cleanup.json'):
                (root/filename).write_text('{}')
            (root/'KinTests-progress.jsonl').write_text('')
            env={'KIN_AB_GROUP':'unit','RUNNER_TEMP':d,'KIN_AB_EVIDENCE_OK':'true',
                 'KIN_AB_TEST_OUTCOME':'failure'}
            with patch.dict(os.environ,env,clear=False),patch.object(m,'validate',return_value={'comparable':True,'failed':0}):
                self.assertEqual(m.main(),1)
            import json
            self.assertFalse(json.loads((root/'KinAB-status.json').read_text())['comparable'])

if __name__=='__main__': unittest.main()
