import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('ci_resource', ROOT / 'scripts/ci-resource.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ResourceTests(unittest.TestCase):
    def test_failure_retains_only_fixed_fields_and_bounded_samples(self):
        raw = 'page size of 4096 bytes\nPages free: 3.\nPages inactive: 5.\nPRIVATE_PAYLOAD\n'
        with tempfile.TemporaryDirectory() as d, patch.object(module.os, 'getloadavg', return_value=(1.25, 0, 0)), patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, raw)):
            sampler = module.ResourceSampler(d, interval=0.001, limit=2)
            sampler.start()
            sampler.stopped.wait(0.03)
            sampler.finish(True)
            data = json.loads(sampler.path.read_text())
            self.assertTrue(data['complete'])
            self.assertLessEqual(len(data['samples']), 2)
            self.assertTrue(data['samples'])
            self.assertEqual(data['samples'][0]['free_bytes'], 12288)
            self.assertEqual(data['samples'][0]['inactive_bytes'], 20480)
            self.assertNotIn('PRIVATE_PAYLOAD', sampler.path.read_text())
            self.assertFalse(sampler.thread.is_alive())

    def test_success_removes_stale_evidence_and_failure_is_null_on_errors(self):
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / 'KinTests-resource.json'
            path.write_text('stale')
            with patch.object(module.os, 'getloadavg', side_effect=OSError()), patch.object(module.subprocess, 'run', side_effect=subprocess.TimeoutExpired('vm_stat', 2)):
                sampler = module.ResourceSampler(d, interval=10)
                sampler.start()
                sampler.finish(True)
                sample = json.loads(path.read_text())['samples'][0]
                self.assertIsNone(sample['load_1m'])
                self.assertIsNone(sample['free_bytes'])
                self.assertIsNone(sample['inactive_bytes'])
                sampler = module.ResourceSampler(d, interval=10)
                sampler.start()
                sampler.finish(False)
                self.assertFalse(path.exists())
                self.assertFalse(sampler.thread.is_alive())

if __name__ == '__main__': unittest.main()
