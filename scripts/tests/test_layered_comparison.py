from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LayeredComparisonTests(unittest.TestCase):
    def test_required_gate_includes_complete_ios_and_smoke(self):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        gate = workflow.split('  validate:', 1)[1]
        self.assertIn('needs: [core-validation, ios-tests, candidate-smoke, release-validation]', gate)
        for job in ('core-validation', 'ios-tests', 'candidate-smoke', 'release-validation'):
            self.assertIn('test "${{ needs.' + job + '.result }}" = success', gate)
        self.assertNotIn('needs.simulator-tests.result', gate)
        ios = workflow.split('  ios-tests:', 1)[1].split('  release-validation:', 1)[0]
        self.assertIn('python3 scripts/ci-observe.py "unit"', ios)
        self.assertIn('python3 scripts/ci-test-shards.py unit', ios)
        self.assertIn('python3 scripts/check-test-results.py', ios)
        self.assertIn('Require retained simulator cleanup record', ios)
        broad = workflow.split('  simulator-tests:', 1)[1].split('  ios-tests:', 1)[0]
        self.assertIn('shard: [ui-0, ui-1, ui-2, ui-3]', broad)
        self.assertIn('needs: [core-validation, ios-tests, candidate-smoke, release-validation]', broad)
        self.assertIn('if: ${{ !cancelled() }}', broad)
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
