import importlib.util
import os
import pathlib
import subprocess
import unittest
from unittest.mock import patch

FILE = pathlib.Path(__file__).resolve().parents[1] / 'ci-lifecycle-preflight.py'
if not FILE.exists():
    FILE = pathlib.Path(__file__).with_name('kin-lifecycle-preflight.py')
SPEC = importlib.util.spec_from_file_location('preflight', FILE)
PREFLIGHT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREFLIGHT)


class PreflightTests(unittest.TestCase):
    def test_only_exact_bundle_service_is_considered(self):
        output = ('PID Status Label\n41 0 UIKitApplication:com.intriguingideas.Kin[abc][rb-legacy]\n'
                  '42 0 UIKitApplication:com.intriguingideas.Kin.other[abc]\n'
                  '43 0 application<com.intriguingideas.Kin>\n')
        self.assertEqual(PREFLIGHT.candidates(output), [41, 43])
        self.assertEqual(PREFLIGHT.candidates('- 0 application<com.intriguingideas.Kin>\n'), [None])

    def test_verified_requires_launch_pid_and_one_matching_service(self):
        with patch.dict(os.environ, {'KIN_CI_SIMULATOR': 'synthetic'}), patch.object(
            PREFLIGHT, 'run', side_effect=['com.intriguingideas.Kin: 41\n',
                                          '41 0 application<com.intriguingideas.Kin>\n']):
            self.assertEqual(PREFLIGHT.main(), 'verified')

    def test_launch_and_inventory_failures_are_unknown_without_raw_output(self):
        for issue in (subprocess.TimeoutExpired('PRIVATE', 1),
                      subprocess.CalledProcessError(1, 'PRIVATE', stderr='PRIVATE'), OSError('PRIVATE')):
            with self.subTest(issue=type(issue).__name__), patch.dict(os.environ, {'KIN_CI_SIMULATOR': 'synthetic'}), patch.object(PREFLIGHT, 'run', side_effect=issue):
                self.assertEqual(PREFLIGHT.main(), 'unknown')

    def test_ambiguous_or_unmatched_launch_is_not_verified(self):
        with patch.dict(os.environ, {'KIN_CI_SIMULATOR': 'synthetic'}), patch.object(
            PREFLIGHT, 'run', side_effect=['com.intriguingideas.Kin: 41\n',
                '41 0 application<com.intriguingideas.Kin>\n42 0 application<com.intriguingideas.Kin>\n',
                subprocess.TimeoutExpired('PRIVATE', 1)]), patch.object(PREFLIGHT.time, 'sleep'):
            self.assertEqual(PREFLIGHT.main(), 'unknown')
        with patch.dict(os.environ, {'KIN_CI_SIMULATOR': 'synthetic'}), patch.object(PREFLIGHT, 'run', return_value='unexpected PRIVATE'):
            self.assertEqual(PREFLIGHT.main(), 'unknown')


if __name__ == '__main__':
    unittest.main()
