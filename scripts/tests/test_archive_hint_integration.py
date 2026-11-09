"""Run the actual Dev trap and cleanup with disposable fake tools only."""
from pathlib import Path
import subprocess
import unittest
import test_hosted_sign_failures as baseline

HERE = Path(__file__).resolve().parents[1]

class ArchiveHintIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.fx = baseline.SignFailureTests('runTest')
        self.fx.setUp(); self.addCleanup(self.fx.doCleanups)
        self.root = self.fx.root
        (self.root / 'export-test.sh').write_bytes((HERE / 'kin-sign-dev-review.sh').read_bytes())
        (self.root / 'cleanup-test.sh').write_bytes((HERE / 'kin-sign-dev-cleanup.sh').read_bytes())
        self.classifier = self.root / 'scripts/classify_archive_failure.py'
        self.classifier.write_bytes((HERE / 'classify_archive_failure.py').read_bytes())
        tool = self.fx.bin / 'xcodebuild'
        tool.write_text(tool.read_text().replace('then exit 17; fi', 'then printf "No profiles for private-app were found secret-password /private/path\\n" >&2; exit 17; fi'))
        self.env = dict(self.fx.env, KIN_DEV_SIGNING_ONLY='1', FAKE_STAGE='archive')

    def exercise(self, classifier_fails):
        if classifier_fails:
            self.classifier.write_text('raise RuntimeError("secret-password /private/path")\n')
        r = subprocess.run(['bash', str(self.root / 'export-test.sh')], env=self.env, cwd=self.root, capture_output=True, timeout=10)
        self.assertEqual(r.returncode, 17)
        self.assertIn(b'Kin Dev signing failed at stage: archive', r.stderr)
        self.assertNotIn(b'secret-password', r.stdout + r.stderr)
        self.assertNotIn(b'/private/path', r.stdout + r.stderr)
        if classifier_fails:
            self.assertNotIn(b'archive diagnostic hint:', r.stderr)
        else:
            self.assertIn(b'Kin Dev archive diagnostic hint: missing-profile', r.stderr)
        cleanup = subprocess.run(['bash', str(self.root / 'cleanup-test.sh')], env=self.env, cwd=self.root, capture_output=True, timeout=10)
        self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
        self.assertEqual(list(self.fx.runner.iterdir()), [])

    def test_hint_and_owned_cleanup(self): self.exercise(False)
    def test_classifier_crash_preserves_failure_and_cleanup(self): self.exercise(True)

if __name__ == '__main__': unittest.main()
