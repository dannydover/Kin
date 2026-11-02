import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

FILE = pathlib.Path(__file__).resolve().parents[1] / 'ci-lifecycle.py'
SPEC = importlib.util.spec_from_file_location('lifecycle', FILE)
LIFECYCLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LIFECYCLE)
DEVICE = '-'.join(('0' * 8, '0' * 4, '0' * 4, '0' * 4, '0' * 11 + '1'))


class LifecycleTests(unittest.TestCase):
    def test_exact_single_service_and_pid_state_only(self):
        label = 'UIKitApplication:com.intriguingideas.Kin[private][rb-legacy]'
        self.assertEqual(LIFECYCLE.state(f'42 0 {label}\n'), 'present')
        self.assertEqual(LIFECYCLE.state(f'- 0 {label}\n'), 'absent')
        self.assertEqual(LIFECYCLE.state(f'0 0 {label}\n'), 'unknown')
        self.assertEqual(LIFECYCLE.state(f'42 0 {label}\n43 0 {label}\n'), 'unknown')
        self.assertEqual(LIFECYCLE.state('42 0 UIKitApplication:com.intriguingideas.Kin.other[x]\n'), 'unknown')
        self.assertEqual(LIFECYCLE.state('PRIVATE unrelated inventory\n'), 'unknown')

    def test_timeout_unavailable_and_bad_input_are_unknown(self):
        with tempfile.TemporaryDirectory() as root:
            sampler = LIFECYCLE.LifecycleSampler(root, DEVICE)
            for exception in (subprocess.TimeoutExpired('PRIVATE', 3),
                              subprocess.CalledProcessError(1, 'PRIVATE', stderr='PRIVATE'), OSError('PRIVATE')):
                with self.subTest(exception=type(exception).__name__), patch.object(sampler, '_inventory', side_effect=exception):
                    self.assertEqual(sampler._sample()['state'], 'unknown')
            with self.assertRaises(ValueError):
                LIFECYCLE.LifecycleSampler(root, 'not-a-device')

    def test_timeout_stops_only_the_observer_process_group(self):
        with tempfile.TemporaryDirectory() as root:
            sampler = LIFECYCLE.LifecycleSampler(root, DEVICE)
            child = Mock(pid=12345)
            child.wait.side_effect = [subprocess.TimeoutExpired('observer', 3), 0]
            child.poll.side_effect = [None, -9]
            with patch.object(LIFECYCLE.subprocess, 'Popen', return_value=child) as popen, patch.object(LIFECYCLE.os, 'killpg') as kill:
                self.assertIsNone(sampler._inventory())
            self.assertTrue(popen.call_args.kwargs['start_new_session'])
            self.assertEqual(child.wait.call_args_list[0].kwargs['timeout'], 3)
            kill.assert_called_once_with(12345, LIFECYCLE.signal.SIGKILL)
            self.assertIsNone(sampler.child)
            self.assertTrue(sampler.cleanup_ok)

    def test_failure_retains_only_fixed_fields_bounded_samples_and_stops(self):
        with tempfile.TemporaryDirectory() as root:
            sampler = LIFECYCLE.LifecycleSampler(root, DEVICE, interval=0.01, limit=2)
            result = '42 0 application<com.intriguingideas.Kin>\nPRIVATE'
            with patch.object(sampler, '_inventory', return_value=result):
                sampler.start()
                sampler.thread.join(timeout=0.04)
                sampler.finish(True)
            data = json.loads(sampler.path.read_text())
            self.assertTrue(data['complete'])
            self.assertFalse(sampler.thread.is_alive())
            self.assertLessEqual(len(data['samples']), 2)
            self.assertTrue(all(set(sample) == {'elapsed', 'state'} for sample in data['samples']))
            self.assertNotIn('PRIVATE', sampler.path.read_text())
            self.assertNotIn('42', sampler.path.read_text())
            self.assertNotIn(DEVICE, sampler.path.read_text())

    def test_success_does_not_retain_samples(self):
        with tempfile.TemporaryDirectory() as root:
            sampler = LIFECYCLE.LifecycleSampler(root, DEVICE)
            sampler.path.write_text('stale')
            with patch.object(sampler, '_inventory', side_effect=OSError('PRIVATE')):
                sampler.start()
                sampler.finish(False)
            self.assertFalse(sampler.thread.is_alive())
            self.assertFalse(sampler.path.exists())

    def test_checkpoint_survives_interruption_and_success_removes_it(self):
        with tempfile.TemporaryDirectory() as root:
            sampler = LIFECYCLE.LifecycleSampler(root, DEVICE, interval=0.01, max_seconds=1)
            with patch.object(sampler, '_inventory', return_value='42 0 application<com.intriguingideas.Kin>\nPRIVATE'):
                sampler.start()
                for _ in range(100):
                    if sampler.path.exists():
                        break
                    LIFECYCLE.time.sleep(0.01)
                partial = json.loads(sampler.path.read_text())
                self.assertFalse(partial['complete'])
                self.assertEqual(partial['samples'][0]['state'], 'present')
                self.assertNotIn('PRIVATE', sampler.path.read_text())
                # The existing retention step must preserve this checkpoint
                # even when XCTest never finalized its result bundle.
                retain = FILE.parents[0] / 'ci-retain.py'
                subprocess.run([sys.executable, str(retain)],
                               env=dict(os.environ, RUNNER_TEMP=root), check=True)
                retained = pathlib.Path(root) / 'KinCI-retained'
                self.assertEqual(json.loads((retained / 'manifest.json').read_text())['status'], 'partial')
                self.assertFalse(json.loads((retained / sampler.path.name).read_text())['complete'])
                self.assertTrue(sampler.finish(False))
            self.assertFalse(sampler.path.exists())

    def test_killed_observer_leaves_partial_checkpoint_for_retention(self):
        with tempfile.TemporaryDirectory() as root:
            child_code = '''
import importlib.util, pathlib, sys, time
spec=importlib.util.spec_from_file_location("sampler",sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
s=m.LifecycleSampler(sys.argv[2],sys.argv[3],interval=0.01,max_seconds=10)
s._inventory=lambda: "42 0 application<com.intriguingideas.Kin>\\nPRIVATE"
s.start()
while not s.path.exists(): time.sleep(0.01)
print("ready",flush=True)
time.sleep(30)
'''
            child = subprocess.Popen([sys.executable, '-c', child_code, str(FILE), root, DEVICE],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            try:
                # A timeout bounds the synthetic test process; it never touches XCTest.
                import select
                readable, _, _ = select.select([child.stdout], [], [], 5)
                self.assertTrue(readable, 'checkpoint was not written')
                self.assertEqual(child.stdout.readline().strip(), 'ready')
            finally:
                child.kill()
                child.wait(timeout=3)
                child.stdout.close()
            checkpoint = pathlib.Path(root) / 'KinTests-lifecycle.json'
            self.assertFalse(json.loads(checkpoint.read_text())['complete'])
            subprocess.run([sys.executable, str(FILE.parent / 'ci-retain.py')],
                           env=dict(os.environ, RUNNER_TEMP=root), check=True)
            retained = pathlib.Path(root) / 'KinCI-retained'
            self.assertEqual(json.loads((retained / 'manifest.json').read_text())['status'], 'partial')
            self.assertNotIn('PRIVATE', (retained / checkpoint.name).read_text())

    def test_overall_deadline_and_invalid_bounds(self):
        with tempfile.TemporaryDirectory() as root:
            sampler = LIFECYCLE.LifecycleSampler(root, DEVICE, interval=0.01, max_seconds=0.03)
            with patch.object(sampler, '_inventory', return_value=None):
                sampler.start()
                sampler.thread.join(timeout=1)
                self.assertTrue(sampler.finish(True))
            self.assertTrue(json.loads(sampler.path.read_text())['deadline_reached'])
            for bounds in ({'interval': 0}, {'limit': 201}, {'max_seconds': 2701}):
                with self.subTest(bounds=bounds), self.assertRaises(ValueError):
                    LIFECYCLE.LifecycleSampler(root, DEVICE, **bounds)

    def test_observer_command_failure_preserves_xcode_failure_status(self):
        with tempfile.TemporaryDirectory() as root:
            root_path = pathlib.Path(root)
            fake_xcode = root_path / 'xcodebuild'
            fake_xcode.write_text('#!/bin/sh\nsleep 0.2\nexit 65\n')
            fake_xcode.chmod(0o755)
            fake_xcrun = root_path / 'xcrun'
            fake_xcrun.write_text('#!/bin/sh\necho PRIVATE >&2\nexit 1\n')
            fake_xcrun.chmod(0o755)
            env = dict(os.environ, PATH=root + ':' + os.environ['PATH'],
                       RUNNER_TEMP=root, KIN_CI_SIMULATOR=DEVICE)
            outcome = subprocess.run([sys.executable, str(FILE.parent / 'ci-observe.py'), 'ui-0'],
                                     cwd=FILE.parent.parent, env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(outcome.returncode, 65)
            checkpoint = root_path / 'KinTests-lifecycle.json'
            evidence = json.loads(checkpoint.read_text())
            self.assertTrue(evidence['complete'])
            self.assertTrue(all(s['state'] == 'unknown' for s in evidence['samples']))
            self.assertNotIn('PRIVATE', outcome.stdout + outcome.stderr + checkpoint.read_text())


if __name__ == '__main__':
    unittest.main()
