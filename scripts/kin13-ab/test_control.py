import importlib.util
import pathlib
import tempfile
import hashlib
import unittest
p=pathlib.Path(__file__).with_name('control.py');s=importlib.util.spec_from_file_location('ab_control',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class ControlTests(unittest.TestCase):
 def test_environment_rejects_drift(self):
  runtime={'runtimes':[{'identifier':'com.apple.CoreSimulator.SimRuntime.iOS-27-0','buildversion':'24A434','isAvailable':True}]}
  m.validate_env('image:1','image:1','27.1','Xcode 27.1\nBuild version 27A9275','arm64',runtime)
  for args in [('image:2','image:1','27.1','Xcode 27.1\nBuild version 27A9275','arm64',runtime),('image:1','image:1','27.1','Xcode 27.0\nBuild version 27A266a','arm64',runtime),('image:1','image:1','27.1','Xcode 27.1\nBuild version 27A9275','x86_64',runtime),('image:1','image:1','27.1','Xcode 27.1\nBuild version 27A9275','arm64',{'runtimes':[]})]:
   with self.assertRaises(ValueError):m.validate_env(*args)
 def test_waits_for_exact_required_ci_head(self):
  head='a'*40
  self.assertFalse(m.required_ci_finished({'workflow_runs':[]},head))
  with self.assertRaises(ValueError):m.required_ci_finished({'workflow_runs':[{}]*100},head)
  other={'name':'Build and test','event':'pull_request','head_sha':'b'*40,'status':'completed'}
  self.assertFalse(m.required_ci_finished({'workflow_runs':[other]},head))
  run={'name':'Build and test','event':'pull_request','head_sha':head,'status':'in_progress'}
  self.assertFalse(m.required_ci_finished({'workflow_runs':[run]},head))
  run['status']='completed';run['conclusion']='failure'
  self.assertTrue(m.required_ci_finished({'workflow_runs':[run]},head))
  run2=dict(run,status='queued')
  self.assertFalse(m.required_ci_finished({'workflow_runs':[run,run2]},head))
 def test_product_digest_rejects_changed_bytes(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'products.zip';p.write_bytes(b'fixed synthetic products')
   digest=hashlib.sha256(p.read_bytes()).hexdigest();m.verify_product(p,digest)
   p.write_bytes(b'changed')
   with self.assertRaises(ValueError):m.verify_product(p,digest)
   with self.assertRaises(ValueError):m.verify_product(p,'invalid')
 def test_arm_rejects_missing_wrong_and_unit_drift(self):
  records=[dict(comparable=True,group=g,arm='arm1',toolchain='27.0',image='image:1',runtime='24A434',product_sha256='a'*64,manifest_sha256='d'*64,identity_sha256='b'*64) for g in m.GROUPS]
  self.assertEqual(m.validate_arm(records,'arm1','27.0','image:1','a'*64,'d'*64),'b'*64)
  with self.assertRaises(ValueError):m.validate_arm(records[:-1],'arm1','27.0','image:1','a'*64,'d'*64)
  with self.assertRaises(ValueError):m.validate_arm(records,'arm1','27.0','image:1','a'*64,'d'*64,'c'*64)
  records[0]['comparable']=False
  with self.assertRaises(ValueError):m.validate_arm(records,'arm1','27.0','image:1','a'*64,'d'*64)
if __name__=='__main__':unittest.main()
