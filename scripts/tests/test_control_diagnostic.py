"""Offline invariants for synthetic-only diagnostic instrumentation."""
import hashlib
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('control_diag',ROOT/'scripts/diagnose-control-events.py')
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)


class ControlDiagnosticTests(unittest.TestCase):
    def test_instrumentation_preserves_original_actions_and_conditions(self):
        names=['KinUITests/KinUITests.swift','KinUITests/IndexMembershipUITests.swift',
               'Kin/Views/PersonEditor.swift','Kin/ContentView.swift','Kin/KinApp.swift']
        before=[(ROOT/p).read_text() for p in names]
        after=d.instrument(*before)
        self.assertEqual(after[0].count('controls.element.tap()'),before[0].count('controls.element.tap()'))
        self.assertEqual(after[1].count('clear.tap()'),before[1].count('clear.tap()'))
        self.assertIn('Friend on and Save enabled',after[0])
        self.assertIn('assertClearSearchRestored(app)',after[1])
        self.assertIn('query = ""; category = nil; scope = .yours; searching = false',after[3])
        self.assertEqual(after[0].count('KIN_MARK target=friend stage=before'),1)
        self.assertEqual(after[1].count('KIN_MARK target=clear stage=before'),1)
        self.assertEqual(len(before),len(after))
        with self.assertRaises(ValueError):d.instrument(before[0].replace('controls.element.tap()','',1),*before[1:])

    def test_sanitization_rejects_extra_or_sensitive_fields(self):
        value={'eventMessage':'KIN_TOUCH friend=true clear=false switch=true button=false ms=100'}
        self.assertEqual(d.sanitize_event(value),{'kind':'touch','fields':['true','false','true','false'],'uptime_ms':100})
        self.assertIsNone(d.sanitize_event({'eventMessage':value['eventMessage']+' private'}))
        self.assertIsNone(d.sanitize_event({'eventMessage':'KIN_CLEAR stage=after queryEmpty=false name=private ms=3'}))
        self.assertIsNone(d.sanitize_event({'eventMessage':'unrelated user content'}))

    def test_calibration_fails_without_exact_markers_probe_geometry_and_heartbeats(self):
        def e(kind,fields,t):return {'kind':kind,'fields':fields,'uptime_ms':t}
        events=[e('probe',['true'],1),e('geometry',['friend'],2),e('heartbeat',[],950),
                e('mark',['friend','before'],1000),e('touch',['true','false','true','false'],1100),
                e('mark',['friend','after'],1200),e('heartbeat',[],1500)]
        self.assertTrue(d.calibrate(events,'friend'))
        for kind in ('probe','geometry','heartbeat','mark'):
            self.assertFalse(d.calibrate([x for x in events if x['kind']!=kind],'friend'))
        self.assertFalse(d.calibrate(events+[e('mark',['friend','after'],1201)],'friend'))
        self.assertFalse(d.calibrate(events,'clear'))
        gap = [e('probe',['true'],1),e('geometry',['friend'],2),e('heartbeat',[],950), e('mark',['friend','before'],1000), e('mark',['friend','after'],5000),e('heartbeat',[],5100)]
        self.assertFalse(d.calibrate(gap,'friend'))

    def test_result_identity_is_exact_and_rejects_duplicates(self):
        node={'testNodes':[{'nodeType':'Test Suite','children':[{'nodeType':'Test Case','nodeIdentifier':'KinUITests/testSynthetic()'}]}]}
        self.assertEqual(d.test_identities(node),['KinUITests/KinUITests/testSynthetic'])
        node['testNodes'][0]['children'].append(node['testNodes'][0]['children'][0])
        with self.assertRaises(ValueError):d.test_identities(node)
        with self.assertRaises(ValueError):d.test_identities({'testNodes':[{'nodeType':'Test Case','nodeIdentifier':'private'}]})

    def test_counts_refuse_incomplete_or_inconsistent_results(self):
        good={'result':'Passed','totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'expectedFailures':0}
        self.assertEqual(d.finalized_counts(good)['passedTests'],1)
        for changes in ({'totalTestCount':2},{'passedTests':0},{'result':'In Progress'},
                        {'passedTests':0,'failedTests':1},{'skippedTests':True}):
            with self.subTest(changes=changes),self.assertRaises(ValueError):d.finalized_counts({**good,**changes})

    def test_failure_messages_are_categorized_without_copying_text(self):
        text='failed - UI precondition failed: Friend on and Save enabled'
        self.assertEqual(d.failure_category(text),'friend_readiness')
        self.assertEqual(len(hashlib.sha256(text.encode()).hexdigest()),64)
        self.assertEqual(d.failure_category('name and unexpected failure'),'other')


if __name__=='__main__':unittest.main()
