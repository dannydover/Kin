import importlib.util
import json
import pathlib
import subprocess
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


if __name__ == '__main__':
    unittest.main()
