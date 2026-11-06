import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('observer', ROOT / 'scripts/ci-observe.py')
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)


class DuplicateStartTests(unittest.TestCase):
    def run_observer(self, duplicate, exit_code=0):
        group = 'ui-3'
        ids = observer.shards.selections(group)
        ident = ids[0]
        _, klass, method = ident.split('/')
        scopes = sorted(observer.CLEANUP_SCOPES[i] for i in ids if i in observer.CLEANUP_SCOPES)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / 'xcodebuild'
            event = f'Test Case \'-[KinUITests.{klass} {method}]\' started. PRIVATE_PAYLOAD'
            lines = [event] * (2 if duplicate else 1)
            lines += [f'Test Case \'-[KinUITests.{klass} {method}]\' passed. PRIVATE_PAYLOAD',
                      'KIN_CI_AUTH authorized PRIVATE_PAYLOAD']
            lines += [f'KIN_CI_CONTACT_CLEANUP {scope} verified PRIVATE_PAYLOAD' for scope in scopes]
            fake.write_text('#!/bin/sh\n' + ''.join('printf "%s\\n" ' + repr(line) + '\n' for line in lines)
                            + f'exit {exit_code}\n')
            fake.chmod(0o755)
            env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}', RUNNER_TEMP=directory,
                       KIN_CI_SIMULATOR='synthetic')
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/ci-observe.py'), group],
                                    cwd=ROOT, env=env, text=True, capture_output=True)
            progress = (root / 'KinTests-progress.jsonl').read_text()
            return ident, result, [json.loads(line) for line in progress.splitlines()], progress

    def test_duplicate_start_fails_even_when_later_test_and_process_pass(self):
        ident, result, events, progress = self.run_observer(True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('CI_DUPLICATE_TEST_START ' + ident, result.stderr)
        self.assertEqual(sum(e.get('kind') == 'duplicate_test_start' and e.get('id') == ident for e in events), 1)
        self.assertNotIn('PRIVATE_PAYLOAD', result.stdout + result.stderr + progress)

    def test_single_start_can_pass_and_existing_failure_is_preserved(self):
        _, result, events, _ = self.run_observer(False)
        self.assertEqual(result.returncode, 0)
        self.assertFalse(any(e.get('kind') == 'duplicate_test_start' for e in events))
        _, failed, _, _ = self.run_observer(True, exit_code=65)
        self.assertEqual(failed.returncode, 65)


if __name__ == '__main__':
    unittest.main()
