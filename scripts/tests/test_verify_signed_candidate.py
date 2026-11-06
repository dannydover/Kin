"""Synthetic candidate checks; never sign or use Apple credentials."""
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('candidate', Path(__file__).resolve().parents[1] / 'verify-signed-candidate.py')
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'Kin.app'; self.app.mkdir()
        self.info = {'CFBundleIdentifier': 'com.intriguingideas.Kin', 'CFBundleExecutable': 'Kin',
                     'CFBundleShortVersionString': '1.3.0', 'CFBundleVersion': '7'}
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))
        self.profile = b'synthetic-profile'; (self.app / 'embedded.mobileprovision').write_bytes(self.profile)
        self.entitlements = {'application-identifier': 'ABCDEFGHIJ.com.intriguingideas.Kin',
                             'com.apple.developer.team-identifier': 'ABCDEFGHIJ', 'get-task-allow': False}
        self.inputs = {'team_id': 'ABCDEFGHIJ', 'certificate_sha256': 'a' * 64,
                       'profile_sha256': hashlib.sha256(self.profile).hexdigest(),
                       'version': '1.3.0', 'build': '7', 'expected_entitlements': self.entitlements}

    def check(self, actual=None, **overrides):
        args = dict(self.inputs, **overrides)
        with mock.patch.object(candidate, '_entitlements', return_value=self.entitlements if actual is None else actual), \
             mock.patch.object(candidate._signature, 'verify', return_value=True) as verify:
            result = candidate._verify_candidate(self.app, **args)
            verify.assert_called_once_with(self.app, args['team_id'], args['certificate_sha256'])
            return result

    def test_integrated_checks_call_signer_and_compare_reviewed_inputs(self):
        self.assertTrue(self.check())

    def test_preflight_wraps_candidate_and_failures_do_not_succeed(self):
        events = []
        def preflight(): events.append('preflight')
        def verify(*_args, **_kwargs): events.append('candidate'); return True
        with mock.patch.object(candidate._evidence, 'main', side_effect=preflight), \
             mock.patch.object(candidate, '_verify_candidate', side_effect=verify):
            self.assertTrue(candidate.verify_with_preflight(self.app, **self.inputs))
        self.assertEqual(events, ['preflight', 'candidate', 'preflight'])
        for outcomes, candidate_result in (([ValueError('first')], True), ([None, ValueError('second')], True), ([None], False)):
            with self.subTest(outcomes=outcomes, candidate_result=candidate_result), \
                 mock.patch.object(candidate._evidence, 'main', side_effect=outcomes), \
                 mock.patch.object(candidate, '_verify_candidate', return_value=candidate_result):
                with self.assertRaises((ValueError, candidate.CandidateError)):
                    candidate.verify_with_preflight(self.app, **self.inputs)

    def test_rejects_wrong_profile_metadata_and_entitlements(self):
        for changes in ({'profile_sha256': 'b' * 64}, {'version': '1.3.1'}, {'build': '8'},
                        {'expected_entitlements': {'application-identifier': 'other'}}):
            with self.subTest(changes=changes), self.assertRaises(candidate.CandidateError): self.check(**changes)
        for entitlements in ({'get-task-allow': True}, {'get-task-allow': 0}, {}):
            with self.subTest(entitlements=entitlements), self.assertRaises(candidate.CandidateError): self.check(actual=entitlements)
        changed = dict(self.entitlements, **{'get-task-allow': 0})
        with self.assertRaises(candidate.CandidateError): self.check(expected_entitlements=changed)
        for field, value in [('com.apple.developer.team-identifier', 'ZZZZZZZZZZ'),
                             ('application-identifier', 'ABCDEFGHIJ.com.example.other')]:
            changed = dict(self.entitlements); changed[field] = value
            with self.subTest(field=field), self.assertRaises(candidate.CandidateError):
                self.check(actual=changed, expected_entitlements=changed)

    def test_signature_failure_and_symlink_profile_fail(self):
        with mock.patch.object(candidate, '_entitlements', return_value=self.entitlements), \
             mock.patch.object(candidate._signature, 'verify', side_effect=candidate._signature.SignatureIntegrityError('private')):
            with self.assertRaises(candidate.CandidateError) as error: candidate._verify_candidate(self.app, **self.inputs)
            self.assertNotIn('private', str(error.exception))
        p = self.app / 'embedded.mobileprovision'; p.unlink(); p.symlink_to(self.app / 'Info.plist')
        with self.assertRaises(candidate.CandidateError): self.check()

    def test_real_child_output_is_bounded_and_reaped(self):
        real_popen = subprocess.Popen
        payload = plistlib.dumps(self.entitlements)
        def execute(code):
            return lambda _args, **kwargs: real_popen([sys.executable, '-c', code], **kwargs)
        with mock.patch.object(candidate.subprocess, 'Popen', side_effect=execute('import sys;sys.stdout.buffer.write(' + repr(payload) + ')')):
            self.assertEqual(candidate._entitlements(self.app), self.entitlements)
        with mock.patch.object(candidate.subprocess, 'Popen', side_effect=execute('import sys;sys.stdout.buffer.write(b"x"*70000)')):
            with self.assertRaises(candidate.CandidateError): candidate._entitlements(self.app)
        for code in ('import sys;sys.exit(1)', 'print("not a property list")'):
            with self.subTest(code=code), mock.patch.object(candidate.subprocess, 'Popen', side_effect=execute(code)):
                with self.assertRaises(candidate.CandidateError): candidate._entitlements(self.app)
        with mock.patch.object(candidate.subprocess, 'Popen', side_effect=execute('import time;time.sleep(30)')), \
             mock.patch.object(candidate.time, 'monotonic', side_effect=[0, 61]):
            with self.assertRaises(candidate.CandidateError): candidate._entitlements(self.app)

    def test_inspection_and_cleanup_failures_are_both_preserved(self):
        read_fd, write_fd = os.pipe()
        self.addCleanup(os.close, write_fd)
        class FakeProcess:
            stdout = os.fdopen(read_fd, 'rb')
            def poll(self): return None
            def kill(self): raise OSError('private')
        with mock.patch.object(candidate.subprocess, 'Popen', return_value=FakeProcess()), \
             mock.patch.object(candidate.time, 'monotonic', side_effect=[0, 61]):
            with self.assertRaises(candidate.CandidateError) as error: candidate._entitlements(self.app)
            self.assertEqual(str(error.exception), 'entitlement inspection and process cleanup failed')


if __name__ == '__main__': unittest.main()
