import json
import pathlib
import re
import subprocess
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[2]
WORKFLOW=ROOT/'.github/workflows/kin13-fixed-product-comparison.yml'

def yaml_file(path):
    result=subprocess.run(['ruby','-ryaml','-rjson','-e','puts JSON.generate(YAML.load_file(ARGV[0]))',str(path)],capture_output=True,text=True,check=True)
    return json.loads(result.stdout)

class WorkflowTests(unittest.TestCase):
 def test_trigger_permissions_and_serial_arms(self):
  workflow=yaml_file(WORKFLOW);jobs=workflow['jobs']
  event=workflow.get('on',workflow.get('true'))
  self.assertEqual(event,{'pull_request':{'types':['synchronize']}})
  self.assertEqual(workflow['permissions'],{'contents':'read'})
  self.assertIn('kin13-ab-once',str(jobs['kickoff']))
  self.assertIn('await_required_ci',jobs['build']['needs'])
  self.assertEqual(jobs['preflight270']['needs'],['build'])
  self.assertEqual(jobs['preflight271']['needs'],['build','preflight270'])
  previous='preflight271'
  for n,tool in [(1,'27.0'),(2,'27.1'),(3,'27.0'),(4,'27.1')]:
   arm=jobs['arm'+str(n)];gate=jobs['gate'+str(n)]
   self.assertIn(previous,arm['needs']);self.assertIn('arm'+str(n),gate['needs'])
   self.assertFalse(arm['strategy']['fail-fast'])
   self.assertEqual(arm['strategy']['matrix']['shard'],['unit','ui-0','ui-1','ui-2','ui-3'])
   self.assertIn("'"+tool+"'",str(arm))
   self.assertIn('always()',arm['if']);self.assertIn('always()',gate['if'])
   self.assertNotIn('continue-on-error',str(arm))
   previous='gate'+str(n)
  text=WORKFLOW.read_text();self.assertNotIn('skip-testing',text);self.assertNotIn('retry-tests-on-failure',text)
  self.assertGreaterEqual(text.count('022e405fe6d301df9b2e4c936f91f32065ba996d'),7)
  self.assertEqual(text.count(' build-for-testing CODE_SIGNING_ALLOWED=NO'),1)
  self.assertNotIn('actions: write',text)
  self.assertIn('await_required_ci',jobs['build']['needs'])
  for name in ('arm','preflight'):
   action=(ROOT/'scripts/kin13-ab/actions'/name/'action.yml').read_text()
   self.assertIn('product_manifest.py verify',action)
   self.assertIn('inputs.manifest_sha',action)
   self.assertIn('inputs.product_sha',action)
   self.assertNotIn('skip-testing',action)

 def test_embedded_shell_parses_after_expression_expansion(self):
  documents=[yaml_file(WORKFLOW),yaml_file(ROOT/'scripts/kin13-ab/actions/arm/action.yml'),
             yaml_file(ROOT/'scripts/kin13-ab/actions/preflight/action.yml')]
  scripts=[]
  def visit(value):
   if isinstance(value,dict):
    if isinstance(value.get('run'),str):scripts.append(value['run'])
    for child in value.values():visit(child)
   elif isinstance(value,list):
    for child in value:visit(child)
  for document in documents:visit(document)
  self.assertGreater(len(scripts),10)
  for script in scripts:
   expanded=re.sub(r'\$\{\{.*?\}\}','VALUE',script)
   result=subprocess.run(['bash','-n'],input=expanded,text=True,capture_output=True)
   self.assertEqual(result.returncode,0,result.stderr)
 def test_actions_always_retain_and_cleanup(self):
  for name in ('arm','preflight'):
   action=yaml_file(ROOT/'scripts/kin13-ab/actions'/name/'action.yml'); steps=action['runs']['steps']
   self.assertEqual(action['runs']['using'],'composite')
   required = (('Retain finalized or partial synthetic results','Upload synthetic result evidence',
                'Remove the isolated simulator','Upload comparison status') if name=='arm' else
               ('Retain synthetic preflight evidence','Upload synthetic preflight evidence',
                'Remove isolated preflight simulator','Upload preflight cleanup status'))
   for label in required:
    matched=[s for s in steps if s.get('name')==label]
    self.assertEqual(len(matched),1,(name,label))
    self.assertEqual(matched[0].get('if'),'always()',(name,label))
  action=yaml_file(ROOT/'scripts/kin13-ab/actions/arm/action.yml')
  status=next(s for s in action['runs']['steps'] if s.get('name')=='Record comparison and cleanup status')
  self.assertEqual(status.get('if'),'always()')
  self.assertIn('run_tests',status['env']['KIN_AB_TEST_OUTCOME'])
  for step in ('export_result','package_result','upload_result','cleanup_simulator'):
   self.assertIn(step,status['env']['KIN_AB_EVIDENCE_OK'])

if __name__=='__main__':unittest.main()
