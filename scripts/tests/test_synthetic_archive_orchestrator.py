"""Only fake tools and synthetic data; never sign or contact a provider."""
import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
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
            return self.failure != 'verify-cleanup' and not self.registered and not keychain.exists() and not profile.exists()
        return orchestrator.run_synthetic(self.root.name, str(Path(self.profiles.name).resolve()),
                                          runner=self.runner, security_backend=self.security, cleanup_check=cleanup_check)

    def test_full_synthetic_path_verifies_then_cleans_before_return(self):
        result = self.run_case()
        self.assertEqual(result['kind'], 'synthetic-control-flow-not-build-attestation')
        self.assertEqual([timeout for _, timeout in self.commands], [1200, 600])
        self.assertNotIn('-allowProvisioningUpdates', sum((list(c) for c, _ in self.commands), []))
        self.assertEqual(list(Path(self.root.name).iterdir()), [])
        self.assertEqual(list(Path(self.profiles.name).iterdir()), [])
        self.assertIn('delete-keychain', self.calls)

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


if __name__ == '__main__': unittest.main()
