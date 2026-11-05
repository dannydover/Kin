import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LayeredComparisonTests(unittest.TestCase):
    def test_no_other_workflow_starts_on_pull_requests(self):
        workflows = ROOT / '.github/workflows'
        for path in workflows.glob('*.y*ml'):
            if path.name != 'ci.yml':
                output = subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e', 'puts JSON.generate(YAML.load_file(ARGV[0]))', str(path)])
                document = json.loads(output)
                triggers = document.get('on', document.get('true', {}))
                if isinstance(triggers, str): triggers = [triggers]
                self.assertNotIn('pull_request', triggers, path.name)
                self.assertNotIn('pull_request_target', triggers, path.name)

    def test_manual_hash_gate_fails_closed(self):
        workflow = (ROOT / '.github/workflows/manual-broad-ui.yml').read_text()
        block = workflow.split('      - name: Verify packaged result hash\n', 1)[1]
        block = block.split('      - name: Retain synthetic progress and finalized result\n', 1)[0]
        script = '\n'.join(line[10:] for line in block.split('        run: |\n', 1)[1].splitlines())
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'KinCI-retained'; root.mkdir()
            result = root / 'KinTests-xcresult.zip'; result.write_bytes(b'synthetic result')
            manifest = root / 'manifest.json'
            def run():
                return subprocess.run(['bash', '-e', '-c', script], env=dict(os.environ, RUNNER_TEMP=temp), capture_output=True)
            manifest.write_text(json.dumps({'status':'finalized', 'result_sha256':hashlib.sha256(result.read_bytes()).hexdigest()}))
            self.assertEqual(run().returncode, 0)
            result.write_bytes(b'changed')
            self.assertNotEqual(run().returncode, 0)
            manifest.write_text(json.dumps({'status':'partial', 'result_sha256':hashlib.sha256(result.read_bytes()).hexdigest()}))
            self.assertNotEqual(run().returncode, 0)
            result.unlink()
            self.assertNotEqual(run().returncode, 0)

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
        self.assertIn("github.ref == 'refs/heads/diagnostic/kin13-trial-random' && 'random' || 'standard'", ios)
        self.assertIn('python3 scripts/check-test-results.py', ios)
        self.assertIn('Require retained simulator cleanup record', ios)
        self.assertNotIn('  simulator-tests:', workflow)
        broad = (ROOT / '.github/workflows/manual-broad-ui.yml').read_text()
        self.assertIn('  workflow_dispatch:', broad)
        self.assertNotIn('  pull_request:', broad)
        self.assertNotIn('  push:', broad)
        self.assertIn('shard: [ui-0, ui-1, ui-2, ui-3]', broad)
        self.assertIn('[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]', broad)
        self.assertIn('ref: ${{ inputs.source_sha }}', broad)
        self.assertIn('test "$(git rev-parse HEAD)" = "$SOURCE_SHA"', broad)
        self.assertIn('source-commit.txt', broad)
        self.assertIn('test-order.txt', broad)
        self.assertIn('Verify packaged result hash', broad)
        self.assertIn("hashlib.sha256(result.read_bytes()).hexdigest() != manifest.get('result_sha256')", broad)
        self.assertIn('python3 scripts/check-test-results.py', broad)
        self.assertIn('python3 scripts/ci-test-shards.py', broad)
        self.assertIn('python3 scripts/ci-simulator.py cleanup', broad)
        self.assertIn('Require retained simulator cleanup record', broad)
        self.assertIn('test "${{ needs.simulator-tests.result }}" = success', broad)
        smoke = workflow.split('  candidate-smoke:', 1)[1].split('  # Keep the existing required check', 1)[0]
        self.assertIn("github.ref == 'refs/heads/diagnostic/kin13-trial-random' && 'random' || 'standard'", smoke)
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
