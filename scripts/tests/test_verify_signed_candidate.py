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
import uuid
from unittest import mock

spec = importlib.util.spec_from_file_location('candidate', Path(__file__).resolve().parents[1] / 'verify-signed-candidate.py')
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)
keychain_spec = importlib.util.spec_from_file_location('keychain', Path(__file__).resolve().parents[1] / 'isolated-signing-keychain.py')
keychain = importlib.util.module_from_spec(keychain_spec)
keychain_spec.loader.exec_module(keychain)


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

    def test_archive_export_and_profile_transaction_synthetic_integration(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as profiles:
            os.chmod(profiles, 0o700)
            profile_uuid = str(uuid.UUID(int=1)).upper()
            profile = {'directory': str(Path(profiles).resolve()), 'uuid': profile_uuid,
                       'bytes': self.profile, 'sha256': hashlib.sha256(self.profile).hexdigest()}
            expected_uuid = str(uuid.UUID(int=2)).upper()
            calls = []
            def security(*args):
                calls.append(args[0])
                if args[0] == 'create-keychain': Path(args[-1]).write_bytes(b'synthetic')
                if args[0] == 'delete-keychain': Path(args[-1]).unlink(missing_ok=True)
            def operation(keychain_path):
                workspace = keychain_path.parent
                archive = workspace / 'Kin.xcarchive'
                archive_app = archive / 'Products/Applications/Kin.app'; archive_app.mkdir(parents=True)
                for app in (archive_app, self.app):
                    (app / 'Info.plist').write_bytes(plistlib.dumps(self.info))
                    (app / 'embedded.mobileprovision').write_bytes(self.profile)
                    (app / 'Kin').write_bytes(b'synthetic-executable')
                dsym = archive / 'dSYMs/Kin.app.dSYM/Contents/Resources/DWARF/Kin'
                dsym.parent.mkdir(parents=True); dsym.write_bytes(b'synthetic-dsym')
                self.assertTrue((Path(profiles) / (profile_uuid + '.mobileprovision')).is_file())
                result = candidate.verify_archive_export_with_preflight(archive, self.app, **self.inputs)
                self.assertEqual(result['source_sha'], 'a' * 40)
                self.assertEqual(result['uuid'], expected_uuid)
                self.assertEqual(result['kind'], 'local-observation-not-build-attestation')
                return True
            with mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted', 'GITHUB_SHA': 'a' * 40}), \
                 mock.patch.object(candidate._evidence, 'main') as preflight, \
                 mock.patch.object(candidate._evidence, 'command', return_value='b' * 40), \
                 mock.patch.object(candidate, '_entitlements', return_value=self.entitlements), \
                 mock.patch.object(candidate._signature, 'verify', return_value=True), \
                 mock.patch.object(candidate, '_binary_uuid', return_value=expected_uuid):
                self.assertTrue(keychain.run_isolated(root, b'synthetic', 'synthetic', operation,
                                                     backend=security, profile=profile))
                self.assertEqual(preflight.call_count, 2)
            self.assertIn('delete-keychain', calls)
            self.assertEqual(list(Path(root).iterdir()), [])
            self.assertEqual(list(Path(profiles).iterdir()), [])

    def test_uuid_parser_rejects_multiple_or_wrong_architecture(self):
        with tempfile.TemporaryDirectory() as root:
            binary = Path(root) / 'binary'; binary.write_bytes(b'synthetic')
            value = str(uuid.UUID(int=2)).upper()
            with mock.patch.object(candidate, '_bounded_output', return_value=('UUID: ' + value + ' (arm64) synthetic\n').encode()):
                self.assertEqual(candidate._binary_uuid(binary), value)
            for data in (('UUID: ' + value + ' (x86_64) synthetic\n').encode(), b'not a UUID\n',
                         ('UUID: ' + value + ' (arm64) synthetic\n') .encode() * 2):
                with self.subTest(data=data), mock.patch.object(candidate, '_bounded_output', return_value=data):
                    with self.assertRaises(candidate.CandidateError): candidate._binary_uuid(binary)

    def test_archive_uuid_mismatch_cannot_return_observation(self):
        archive = Path(self.temp.name) / 'Kin.xcarchive'; archive.mkdir()
        values = [str(uuid.UUID(int=2)).upper(), str(uuid.UUID(int=3)).upper()]
        with mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), \
             mock.patch.object(candidate._evidence, 'main') as preflight, \
             mock.patch.object(candidate._evidence, 'command', return_value='b' * 40), \
             mock.patch.object(candidate, '_verify_candidate', return_value=True), \
             mock.patch.object(candidate, '_binary_uuid', side_effect=values):
            with self.assertRaises(candidate.CandidateError):
                candidate.verify_archive_export_with_preflight(archive, self.app, **self.inputs)
            self.assertEqual(preflight.call_count, 1)

    def test_archive_mismatch_still_cleans_profile_and_keychain(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as profiles:
            os.chmod(profiles, 0o700)
            profile = {'directory': str(Path(profiles).resolve()), 'uuid': str(uuid.UUID(int=1)).upper(),
                       'bytes': self.profile, 'sha256': hashlib.sha256(self.profile).hexdigest()}
            values = [str(uuid.UUID(int=2)).upper(), str(uuid.UUID(int=3)).upper()]
            calls = []
            def security(*args):
                calls.append(args[0])
                if args[0] == 'create-keychain': Path(args[-1]).write_bytes(b'synthetic')
                if args[0] == 'delete-keychain': Path(args[-1]).unlink(missing_ok=True)
            def operation(keychain_path):
                archive = keychain_path.parent / 'Kin.xcarchive'; archive.mkdir()
                return candidate.verify_archive_export_with_preflight(archive, self.app, **self.inputs)
            with mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted', 'GITHUB_SHA': 'a' * 40}), \
                 mock.patch.object(candidate._evidence, 'main'), \
                 mock.patch.object(candidate._evidence, 'command', return_value='b' * 40), \
                 mock.patch.object(candidate, '_verify_candidate', return_value=True), \
                 mock.patch.object(candidate, '_binary_uuid', side_effect=values):
                with self.assertRaises(keychain.TransactionFailed):
                    keychain.run_isolated(root, b'synthetic', 'synthetic', operation, backend=security, profile=profile)
            self.assertIn('delete-keychain', calls)
            self.assertEqual(list(Path(root).iterdir()), [])
            self.assertEqual(list(Path(profiles).iterdir()), [])


if __name__ == '__main__': unittest.main()
