"""Fake codesign tests; no certificates, credentials or signing operations."""
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('signature', Path(__file__).resolve().parents[1] / 'verify-signature-integrity.py')
signature = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signature)
TEAM = 'ABCDEFGHIJ'
LEAF = b'synthetic-public-certificate'
FINGERPRINT = hashlib.sha256(LEAF).hexdigest()


class SignatureIntegrityTests(unittest.TestCase):
    def test_bounded_signer_requirement_and_leaf_fingerprint(self):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root) / 'Kin.app'; app.mkdir()
            def fake(args, **kwargs):
                self.assertEqual(kwargs['timeout'], 60)
                for key in ('stdout', 'stderr', 'stdin'): self.assertEqual(kwargs[key], subprocess.DEVNULL)
                if '--verify' in args:
                    self.assertIn('--deep', args); self.assertIn('--strict', args)
                    self.assertIn('--all-architectures', args)
                    requirement = args[args.index('--test-requirement') + 1]
                    self.assertIn('anchor apple generic', requirement)
                    self.assertIn('com.intriguingideas.Kin', requirement)
                    self.assertIn(TEAM, requirement)
                else:
                    Path(args[args.index('--extract-certificates') + 1] + '0').write_bytes(LEAF)
                return subprocess.CompletedProcess(args, 0)
            with mock.patch.object(signature.subprocess, 'run', side_effect=fake) as run:
                self.assertTrue(signature.verify(app, TEAM, FINGERPRINT))
                self.assertEqual(run.call_count, 2)
                prefix = Path(run.call_args_list[-1].args[0][-2])
            self.assertFalse(prefix.parent.exists())

    def test_failed_commands_mismatch_and_timeout_fail_closed(self):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root) / 'Kin.app'; app.mkdir()
            for outcome in (subprocess.CompletedProcess([], 1), OSError('private'), subprocess.TimeoutExpired('private', 60)):
                with self.subTest(outcome=type(outcome).__name__):
                    with mock.patch.object(signature.subprocess, 'run', side_effect=outcome if isinstance(outcome, Exception) else None, return_value=outcome):
                        with self.assertRaises(signature.SignatureIntegrityError) as error: signature.verify(app, TEAM, FINGERPRINT)
                        self.assertNotIn('private', str(error.exception))
            def wrong_leaf(args, **kwargs):
                if '--extract-certificates' in args:
                    Path(args[args.index('--extract-certificates') + 1] + '0').write_bytes(b'wrong')
                return subprocess.CompletedProcess(args, 0)
            with mock.patch.object(signature.subprocess, 'run', side_effect=wrong_leaf):
                with self.assertRaises(signature.SignatureIntegrityError): signature.verify(app, TEAM, FINGERPRINT)
            for scenario in ('missing', 'extract-fails', 'symlink'):
                def incomplete(args, **kwargs):
                    if '--extract-certificates' in args:
                        if scenario == 'extract-fails': return subprocess.CompletedProcess(args, 1)
                        if scenario == 'symlink': Path(args[args.index('--extract-certificates') + 1] + '0').symlink_to(app)
                    return subprocess.CompletedProcess(args, 0)
                with self.subTest(scenario=scenario), mock.patch.object(signature.subprocess, 'run', side_effect=incomplete):
                    with self.assertRaises(signature.SignatureIntegrityError): signature.verify(app, TEAM, FINGERPRINT)

    def test_rejects_invalid_identity_missing_bundle_and_symlink(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root); app = root / 'Kin.app'; app.mkdir()
            link = root / 'Link.app'; link.symlink_to(app, target_is_directory=True)
            for path, team, fingerprint in ((root / 'missing.app', TEAM, FINGERPRINT),
                (root, TEAM, FINGERPRINT), (link, TEAM, FINGERPRINT), (app, 'bad" or true', FINGERPRINT),
                (app, TEAM, 'not-a-sha256')):
                with self.subTest(path=path, team=team), mock.patch.object(signature.subprocess, 'run') as run:
                    with self.assertRaises(signature.SignatureIntegrityError): signature.verify(path, team, fingerprint)
                    run.assert_not_called()

    def test_certificate_workspace_failure_is_not_success(self):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root) / 'Kin.app'; app.mkdir()
            with mock.patch.object(signature.tempfile, 'TemporaryDirectory', side_effect=OSError('private path')):
                with self.assertRaises(signature.SignatureIntegrityError) as error:
                    signature.verify(app, TEAM, FINGERPRINT)
                self.assertNotIn('private path', str(error.exception))


if __name__ == '__main__': unittest.main()
