"""Keep the required GitHub gate small and the source-only release draft independent."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]

class WorkflowBoundaryTests(unittest.TestCase):
    def test_github_ci_keeps_required_core_gate_without_simulators_or_signing(self):
        path = ROOT / '.github/workflows/ci.yml'
        doc = json.loads(subprocess.check_output([
            'ruby', '-ryaml', '-rjson', '-e', 'puts JSON.generate(YAML.load_file(ARGV[0]))', str(path)]))
        jobs = doc['jobs']
        self.assertEqual(set(jobs), {'core-validation', 'validate'})
        self.assertEqual(jobs['validate']['needs'], ['core-validation'])
        self.assertEqual(jobs['validate']['if'], 'always()')
        self.assertIn('needs.core-validation.result', jobs['validate']['steps'][0]['run'])
        workflow = path.read_text()
        for forbidden in ('simctl', 'environment:', 'secrets.', 'ios-tests:', 'release-validation:', 'candidate-smoke:'):
            self.assertNotIn(forbidden, workflow)
        self.assertIn('scripts/test-core.sh', workflow)
        self.assertIn('python3 scripts/check-repository.py', workflow)

    def test_only_source_release_draft_remains_beside_ci(self):
        names = {p.name for p in (ROOT / '.github/workflows').glob('*.yml')}
        self.assertEqual(names, {'ci.yml', 'draft-release.yml'})
        self.assertIn('workflow_dispatch:', (ROOT / '.github/workflows/draft-release.yml').read_text())

if __name__ == '__main__': unittest.main()
