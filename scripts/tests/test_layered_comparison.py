from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LayeredComparisonTests(unittest.TestCase):
    def test_current_gate_remains_full_and_smoke_is_separate(self):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        gate = workflow.split('  validate:', 1)[1]
        self.assertIn('needs: [core-validation, simulator-tests, release-validation]', gate)
        self.assertIn('test "${{ needs.simulator-tests.result }}" = success', gate)
        self.assertNotIn('candidate-smoke', gate)
        smoke = workflow.split('  candidate-smoke:', 1)[1].split('  # Keep the existing required check', 1)[0]
        self.assertIn('python3 scripts/ci-observe.py smoke', smoke)
        self.assertIn('python3 scripts/ci-test-shards.py smoke', smoke)
        self.assertIn('python3 scripts/check-test-results.py', smoke)
        self.assertIn('python3 scripts/ci-simulator.py cleanup', smoke)
        self.assertIn('Require retained simulator cleanup record', smoke)
        self.assertNotIn('simctl privacy', smoke)
        self.assertNotIn('ci-simulator.py grant', smoke)
        self.assertNotIn('simctl addmedia', smoke)


if __name__ == '__main__':
    unittest.main()
