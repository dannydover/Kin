"""Tests exercise a fake verifier only; no real signing or credentials."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('signature', Path(__file__).resolve().parents[1] / 'verify-signature-integrity.py')
signature = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signature)


class SignatureIntegrityTests(unittest.TestCase):
    def test_invocation_is_bounded_and_suppresses_output(self):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root) / 'Kin.app'; app.mkdir()
            with mock.patch.object(signature.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
                self.assertTrue(signature.verify(app))
            args, options = run.call_args
            self.assertEqual(args[0], ['/usr/bin/codesign', '--verify', '--strict', '--all-architectures', str(app)])
            self.assertEqual(options['timeout'], 60)
            self.assertEqual(options['stdout'], subprocess.DEVNULL)
            self.assertEqual(options['stderr'], subprocess.DEVNULL)
            self.assertEqual(options['stdin'], subprocess.DEVNULL)

    def test_failures_are_closed_and_sanitized(self):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root) / 'Kin.app'; app.mkdir()
            for outcome in (subprocess.CompletedProcess([], 1), OSError('private'), subprocess.TimeoutExpired('private', 60)):
                with self.subTest(outcome=type(outcome).__name__):
                    with mock.patch.object(signature.subprocess, 'run', side_effect=outcome if isinstance(outcome, Exception) else None, return_value=outcome):
                        with self.assertRaises(signature.SignatureIntegrityError) as error:
                            signature.verify(app)
                        self.assertNotIn('private', str(error.exception))

    def test_rejects_missing_wrong_type_and_symlink(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root); app = root / 'Kin.app'; app.mkdir()
            link = root / 'Link.app'; link.symlink_to(app, target_is_directory=True)
            for candidate in (root / 'missing.app', root, link):
                with self.subTest(candidate=candidate), mock.patch.object(signature.subprocess, 'run') as run:
                    with self.assertRaises(signature.SignatureIntegrityError): signature.verify(candidate)
                    run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
