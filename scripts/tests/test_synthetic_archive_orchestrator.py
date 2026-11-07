"""Only fake tools and synthetic data; never sign or contact a provider."""
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
import zipfile
from unittest import mock

spec = importlib.util.spec_from_file_location('orchestrator', Path(__file__).resolve().parents[1] / 'synthetic-archive-orchestrator.py')
orchestrator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(orchestrator)


class SyntheticOrchestratorTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory(); self.addCleanup(self.root.cleanup)
        self.profiles = tempfile.TemporaryDirectory(); self.addCleanup(self.profiles.cleanup)
        os.chmod(self.profiles.name, 0o700)
        self.commands = []; self.calls = []; self.failure = None; self.registered = False; self.cleanup_checks = 0
        class FakeSearch:
            def __init__(self): self.paths = ['/synthetic/original.keychain']; self.writes = []
            def read(self): return list(self.paths)
            def write(self, paths): self.paths = list(paths); self.writes.append(list(paths))
        self.search = FakeSearch()
        self.env = mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted', 'GITHUB_SHA': 'a' * 40})
        self.env.start(); self.addCleanup(self.env.stop)
        self.patches = [mock.patch.object(orchestrator._candidate._evidence, 'main'),
                        mock.patch.object(orchestrator._candidate._evidence, 'command', return_value='b' * 40),
                        mock.patch.object(orchestrator._candidate._signature, 'verify', return_value=True),
                        mock.patch.object(orchestrator._candidate, '_binary_uuid', return_value='synthetic-uuid'),
                        mock.patch.object(orchestrator._candidate, '_entitlements', return_value={
                            'application-identifier': 'ABCDEFGHIJ.com.intriguingideas.Kin',
                            'com.apple.developer.team-identifier': 'ABCDEFGHIJ', 'get-task-allow': False})]
        for patch in self.patches: patch.start(); self.addCleanup(patch.stop)

    def security(self, *args):
        self.calls.append(args[0])
        if args[0] == 'create-keychain':
            Path(args[-1]).write_bytes(b'fake'); self.registered = True
        if args[0] == 'delete-keychain':
            if self.failure == 'cleanup': raise OSError('private')
            Path(args[-1]).unlink(missing_ok=True); self.registered = False

    def runner(self, command, timeout):
        self.commands.append((command, timeout))
        self.assertTrue(orchestrator._run_bounded((sys.executable, '-c', 'pass'), 5,
                                                 cwd=str(Path(self.root.name).resolve()), env={'PATH': '/usr/bin:/bin'}))
        if len(self.commands) == 1:
            if self.failure == 'archive': return False
            archive = Path(command[command.index('-archivePath') + 1])
            app = archive / 'Products/Applications/Kin.app'; app.mkdir(parents=True)
            self.make_app(app)
            dsym = archive / 'dSYMs/Kin.app.dSYM/Contents/Resources/DWARF/Kin'
            dsym.parent.mkdir(parents=True); dsym.write_bytes(b'dsym')
        else:
            if self.failure == 'export': return False
            options = plistlib.loads(Path(command[command.index('-exportOptionsPlist') + 1]).read_bytes())
            self.assertEqual(options['destination'], 'export')
            self.assertEqual(options['signingStyle'], 'manual')
            export = Path(command[command.index('-exportPath') + 1])
            app = export / 'Payload/Kin.app'; app.mkdir(parents=True); self.make_app(app)
            with zipfile.ZipFile(export / 'Kin.ipa', 'w') as ipa:
                for item in app.iterdir(): ipa.write(item, 'Payload/Kin.app/' + item.name)
            if self.failure == 'ipa': (app / 'Kin').write_bytes(b'changed')
        return True

    def make_app(self, app):
        info = {'CFBundleIdentifier': 'com.intriguingideas.Kin', 'CFBundleExecutable': 'Kin',
                'CFBundleShortVersionString': '1.3.0', 'CFBundleVersion': '7'}
        (app / 'Info.plist').write_bytes(plistlib.dumps(info))
        (app / 'embedded.mobileprovision').write_bytes(b'kin-synthetic-profile-only')
        (app / 'Kin').write_bytes(b'executable')

    def run_case(self):
        def cleanup_check(keychain, profile):
            self.cleanup_checks += 1
            return (self.failure != 'verify-cleanup' and not self.registered and not keychain.exists() and
                    not profile.exists() and self.search.read() == ['/synthetic/original.keychain'])
        return orchestrator.run_synthetic(self.root.name, str(Path(self.profiles.name).resolve()),
                                          runner=self.runner, security_backend=self.security,
                                          cleanup_check=cleanup_check, search_list=self.search)

    def test_full_synthetic_path_verifies_then_cleans_before_return(self):
        result = self.run_case()
        self.assertEqual(result['kind'], 'synthetic-control-flow-not-build-attestation')
        self.assertEqual([timeout for _, timeout in self.commands], [1200, 600])
        self.assertNotIn('-allowProvisioningUpdates', sum((list(c) for c, _ in self.commands), []))
        settings = dict(part.split('=', 1) for part in self.commands[0][0] if '=' in part)
        self.assertEqual(settings['DEVELOPMENT_TEAM'], 'ABCDEFGHIJ')
        self.assertEqual(settings['PROVISIONING_PROFILE_SPECIFIER'], str(uuid.UUID(int=1)).upper())
        self.assertTrue(settings['OTHER_CODE_SIGN_FLAGS'].startswith('--keychain /'))
        self.assertEqual(list(Path(self.root.name).iterdir()), [])
        self.assertEqual(list(Path(self.profiles.name).iterdir()), [])
        self.assertIn('delete-keychain', self.calls)
        self.assertEqual(self.search.read(), ['/synthetic/original.keychain'])
        self.assertEqual(len(self.search.writes), 2)

    def test_failed_stages_and_cleanup_cannot_return_success(self):
        for failure in ('archive', 'export', 'ipa', 'cleanup'):
            with self.subTest(failure=failure):
                self.failure = failure; self.commands = []; self.calls = []; self.cleanup_checks = 0
                with self.assertRaises(orchestrator._keychain.TransactionFailed): self.run_case()
                self.assertIn('delete-keychain', self.calls)
                self.assertEqual(self.cleanup_checks, 1)
                self.assertEqual(list(Path(self.root.name).iterdir()), [])
                self.assertEqual(list(Path(self.profiles.name).iterdir()), [])

    def test_preflight_failure_prevents_keychain_and_commands(self):
        with mock.patch.object(orchestrator._candidate._evidence, 'main', side_effect=ValueError('private')):
            with self.assertRaises(ValueError): self.run_case()
        self.assertEqual(self.calls, []); self.assertEqual(self.commands, [])

    def test_unverified_cleanup_prevents_success(self):
        self.failure = 'verify-cleanup'
        with self.assertRaises(ValueError): self.run_case()
        self.assertEqual(list(Path(self.root.name).iterdir()), [])
        self.assertEqual(list(Path(self.profiles.name).iterdir()), [])

    def test_post_cleanup_preflight_failure_prevents_success(self):
        with mock.patch.object(orchestrator._candidate._evidence, 'main',
                               side_effect=[None, None, None, None, ValueError('private')]):
            with self.assertRaises(ValueError): self.run_case()
        self.assertIn('delete-keychain', self.calls)
        self.assertEqual(list(Path(self.root.name).iterdir()), [])
        self.assertEqual(list(Path(self.profiles.name).iterdir()), [])

    def test_source_change_after_cleanup_prevents_success(self):
        calls = []
        def preflight():
            calls.append(True)
            if len(calls) == 5: os.environ['GITHUB_SHA'] = 'c' * 40
        with mock.patch.object(orchestrator._candidate._evidence, 'main', side_effect=preflight):
            with self.assertRaises(ValueError): self.run_case()
        self.assertEqual(self.cleanup_checks, 1)
        self.assertEqual(list(Path(self.root.name).iterdir()), [])

    def test_bounded_runner_reports_exit_timeout_and_disabled_production(self):
        for code, reason in [('import sys;sys.exit(3)', 'exit'), ('import time;time.sleep(30)', 'timeout')]:
            with self.subTest(reason=reason), self.assertRaises(orchestrator.BoundedProcessError) as error:
                orchestrator._run_bounded((sys.executable, '-c', code), 0.15,
                                          cwd=str(Path(self.root.name).resolve()), env={'PATH': '/usr/bin:/bin'})
            self.assertEqual(error.exception.reason, reason)
            self.assertFalse(error.exception.cleanup_failed)
        with self.assertRaises(orchestrator.BoundedProcessError) as error:
            orchestrator.run_production_xcode()
        self.assertEqual(error.exception.reason, 'production-disabled')
        with self.assertRaises(ValueError):
            orchestrator._run_bounded((sys.executable, '-c', 'pass'), 1, cwd=str(Path(self.root.name).resolve()),
                                      env={'UNREVIEWED_VARIABLE': 'fake'})

    def test_timeout_preserves_cleanup_failure_category(self):
        class FakeProcess:
            pid = 123
            def wait(self, timeout): raise subprocess.TimeoutExpired('redacted', timeout)
        with mock.patch.object(orchestrator.subprocess, 'Popen', return_value=FakeProcess()), \
             mock.patch.object(orchestrator.os, 'killpg', side_effect=OSError('private')):
            with self.assertRaises(orchestrator.BoundedProcessError) as error:
                orchestrator._run_bounded(('fake',), 1, cwd=str(Path(self.root.name).resolve()), env={})
        self.assertEqual(error.exception.reason, 'timeout')
        self.assertTrue(error.exception.cleanup_failed)
        self.assertNotIn('private', str(error.exception))

    def test_timeout_stops_same_group_child_before_it_writes(self):
        marker = Path(self.root.name) / 'marker'
        child = 'import time,pathlib;time.sleep(0.6);pathlib.Path(' + repr(str(marker)) + ').write_text("late")'
        parent = 'import subprocess,time;subprocess.Popen([' + repr(sys.executable) + ',"-c",' + repr(child) + ']);time.sleep(30)'
        with self.assertRaises(orchestrator.BoundedProcessError) as error:
            orchestrator._run_bounded((sys.executable, '-c', parent), 0.2,
                                      cwd=str(Path(self.root.name).resolve()), env={'PATH': '/usr/bin:/bin'})
        self.assertEqual(error.exception.reason, 'timeout')
        self.assertFalse(error.exception.cleanup_failed)
        time.sleep(0.8)
        self.assertFalse(marker.exists())

    def test_process_failure_preserves_cause_and_cleanup_failure(self):
        def fail(_command, _timeout):
            raise orchestrator.BoundedProcessError('timeout', cleanup_failed=True)
        with self.assertRaises(orchestrator._keychain.TransactionFailed) as error:
            orchestrator.run_synthetic(self.root.name, str(Path(self.profiles.name).resolve()),
                                       runner=fail, security_backend=self.security, cleanup_check=lambda *_: True,
                                       search_list=self.search)
        self.assertEqual(error.exception.primary_error, 'process:timeout')
        self.assertIn('process:cleanup-failed', error.exception.cleanup_errors)
        self.assertIn('delete-keychain', self.calls)

    def test_changed_search_list_is_not_overwritten(self):
        def changed(command, timeout):
            self.search.paths = ['/synthetic/changed.keychain']
            return False
        with self.assertRaises(orchestrator._keychain.TransactionFailed) as error:
            orchestrator.run_synthetic(self.root.name, str(Path(self.profiles.name).resolve()),
                                       runner=changed, security_backend=self.security,
                                       cleanup_check=lambda *_: False, search_list=self.search)
        self.assertIn('search-list:changed', error.exception.cleanup_errors)
        self.assertEqual(self.search.read(), ['/synthetic/changed.keychain'])
        self.assertEqual(len(self.search.writes), 1)

    def test_search_list_write_that_mutates_then_fails_is_restored(self):
        original_write = self.search.write
        calls = []
        def uncertain_write(paths):
            calls.append(True); original_write(paths)
            if len(calls) == 1: raise OSError('private')
        with mock.patch.object(self.search, 'write', side_effect=uncertain_write):
            with self.assertRaises(orchestrator._keychain.TransactionFailed) as error: self.run_case()
        self.assertTrue(error.exception.primary_failed)
        self.assertEqual(self.search.read(), ['/synthetic/original.keychain'])
        self.assertIn('delete-keychain', self.calls)
        self.assertEqual(self.commands, [])

    def test_search_list_restore_failure_cannot_return_success(self):
        original_write = self.search.write
        calls = []
        def fail_restore(paths):
            calls.append(True)
            if len(calls) == 2: raise OSError('private')
            original_write(paths)
        with mock.patch.object(self.search, 'write', side_effect=fail_restore):
            with self.assertRaises(orchestrator._keychain.TransactionFailed) as error: self.run_case()
        self.assertIn('search-list:filesystem-error', error.exception.cleanup_errors)
        self.assertIn('independent-cleanup:unverified', error.exception.cleanup_errors)
        self.assertIn('delete-keychain', self.calls)

    def test_security_search_adapter_parses_without_emitting_paths(self):
        adapter = orchestrator.SecuritySearchList()
        with mock.patch.object(orchestrator._candidate, '_bounded_output',
                               return_value=b'"/synthetic/one keychain"\n"/synthetic/two"\n'):
            self.assertEqual(adapter.read(), ['/synthetic/one keychain', '/synthetic/two'])
        with mock.patch.object(orchestrator._keychain, '_security') as backend:
            adapter.write(['/synthetic/one keychain'])
            backend.assert_called_once_with('list-keychains', '-d', 'user', '-s', '/synthetic/one keychain')
        with mock.patch.object(orchestrator._keychain, '_security', side_effect=OSError('private path')):
            with self.assertRaises(ValueError) as error: adapter.write(['/synthetic/one'])
            self.assertNotIn('private', str(error.exception))
        for malformed in (b'', b'"/unterminated', b'"relative"', b'"/duplicate"\n"/duplicate"'):
            with self.subTest(malformed=malformed), \
                 mock.patch.object(orchestrator._candidate, '_bounded_output', return_value=malformed), \
                 self.assertRaises(ValueError):
                adapter.read()

    def test_reviewed_plan_rejects_untrusted_fields(self):
        entitlements = {'application-identifier': 'ABCDEFGHIJ.com.intriguingideas.Kin',
                        'com.apple.developer.team-identifier': 'ABCDEFGHIJ', 'get-task-allow': False}
        reviewed = {'team_id': 'ABCDEFGHIJ', 'certificate_sha256': 'a' * 64, 'profile_sha256': 'b' * 64,
                    'version': '1.3.0', 'build': '7', 'expected_entitlements': entitlements}
        root = Path(self.root.name).resolve(); keychain = root / 'keychain'
        profile_id = str(uuid.UUID(int=1)).upper()
        for changed in (dict(reviewed, team_id='bad;argument'), dict(reviewed, certificate_sha256='bad'),
                        dict(reviewed, expected_entitlements=dict(entitlements, **{'get-task-allow': True}))):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                orchestrator._reviewed_plan(changed, profile_id, root, keychain)
        with self.assertRaises(ValueError):
            orchestrator._reviewed_plan(reviewed, 'invalid', root, keychain)
        with self.assertRaises(ValueError):
            orchestrator._reviewed_plan(reviewed, profile_id, root / 'unsafe path', root / 'unsafe path/keychain')


if __name__ == '__main__': unittest.main()
