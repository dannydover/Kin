"""Exercise the CI result gate with synthetic finalized and missing results."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def selected_ui():
    spec = importlib.util.spec_from_file_location('ci_shards', ROOT / 'scripts/ci-test-shards.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.selections('ui-1')


class FinalizationGateTests(unittest.TestCase):
    def run_block(self, *, passed=True, missing='', bad_identity=False, shard='ui-1'):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        block = workflow.split('      - name: Require finalized results with full fixture coverage\n', 1)[1]
        block = block.split('      - name: Package synthetic progress and finalized result\n', 1)[0]
        script = '\n'.join(line[10:] for line in block.split('        run: |\n', 1)[1].splitlines())
        script = script.replace('${{ matrix.shard }}', shard)
        ids = selected_ui() if shard != 'unit' else []
        total = len(ids) if ids else 1
        summary = {'result': 'Passed' if passed else 'Failed', 'totalTestCount': total,
                   'passedTests': total if passed else total - 1, 'failedTests': 0 if passed else 1,
                   'skippedTests': 0, 'expectedFailures': 0}
        nodes = [{'nodeType': 'Test Case', 'nodeIdentifier': ident.removeprefix('KinUITests/') + '()'}
                 for ident in ids]
        if bad_identity:
            nodes = nodes[:-1]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'summary.json').write_text(json.dumps(summary))
            (root / 'tree.json').write_text(json.dumps({'testNodes': nodes}))
            if missing != 'bundle':
                (root / 'KinTests.xcresult').mkdir()
            xcrun = root / 'xcrun'
            xcrun.write_text('#!/bin/sh\necho invoked >> "$TASK_SOURCE/xcrun-called"\ncase "$*" in\n'
                             '  *"test-results summary"*) [ "$TASK_MISSING" != summary ] || exit 2; cat "$TASK_SOURCE/summary.json";;\n'
                             '  *"test-results tests"*) [ "$TASK_MISSING" != tree ] || exit 2; cat "$TASK_SOURCE/tree.json";;\n'
                             '  *) exit 2;;\nesac\n')
            xcrun.chmod(0o755)
            env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}', RUNNER_TEMP=str(root),
                       TASK_SOURCE=str(root), TASK_MISSING=missing)
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c', script], cwd=ROOT,
                                    env=env, text=True, capture_output=True)
            result.xcrun_called = (root / 'xcrun-called').exists()
            return result

    def test_failed_result_remains_failed_and_identities_are_checked(self):
        result = self.run_block(passed=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('expected UI identities verified', result.stdout)
        self.assertNotEqual(self.run_block(passed=False, bad_identity=True).returncode, 0)

    def test_success_and_missing_inputs_fail_closed(self):
        self.assertEqual(self.run_block().returncode, 0)
        self.assertEqual(self.run_block(shard='unit').returncode, 0)
        self.assertNotEqual(self.run_block(bad_identity=True).returncode, 0)
        self.assertNotEqual(self.run_block(missing='tree').returncode, 0)
        self.assertNotEqual(self.run_block(missing='summary').returncode, 0)
        missing = self.run_block(missing='bundle')
        self.assertNotEqual(missing.returncode, 0)
        self.assertFalse(missing.xcrun_called)


if __name__ == '__main__':
    unittest.main()
