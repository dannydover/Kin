"""Synthetic keychain lifecycle tests: never call macOS security or real keys."""
import importlib.util
import hashlib
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import threading
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('keychain', Path(__file__).resolve().parents[1] / 'isolated-signing-keychain.py')
keychain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(keychain)


class FakeSecurity:
    def __init__(self, fail=None):
        self.fail = set(fail or ()); self.calls = []

    def __call__(self, *args):
        action = args[0]; self.calls.append(action)
        if action in self.fail: raise RuntimeError('synthetic sensitive error')
        if action == 'create-keychain': Path(args[-1]).write_text('synthetic keychain')
        if action == 'delete-keychain': Path(args[-1]).unlink(missing_ok=True)


class KeychainLifecycleTests(unittest.TestCase):
    def exercise(self, root, fake, operation=lambda _: True):
        with mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
            return keychain.run_isolated(root, b'synthetic p12', 'synthetic password', operation, backend=fake)

    def test_success_removes_all_owned_files(self):
        with tempfile.TemporaryDirectory() as root:
            fake = FakeSecurity()
            self.assertTrue(self.exercise(root, fake))
            self.assertEqual(fake.calls, ['create-keychain', 'unlock-keychain', 'import',
                                          'set-key-partition-list', 'delete-keychain'])
            self.assertEqual(list(Path(root).iterdir()), [])

    def test_termination_during_import_cleans_owned_state_and_restores_handlers(self):
        with tempfile.TemporaryDirectory() as root:
            previous = {sig: signal.getsignal(sig) for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}
            class InterruptedSecurity(FakeSecurity):
                def __call__(self, *args):
                    if args[0] == 'import':
                        self.calls.append('import')
                        os.kill(os.getpid(), signal.SIGTERM)
                    return super().__call__(*args)
            fake = InterruptedSecurity()
            with self.assertRaises(keychain.TransactionFailed) as result: self.exercise(root, fake)
            self.assertEqual(result.exception.primary_error, 'interrupted')
            self.assertFalse(result.exception.cleanup_failed)
            self.assertIn('delete-keychain', fake.calls)
            self.assertEqual(list(Path(root).iterdir()), [])
            self.assertEqual({sig: signal.getsignal(sig) for sig in previous}, previous)

    def test_worker_thread_rejected_before_workspace_creation(self):
        with tempfile.TemporaryDirectory() as root, mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
            outcomes = []
            def worker():
                try:
                    keychain.run_isolated(root, b'synthetic', 'synthetic', lambda _: True, backend=FakeSecurity())
                except ValueError:
                    outcomes.append('rejected')
            thread = threading.Thread(target=worker); thread.start(); thread.join(timeout=5)
            self.assertFalse(thread.is_alive())
            self.assertEqual(outcomes, ['rejected'])
            self.assertEqual(list(Path(root).iterdir()), [])

    def test_signal_during_keychain_cleanup_is_reported(self):
        with tempfile.TemporaryDirectory() as root:
            class InterruptedCleanup(FakeSecurity):
                def __call__(self, *args):
                    if args[0] == 'delete-keychain':
                        self.calls.append('delete-keychain')
                        os.kill(os.getpid(), signal.SIGTERM)
                    return super().__call__(*args)
            fake = InterruptedCleanup()
            with self.assertRaises(keychain.TransactionFailed) as result: self.exercise(root, fake)
            self.assertTrue(result.exception.cleanup_failed)
            self.assertIn('keychain:interrupted', result.exception.cleanup_errors)
            self.assertEqual(list(Path(root).iterdir()), [])

    def test_unknown_existing_signal_handler_fails_before_keychain_creation(self):
        with tempfile.TemporaryDirectory() as root, mock.patch.object(keychain.signal, 'getsignal', return_value=None):
            fake = FakeSecurity()
            with self.assertRaises(keychain.TransactionFailed) as result: self.exercise(root, fake)
            self.assertEqual(result.exception.primary_error, 'validation-error')
            self.assertEqual(fake.calls, [])
            self.assertEqual(list(Path(root).iterdir()), [])

    def test_signal_handler_restore_failure_is_reported(self):
        with tempfile.TemporaryDirectory() as root:
            calls = []
            def fake_signal(sig, handler):
                calls.append((sig, handler))
                if len(calls) == 4: raise TypeError('private')
            with mock.patch.object(keychain.signal, 'signal', side_effect=fake_signal):
                with self.assertRaises(keychain.TransactionFailed) as result: self.exercise(root, FakeSecurity())
            self.assertIn('signal:restore-error', result.exception.cleanup_errors)
            self.assertEqual(len(calls), 6)
            self.assertEqual(list(Path(root).iterdir()), [])

    def test_owned_profile_exists_only_during_operation_and_is_removed(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as profiles:
            os.chmod(profiles, 0o700)
            data = b'synthetic-profile'; name = '11111111-2222-3333-4444-555555555555.mobileprovision'
            profile = {'directory': str(Path(profiles).resolve()), 'uuid': name[:-len('.mobileprovision')],
                       'bytes': data, 'sha256': hashlib.sha256(data).hexdigest()}
            def operation(_):
                self.assertEqual((Path(profiles) / name).read_bytes(), data)
                return True
            with mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
                self.assertTrue(keychain.run_isolated(root, b'synthetic', 'synthetic', operation,
                                                     backend=FakeSecurity(), profile=profile))
            self.assertFalse((Path(profiles) / name).exists())
            self.assertEqual(list(Path(root).iterdir()), [])

    def test_existing_profile_is_never_overwritten_or_removed(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as profiles:
            os.chmod(profiles, 0o700)
            data = b'synthetic-profile'; name = '11111111-2222-3333-4444-555555555555.mobileprovision'
            path = Path(profiles) / name; path.write_bytes(b'preexisting')
            profile = {'directory': str(Path(profiles).resolve()), 'uuid': name[:-len('.mobileprovision')],
                       'bytes': data, 'sha256': hashlib.sha256(data).hexdigest()}
            fake = FakeSecurity()
            with mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
                with self.assertRaises(keychain.TransactionFailed):
                    keychain.run_isolated(root, b'synthetic', 'synthetic', lambda _: True, backend=fake, profile=profile)
            self.assertEqual(path.read_bytes(), b'preexisting')
            self.assertEqual(fake.calls, [])

    def test_changed_profile_is_not_removed_and_cleanup_fails(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as profiles:
            os.chmod(profiles, 0o700)
            data = b'synthetic-profile'; name = '11111111-2222-3333-4444-555555555555.mobileprovision'
            path = Path(profiles) / name
            profile = {'directory': str(Path(profiles).resolve()), 'uuid': name[:-len('.mobileprovision')],
                       'bytes': data, 'sha256': hashlib.sha256(data).hexdigest()}
            def operation(_):
                path.unlink(); path.symlink_to(Path(root))
                return True
            with mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
                with self.assertRaises(keychain.TransactionFailed) as result:
                    keychain.run_isolated(root, b'synthetic', 'synthetic', operation, backend=FakeSecurity(), profile=profile)
            self.assertIn('profile:ownership-changed', result.exception.cleanup_errors)
            self.assertTrue(path.is_symlink())

    def test_invalid_profile_hash_and_nonprivate_directory_fail_closed(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as profiles:
            data = b'synthetic-profile'
            profile = {'directory': str(Path(profiles).resolve()), 'uuid': '11111111-2222-3333-4444-555555555555',
                       'bytes': data, 'sha256': '0' * 64}
            with mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
                with self.assertRaises(ValueError):
                    keychain.run_isolated(root, b'synthetic', 'synthetic', lambda _: True, backend=FakeSecurity(), profile=profile)
                profile['sha256'] = hashlib.sha256(data).hexdigest(); os.chmod(profiles, 0o755)
                with self.assertRaises(keychain.TransactionFailed):
                    keychain.run_isolated(root, b'synthetic', 'synthetic', lambda _: True, backend=FakeSecurity(), profile=profile)
            self.assertEqual(list(Path(profiles).iterdir()), [])

    def test_profile_is_removed_when_operation_is_interrupted(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as profiles:
            os.chmod(profiles, 0o700)
            data = b'synthetic-profile'
            profile = {'directory': str(Path(profiles).resolve()), 'uuid': '11111111-2222-3333-4444-555555555555',
                       'bytes': data, 'sha256': hashlib.sha256(data).hexdigest()}
            def interrupt(_):
                os.kill(os.getpid(), signal.SIGTERM)
                return True
            fake = FakeSecurity()
            with mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
                with self.assertRaises(keychain.TransactionFailed) as result:
                    keychain.run_isolated(root, b'synthetic', 'synthetic', interrupt, backend=fake, profile=profile)
            self.assertEqual(result.exception.primary_error, 'interrupted')
            self.assertFalse(result.exception.cleanup_failed)
            self.assertEqual(list(Path(profiles).iterdir()), [])
            self.assertIn('delete-keychain', fake.calls)

    def test_profile_cleanup_failure_does_not_erase_operation_failure(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as profiles:
            os.chmod(profiles, 0o700)
            data = b'synthetic-profile'
            profile = {'directory': str(Path(profiles).resolve()), 'uuid': '11111111-2222-3333-4444-555555555555',
                       'bytes': data, 'sha256': hashlib.sha256(data).hexdigest()}
            original_unlink = os.unlink
            def deny_owned(path, *args, **kwargs):
                if str(path).endswith('.mobileprovision'): raise OSError('private')
                return original_unlink(path, *args, **kwargs)
            with mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}), \
                 mock.patch.object(keychain.os, 'unlink', side_effect=deny_owned):
                with self.assertRaises(keychain.TransactionFailed) as result:
                    keychain.run_isolated(root, b'synthetic', 'synthetic', lambda _: False, backend=FakeSecurity(), profile=profile)
            self.assertEqual(result.exception.primary_error, 'validation-error')
            self.assertIn('profile:filesystem-error', result.exception.cleanup_errors)
            self.assertNotIn('private', str(result.exception))

    def test_modified_profile_is_preserved_but_partial_write_is_cleaned(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as profiles:
            os.chmod(profiles, 0o700)
            data = b'synthetic-profile'; name = '11111111-2222-3333-4444-555555555555.mobileprovision'
            path = Path(profiles) / name
            profile = {'directory': str(Path(profiles).resolve()), 'uuid': name[:-len('.mobileprovision')],
                       'bytes': data, 'sha256': hashlib.sha256(data).hexdigest()}
            def modify(_):
                path.write_bytes(b'changed-in-place')
                return True
            with mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
                with self.assertRaises(keychain.TransactionFailed) as result:
                    keychain.run_isolated(root, b'synthetic', 'synthetic', modify, backend=FakeSecurity(), profile=profile)
                self.assertIn('profile:content-or-ownership-changed', result.exception.cleanup_errors)
                self.assertEqual(path.read_bytes(), b'changed-in-place')
                path.unlink()
                with mock.patch.object(keychain.os, 'write', side_effect=OSError('synthetic')):
                    with self.assertRaises(keychain.TransactionFailed) as result:
                        keychain.run_isolated(root, b'synthetic', 'synthetic', lambda _: True, backend=FakeSecurity(), profile=profile)
                self.assertEqual(result.exception.primary_error, 'filesystem-error')
                self.assertFalse(result.exception.cleanup_failed)
                self.assertFalse(path.exists())

    def test_each_setup_failure_still_attempts_cleanup(self):
        for stage in ('create-keychain', 'unlock-keychain', 'import', 'set-key-partition-list'):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as root:
                fake = FakeSecurity({stage})
                with self.assertRaises(keychain.TransactionFailed) as result: self.exercise(root, fake)
                self.assertTrue(result.exception.primary_failed)
                self.assertIn('delete-keychain', fake.calls)
                self.assertNotIn('synthetic password', str(result.exception))
                self.assertEqual(list(Path(root).iterdir()), [])

    def test_operation_failure_is_preserved_when_cleanup_also_fails(self):
        with tempfile.TemporaryDirectory() as root:
            fake = FakeSecurity({'delete-keychain'})
            with self.assertRaises(keychain.TransactionFailed) as result:
                self.exercise(root, fake, operation=lambda _: False)
            self.assertTrue(result.exception.primary_failed)
            self.assertTrue(result.exception.cleanup_failed)
            self.assertEqual(result.exception.primary_error, 'validation-error')
            self.assertEqual(result.exception.cleanup_errors, ('keychain:other-error',))
            self.assertEqual(list(Path(root).iterdir()), [])

    def test_cleanup_failure_cannot_be_success(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(keychain.TransactionFailed) as result: self.exercise(root, FakeSecurity({'delete-keychain'}))
            self.assertFalse(result.exception.primary_failed)
            self.assertTrue(result.exception.cleanup_failed)

    def test_workspace_timeout_preserves_prior_failure(self):
        with tempfile.TemporaryDirectory() as root, mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
            def timeout(_): raise subprocess.TimeoutExpired('synthetic', 20)
            with self.assertRaises(keychain.TransactionFailed) as result:
                keychain.run_isolated(root, b'synthetic', 'synthetic', lambda _: False,
                                      backend=FakeSecurity(), remove_workspace=timeout)
            self.assertTrue(result.exception.primary_failed)
            self.assertTrue(result.exception.cleanup_failed)
            self.assertEqual(result.exception.primary_error, 'validation-error')
            self.assertEqual(result.exception.cleanup_errors, ('workspace:timeout',))

    def test_workspace_setup_failure_still_removes_owned_directory(self):
        with tempfile.TemporaryDirectory() as root, mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
            fake = FakeSecurity()
            with mock.patch.object(keychain.os, 'chmod', side_effect=OSError('synthetic')):
                with self.assertRaises(keychain.TransactionFailed) as result:
                    keychain.run_isolated(root, b'synthetic', 'synthetic', lambda _: True, backend=fake)
            self.assertTrue(result.exception.primary_failed)
            self.assertFalse(result.exception.cleanup_failed)
            self.assertEqual(fake.calls, [])
            self.assertEqual(list(Path(root).iterdir()), [])

    def test_cleanup_noop_is_detected(self):
        with tempfile.TemporaryDirectory() as root, mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
            with self.assertRaises(keychain.TransactionFailed) as result:
                keychain.run_isolated(root, b'synthetic', 'synthetic', lambda _: True,
                                      backend=FakeSecurity(), remove_workspace=lambda _: None)
            self.assertFalse(result.exception.primary_failed)
            self.assertTrue(result.exception.cleanup_failed)

    def test_hosted_runner_is_required_before_backend_call(self):
        with tempfile.TemporaryDirectory() as root, mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'self-hosted'}):
            fake = FakeSecurity()
            with self.assertRaises(ValueError): keychain.run_isolated(root, b'synthetic', 'synthetic', lambda _: True, backend=fake)
            self.assertEqual(fake.calls, [])
            self.assertEqual(list(Path(root).iterdir()), [])

    def test_missing_material_and_symlink_root_are_rejected(self):
        with tempfile.TemporaryDirectory() as parent, mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}):
            fake = FakeSecurity()
            with self.assertRaises(ValueError): keychain.run_isolated(parent, b'', 'synthetic', lambda _: True, backend=fake)
            link = Path(parent) / 'link'; link.symlink_to(parent, target_is_directory=True)
            with self.assertRaises(ValueError): keychain.run_isolated(str(link), b'synthetic', 'synthetic', lambda _: True, backend=fake)
            self.assertEqual(fake.calls, [])

    def test_workspace_creation_error_is_sanitized(self):
        with tempfile.TemporaryDirectory() as root, mock.patch.dict(os.environ, {'RUNNER_ENVIRONMENT': 'github-hosted'}), \
             mock.patch.object(keychain.tempfile, 'mkdtemp', side_effect=OSError('synthetic sensitive detail')):
            with self.assertRaises(keychain.TransactionFailed) as result:
                keychain.run_isolated(root, b'synthetic', 'synthetic', lambda _: True, backend=FakeSecurity())
            self.assertEqual(result.exception.primary_error, 'workspace-creation-error')
            self.assertNotIn('synthetic sensitive detail', str(result.exception))

    def test_security_subprocess_is_bounded_and_silent(self):
        with mock.patch.object(keychain.subprocess, 'run') as run:
            keychain._security('synthetic-operation', 'synthetic-argument')
            self.assertEqual(run.call_args.kwargs['timeout'], 20)
            self.assertTrue(run.call_args.kwargs['check'])
            self.assertEqual(run.call_args.kwargs['stdout'], subprocess.DEVNULL)
            self.assertEqual(run.call_args.kwargs['stderr'], subprocess.DEVNULL)

    def test_workspace_removal_is_bounded_and_silent(self):
        with mock.patch.object(keychain.subprocess, 'run') as run:
            keychain._remove_owned_workspace(Path('/tmp/synthetic-owned-workspace'))
            self.assertEqual(run.call_args.kwargs['timeout'], 20)
            self.assertTrue(run.call_args.kwargs['check'])
            self.assertEqual(run.call_args.kwargs['stdout'], subprocess.DEVNULL)
            self.assertEqual(run.call_args.kwargs['stderr'], subprocess.DEVNULL)


if __name__ == '__main__': unittest.main()
