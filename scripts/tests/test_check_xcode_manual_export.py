"""Synthetic Xcode help; no archive, signing, credentials or network."""
import importlib.util
from pathlib import Path
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('help_probe', Path(__file__).resolve().parents[1] / 'check-xcode-manual-export.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

HELP = '''Usage: xcodebuild -exportArchive -exportOptionsPlist
Available keys for -exportOptionsPlist:
    destination : String
        Options are export or upload.
    method : String
        Options include app-store-connect.
    provisioningProfiles : Dictionary
        Manual signing profiles.
    signingCertificate : String
        Manual signing certificate.
    signingStyle : String
        Options are manual or automatic.
    teamID : String
        The team identifier.
'''


class HelpProbeTests(unittest.TestCase):
    def test_supported_synthetic_help(self):
        self.assertTrue(probe.check(HELP))

    def test_missing_or_unsupported_options_fail(self):
        for modified in (HELP.replace('app-store-connect', 'debugging'), HELP.replace('manual or automatic', 'automatic'),
                         HELP.replace('export or upload', 'upload'), HELP.replace('teamID : String', 'teamID : Bool'),
                         HELP + '\n    teamID : String\n duplicate', 'not help'):
            with self.subTest(modified=modified), self.assertRaises(ValueError): probe.check(modified)

    def test_main_uses_only_read_only_help(self):
        with mock.patch.object(probe._candidate, '_bounded_output', return_value=HELP.encode()) as run:
            probe.main()
        run.assert_called_once_with(['/usr/bin/xcodebuild', '-help'], 'Xcode help', merge_stderr=True)


if __name__ == '__main__': unittest.main()
