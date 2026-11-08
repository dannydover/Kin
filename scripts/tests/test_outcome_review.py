import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('outcome', ROOT / 'scripts/summarize_upload_review.py')
outcome = importlib.util.module_from_spec(spec)
spec.loader.exec_module(outcome)


class OutcomeTests(unittest.TestCase):
    def test_known_and_missing_markers_are_fixed_categories(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); evidence = root / 'kin-upload-evidence-7-1'; evidence.mkdir()
            marker = evidence / 'upload-outcome'
            for raw, expected in [('uncertain\n', 'uncertain'),
                                  ('tool-success-processing-unverified\n', 'tool-success-processing-unverified'),
                                  ('private data should not escape', 'unknown')]:
                marker.write_text(raw)
                result = outcome.summarize(root, '7', '1', 'a' * 40)
                self.assertEqual(result['upload'], expected)
                self.assertNotIn('private data', str(result))
                self.assertFalse(result['automatic_retry'])
                self.assertEqual(result['apple_processing'], 'unverified')
            marker.unlink()
            self.assertEqual(outcome.summarize(root, '7', '1', 'a' * 40)['upload'], 'unknown')

    def test_bad_run_identity_fails(self):
        with self.assertRaises(ValueError): outcome.summarize('/tmp', '../7', '1', 'a' * 40)
        with self.assertRaises(ValueError): outcome.summarize('/tmp', '7', '1', 'wrong')

    def test_processing_outcomes_never_claim_byte_proof(self):
        with tempfile.TemporaryDirectory() as d:
            e=Path(d)/'kin-upload-evidence-7-1';e.mkdir();m=e/'upload-outcome'
            for raw, state in [('processing-valid-metadata-match','valid-metadata-match'),
                               ('apple-processing-failed','failed')]:
                m.write_text(raw); r=outcome.summarize(d,'7','1','a'*40)
                self.assertEqual(r['apple_processing'],state)
                self.assertEqual(r['byte_identity'],'unverified')

    def test_outcome_is_after_cleanup_in_disabled_job(self):
        s = (ROOT / '.github/workflows/hosted-dev-testflight.yml').read_text()
        self.assertIn('if: ${{ false }}', s)
        self.assertNotIn('environment:', s)
        self.assertLess(s.index('kin-sign-export.sh'), s.index('kin-upload-dev-review.sh'))
        self.assertLess(s.index('kin-upload-dev-review.sh'), s.index('kin-sign-cleanup.sh'))
        self.assertLess(s.index('kin-sign-cleanup.sh'), s.index('summarize_upload_review.py'))
        self.assertIn('if-no-files-found: error', s)


if __name__ == '__main__': unittest.main()
