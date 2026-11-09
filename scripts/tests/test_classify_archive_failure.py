import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('category', ROOT / 'scripts/classify_archive_failure.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)

class ArchiveCategoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'private.log'

    def test_fixed_categories_and_no_raw_output(self):
        examples = {
            'No profiles for private-app were found: secret-path': 'missing-profile',
            'No signing certificate private-label found: secret-path': 'missing-certificate',
            "Provisioning profile private-label doesn't include signing certificate secret-path": 'profile-certificate-mismatch',
            'conflicting provisioning settings secret-path': 'signing-conflict',
            'requires a development team secret-path': 'missing-team',
            '/private/source.swift:7:4: error: secret-token': 'swift-compile',
            'linker command failed secret-path': 'linker',
            'build input file cannot be found secret-path': 'missing-input',
            'arbitrary secret-path': 'unclassified',
            'requires a development team\nconflicting provisioning settings': 'multiple',
        }
        for raw, expected in examples.items():
            with self.subTest(expected=expected):
                self.path.write_text(raw)
                self.assertEqual(p.classify(self.path), expected)
                result = subprocess.run(['python3', str(ROOT / 'scripts/classify_archive_failure.py'), str(self.path)], capture_output=True, text=True)
                self.assertEqual(result.stdout, 'Kin Dev archive diagnostic hint: ' + expected + '\n')
                self.assertNotIn('secret', result.stdout + result.stderr)
                self.assertNotIn('/private/', result.stdout + result.stderr)
                self.assertNotIn(str(self.path), result.stdout + result.stderr)

    def test_missing_symlink_oversized_fail_closed(self):
        self.assertEqual(p.classify(self.path), 'unavailable')
        self.path.write_bytes(b'x' * (p.MAX_BYTES + 1))
        self.assertEqual(p.classify(self.path), 'unavailable')
        self.path.unlink()
        self.path.symlink_to('/dev/null')
        self.assertEqual(p.classify(self.path), 'unavailable')
        self.path.unlink()
        os.mkfifo(self.path)
        self.assertEqual(p.classify(self.path), 'unavailable')

    def test_signer_retains_original_exit_and_archive_only(self):
        script = (ROOT / 'scripts/kin-sign-dev-review.sh').read_text()
        self.assertIn('if [[ "$stage" == archive ]]; then', script)
        self.assertIn('classify_archive_failure.py "$work/archive.log" >&3 2>/dev/null || true', script)
        self.assertIn('exit "$status"', script)

if __name__ == '__main__': unittest.main()
