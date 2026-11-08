"""Static boundaries for the disabled release proposal and reusable-CI probe."""
import hashlib
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECKOUT = '11d5960a326750d5838078e36cf38b85af677262'
UPLOAD = 'ea165f8d65b6e75b540449e92b4886f43607fa02'
BASE_CI = '2924126f6af03e12c84ce196271fc04a048653892bc29ba20f9a31028229b986'


class HostedWorkflowTests(unittest.TestCase):
    def test_existing_ci_changes_only_call_trigger_and_verified_pins(self):
        path = ROOT / '.github/workflows/ci.yml'
        text = path.read_text()
        self.assertEqual(text.count('  workflow_call:\n'), 1)
        self.assertEqual(text.count('actions/checkout@' + CHECKOUT + ' # v4'), 5)
        self.assertEqual(text.count('actions/upload-artifact@' + UPLOAD + ' # v4'), 6)
        probe_start = text.index('  # Credential-free PR-only probe;')
        probe_end = text.index('  core-validation:', probe_start)
        probe = text[probe_start:probe_end]
        self.assertIn("if: github.event_name == 'pull_request'", probe)
        self.assertIn('needs: reusable-probe-source', probe)
        self.assertIn('uses: ./.github/workflows/reusable-ci-probe-target.yml', probe)
        without_probe = text[:probe_start] + text[probe_end:]
        base = (without_probe.replace('  workflow_call:\n', '', 1)
                .replace('actions/checkout@' + CHECKOUT + ' # v4', 'actions/checkout@v4')
                .replace('actions/upload-artifact@' + UPLOAD + ' # v4', 'actions/upload-artifact@v4'))
        self.assertEqual(hashlib.sha256(base.encode()).hexdigest(), BASE_CI)

    def test_disabled_signing_and_reusable_needs(self):
        workflow = ROOT / '.github/workflows/hosted-release.yml'
        ruby = "require 'yaml'; h=YAML.safe_load(File.read(ARGV[0])); j=h.fetch('jobs'); abort unless j.fetch('signing').fetch('if') == '${{ false }}' && !j.fetch('signing').key?('environment') && j.fetch('signing').fetch('needs') == ['source','tests'] && j.fetch('tests').fetch('needs') == 'source' && j.fetch('tests').fetch('uses') == './.github/workflows/ci.yml'"
        subprocess.run(['ruby', '-e', ruby, str(workflow)], check=True, timeout=10)
        self.assertNotIn('upload-app', workflow.read_text())
        for name in ('kin-sign-export.sh', 'kin-sign-cleanup.sh'):
            path = ROOT / 'scripts' / name
            subprocess.run(['bash', '-n', str(path)], check=True, timeout=10)
            result = subprocess.run(['bash', str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            self.assertEqual(result.returncode, 1); self.assertIn(b'disabled', result.stderr)

    def test_pr_probe_is_small_readonly_and_uses_caller_sha(self):
        caller = ROOT / '.github/workflows/ci.yml'
        target = ROOT / '.github/workflows/reusable-ci-probe-target.yml'
        ruby = "require 'yaml'; h=YAML.safe_load(File.read(ARGV[0])); j=h.fetch('jobs'); abort unless j.fetch('reusable-probe').fetch('needs') == 'reusable-probe-source' && j.fetch('reusable-probe').fetch('uses') == './.github/workflows/reusable-ci-probe-target.yml' && j.fetch('reusable-probe').fetch('permissions') == {'contents'=>'read'}"
        subprocess.run(['ruby', '-e', ruby, str(caller)], check=True, timeout=10)
        text = target.read_text()
        self.assertIn('  workflow_call:', text)
        self.assertIn('test "$EXPECTED_SHA" = "$GITHUB_SHA"', text)
        self.assertIn('test "$(git rev-parse HEAD)" = "$EXPECTED_SHA"', text)
        self.assertIn('test "$GITHUB_EVENT_NAME" = pull_request', text)
        self.assertNotIn('secrets.', text); self.assertNotIn('environment:', text)


if __name__ == '__main__': unittest.main()
