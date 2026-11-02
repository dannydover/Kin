import importlib.util, json, os, pathlib, re, subprocess, sys, tempfile, unittest, zipfile
import xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).resolve().parents[2]
def load(name):
    spec=importlib.util.spec_from_file_location('observe',ROOT/'scripts'/name); module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
class ObservabilityTests(unittest.TestCase):
    def test_real_contact_fixture_journeys_keep_distinct_required_cleanup_scopes(self):
        observer = load('ci-observe.py')
        required = {
            'KinUITests/NativeContactsTests/testNativeFullBirthdayAndPhotoImportForAdultAndMinor': 'native-full',
            'KinUITests/KinUITests/testContactMissingBirthdayPromptCancellationAndEstimatedImport': 'missing-birthday',
        }
        discovered = set(observer.shards.discover())
        self.assertTrue(set(required).issubset(discovered))
        for ident, scope in required.items():
            self.assertEqual(observer.CLEANUP_SCOPES.get(ident), scope)
        self.assertEqual(len(set(required.values())), len(required))

    def test_release_guard_rejects_synthetic_contacts_adapter_markers(self):
        release = load('check-release.py')
        for marker in (b'--kin-ui-fixture', b'SyntheticNotebookFixture', b'named-friend', b'long-friend', b'partner-friends', b'young-parent-friends', b'--kin-ui-synthetic-contact', b'synthetic-contact-selection', b'--kin-ui-preservation-contacts', b'synthetic-preservation-contact-'):
            self.assertIsNotNone(re.search(release.DEBUG_PATTERN, marker))

    def test_coverage_map_accounts_for_every_current_ui_method(self):
        shards = load('ci-test-shards.py')
        document = (ROOT / 'scripts/kin13-coverage-map.md').read_text()
        entries = re.findall(r'^\| `([A-Za-z0-9_]+)\.(test[A-Za-z0-9_]+)` \|', document, re.MULTILINE)
        self.assertEqual(len(entries), len(set(entries)))
        mapped = {f'KinUITests/{klass}/{method}' for klass, method in entries}
        self.assertTrue(set(shards.discover()).issubset(mapped), 'Every current UI method needs a coverage-map row')

    def test_order_comparison_requires_exact_identities_and_real_change(self):
        m=load('ci-compare-order.py')
        expected={'ui-0':['a','b','c'],'ui-1':['d','e']}
        before={'ui-0':['a','b','c'],'ui-1':['d','e']}
        self.assertEqual(m.compare(before,{'ui-0':['b','a','c'],'ui-1':['d','e']},expected),['ui-0'])
        with self.assertRaises(ValueError):m.compare(before,before,expected)
        with self.assertRaises(ValueError):m.compare(before,{'ui-0':['a','a','c'],'ui-1':['d','e']},expected)
        with self.assertRaises(ValueError):m.compare(before,{'ui-0':['a','b','c']},expected)

    def test_random_order_only_changes_ui_trial_scheme(self):
        m=load('ci-observe.py')
        self.assertEqual(m.test_scheme('unit','standard'),'Kin')
        self.assertEqual(m.test_scheme('unit','random'),'Kin')
        self.assertEqual(m.test_scheme('ui-0','standard'),'Kin')
        self.assertEqual(m.test_scheme('ui-0','random'),'KinRandomOrder')
        with self.assertRaises(ValueError):m.test_scheme('ui-0','unknown')
        generator=load('ci-random-plan.py')
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory)
            original_path=ROOT/'Kin.xcodeproj/xcshareddata/xcschemes/Kin.xcscheme'
            copied=root/'Kin.xcodeproj/xcshareddata/xcschemes/Kin.xcscheme'
            copied.parent.mkdir(parents=True)
            copied.write_bytes(original_path.read_bytes())
            self.assertEqual(generator.generate(root),'KinRandomOrder')
            self.assertEqual(copied.read_bytes(),original_path.read_bytes())
            plan=json.loads((root/'KinRandomOrder.xctestplan').read_text())
            alternate=ET.parse(root/'Kin.xcodeproj/xcshareddata/xcschemes/KinRandomOrder.xcscheme').getroot()
            with self.assertRaises(ValueError):generator.generate(root)
        self.assertEqual(plan['configurations'][0]['options']['testExecutionOrdering'],'random')
        self.assertEqual({t['target']['name'] for t in plan['testTargets']},{'KinTests','KinUITests'})
        self.assertTrue(all(t.get('parallelizable') is False for t in plan['testTargets']))
        original=ET.parse(ROOT/'Kin.xcodeproj/xcshareddata/xcschemes/Kin.xcscheme').getroot()
        old_test=original.find('TestAction');new_test=alternate.find('TestAction')
        self.assertEqual(old_test.attrib,new_test.attrib)
        refs=old_test.findall('.//BuildableReference')
        self.assertEqual({(r.get('BlueprintIdentifier'),r.get('BlueprintName')) for r in refs},
                         {(t['target']['identifier'],t['target']['name']) for t in plan['testTargets']})
        self.assertEqual(new_test.find('./TestPlans/TestPlanReference').get('reference'),
                         'container:KinRandomOrder.xctestplan')
        for tag in ('BuildAction','LaunchAction','ProfileAction','AnalyzeAction','ArchiveAction'):
            def canonical(node):
                return (node.tag,tuple(sorted(node.attrib.items())),tuple(canonical(child) for child in node))
            self.assertEqual(canonical(original.find(tag)),canonical(alternate.find(tag)))

    def test_random_plan_rejects_changed_or_skipped_targets(self):
        generator=load('ci-random-plan.py')
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory);scheme=root/'Kin.xcodeproj/xcshareddata/xcschemes/Kin.xcscheme'
            scheme.parent.mkdir(parents=True)
            source=(ROOT/'Kin.xcodeproj/xcshareddata/xcschemes/Kin.xcscheme').read_text()
            scheme.write_text(source.replace('skipped="NO"','skipped="YES"',1))
            with self.assertRaises(ValueError):generator.generate(root)
            self.assertFalse((root/'KinRandomOrder.xctestplan').exists())
            self.assertFalse(scheme.with_name('KinRandomOrder.xcscheme').exists())

    def test_allowlist_drops_private_payloads(self):
        m=load('ci-observe.py');ids={'KinUITests/KinUITests/testFoo'}
        self.assertEqual(m.parse("Test Case '-[KinUITests.KinUITests testFoo]' started. SECRET",ids),{'kind':'test','id':'KinUITests/KinUITests/testFoo','event':'started'})
        self.assertIsNone(m.parse("Test Case '-[Private.Secret testName]' started. SECRET",ids))
        self.assertEqual(m.parse('t = 5.0s Type PRIVATE_FIELD SECRET',ids),{'kind':'action','stage':'type'})
        self.assertEqual(m.parse('KIN_CI_AUTH authorized SECRET',ids),{'kind':'authorization','state':'authorized'})
        self.assertEqual(m.parse('KIN_CI_DELETE before=201 SECRET',ids),{'kind':'deletion','stage':'before','length':201})
        self.assertEqual(m.parse('KIN_CI_DELETE after=169 completed=true SECRET',ids),{'kind':'deletion','stage':'after','length':169,'completed':True})
        self.assertEqual(m.parse('KIN_CI_CONTACT candidate=1 inside=false SECRET',ids),{'kind':'contact_candidate','index':1,'inside':False})
        self.assertEqual(m.parse('KIN_CI_CONTACT count=2 SECRET',ids),{'kind':'contact_candidates','count':2})
    def test_cleanup_markers_are_fixed_and_redacted(self):
        m=load('ci-observe.py')
        self.assertEqual(m.parse('KIN_CI_CONTACT_CLEANUP native-full failed PRIVATE_PAYLOAD',set()),
                         {'kind':'contact_cleanup','scope':'native-full','status':'failed'})
        self.assertIsNone(m.parse('KIN_CI_CONTACT_CLEANUP arbitrary failed',set()))
        self.assertIsNone(m.parse('KIN_CI_CONTACT_CLEANUP native-full unknown',set()))

    def test_passing_run_requires_exact_verified_cleanup_markers(self):
        m=load('ci-observe.py')
        group=next(g for g in m.shards.GROUPS[1:] if any(ident in m.CLEANUP_SCOPES for ident in m.shards.selections(g)))
        ids=m.shards.selections(group)
        expected=sorted(m.CLEANUP_SCOPES[ident] for ident in ids if ident in m.CLEANUP_SCOPES)
        self.assertTrue(expected)
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d); fake=p/'xcodebuild'; env=dict(os.environ,PATH=d+':'+os.environ['PATH'],
                RUNNER_TEMP=d,KIN_CI_SIMULATOR='synthetic')
            def run(markers, code=0):
                fake.write_text('#!/bin/sh\necho "KIN_CI_AUTH authorized"\n'
                    + ''.join(f'echo "KIN_CI_CONTACT_CLEANUP {scope} {status} PRIVATE_PAYLOAD"\n' for scope,status in markers)
                    + f'exit {code}\n')
                fake.chmod(0o755)
                return subprocess.run([sys.executable,str(ROOT/'scripts/ci-observe.py'),group],
                                      cwd=ROOT,env=env,capture_output=True,text=True)
            verified=[(scope,'verified') for scope in expected]
            self.assertEqual(run(verified).returncode,0)
            for markers in (verified[:-1], verified+[verified[0]],
                            [(expected[0],'failed')]+verified[1:],
                            [(expected[0],'empty')]+verified[1:]):
                with self.subTest(markers=markers):
                    outcome=run(markers)
                    self.assertNotEqual(outcome.returncode,0)
                    self.assertNotIn('PRIVATE_PAYLOAD',outcome.stdout)
            outcome=run([(expected[0],'failed')],code=65)
            self.assertNotEqual(outcome.returncode,0)
            self.assertIn(f'CI_CONTACT_CLEANUP {expected[0]} failed',outcome.stdout)
            events=[json.loads(line) for line in (p/'KinTests-progress.jsonl').read_text().splitlines()]
            self.assertIn({'kind':'contact_cleanup','scope':expected[0],
                           'status':'failed','elapsed':events[1]['elapsed']},events)
            self.assertNotIn('PRIVATE_PAYLOAD',(p/'KinTests-progress.jsonl').read_text())
            for markers, state in (([], 'missing'),
                                   ([(expected[0],'verified')]*2, 'duplicate')):
                outcome=run(markers,code=65)
                self.assertEqual(outcome.returncode,65)
                self.assertIn(f'CI_CONTACT_CLEANUP_ACCOUNTING {expected[0]} {state}',outcome.stderr)
                events=[json.loads(line) for line in (p/'KinTests-progress.jsonl').read_text().splitlines()]
                self.assertTrue(any(e.get('kind')=='contact_cleanup_accounting' and e.get('scope')==expected[0] and e.get('status')==state for e in events))

    def test_live_test_events_are_allowlisted_and_do_not_emit_raw_output(self):
        shards=load('ci-test-shards.py')
        ident=shards.selections('ui-3')[0]
        _,klass,method=ident.split('/')
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d);fake=p/'xcodebuild'
            fake.write_text('#!/bin/sh\n'
                            + f'echo "Test Case \'-[KinUITests.{klass} {method}]\' started. PRIVATE_PAYLOAD"\n'
                            + 'echo "KIN_CI_AUTH authorized PRIVATE_PAYLOAD"\n'
                            + f'echo "Test Case \'-[KinUITests.{klass} {method}]\' failed. PRIVATE_PAYLOAD"\n'
                            + 'exit 1\n')
            fake.chmod(0o755)
            env=dict(os.environ,PATH=d+':'+os.environ['PATH'],RUNNER_TEMP=d,
                     KIN_CI_SIMULATOR='synthetic')
            run=subprocess.run([sys.executable,str(ROOT/'scripts/ci-observe.py'),'ui-3'],
                               cwd=ROOT,env=env,capture_output=True,text=True)
            self.assertNotEqual(run.returncode,0)
            self.assertIn(f'CI_TEST started {ident} elapsed=',run.stdout)
            self.assertIn(f'CI_TEST failed {ident} elapsed=',run.stdout)
            self.assertNotIn('PRIVATE_PAYLOAD',run.stdout)
            self.assertNotIn('PRIVATE_PAYLOAD',(p/'KinTests-progress.jsonl').read_text())

    def test_original_and_cleanup_failures_are_both_retained(self):
        m=load('ci-observe.py')
        group=next(g for g in m.shards.GROUPS[1:] if any(i in m.CLEANUP_SCOPES for i in m.shards.selections(g)))
        ident=next(i for i in m.shards.selections(group) if i in m.CLEANUP_SCOPES)
        _,klass,method=ident.split('/')
        scope=m.CLEANUP_SCOPES[ident]
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d);fake=p/'xcodebuild'
            fake.write_text('#!/bin/sh\n'
                            + f'echo "Test Case \'-[KinUITests.{klass} {method}]\' failed. PRIVATE_PAYLOAD"\n'
                            + f'echo "KIN_CI_CONTACT_CLEANUP {scope} failed PRIVATE_PAYLOAD"\n'
                            + 'exit 65\n')
            fake.chmod(0o755)
            env=dict(os.environ,PATH=d+':'+os.environ['PATH'],RUNNER_TEMP=d,KIN_CI_SIMULATOR='synthetic')
            run=subprocess.run([sys.executable,str(ROOT/'scripts/ci-observe.py'),group],
                               cwd=ROOT,env=env,capture_output=True,text=True)
            self.assertNotEqual(run.returncode,0)
            events=[json.loads(line) for line in (p/'KinTests-progress.jsonl').read_text().splitlines()]
            self.assertTrue(any(e.get('kind')=='test' and e.get('id')==ident and e.get('event')=='failed' for e in events))
            self.assertTrue(any(e.get('kind')=='contact_cleanup' and e.get('scope')==scope and e.get('status')=='failed' for e in events))
            self.assertNotIn('PRIVATE_PAYLOAD',(p/'KinTests-progress.jsonl').read_text())
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
