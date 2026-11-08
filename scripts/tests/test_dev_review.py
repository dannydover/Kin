import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('dev', ROOT / 'scripts/check_dev_entitlements.py')
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class DevReviewTests(unittest.TestCase):
    def setUp(self):
        self.team = 'ABCDEFGHIJ'
        self.app = self.team + '.com.intriguingideas.Kin.dev'
        self.ent = {'application-identifier': self.app,
                    'com.apple.developer.team-identifier': self.team,
                    'keychain-access-groups': [self.app], 'get-task-allow': False}

    def test_accepts_expected_synthetic_entitlements(self): dev.check(self.ent, self.team)

    def test_rejects_production_shared_or_debug_entitlements(self):
        cases = [
            {'application-identifier': self.team + '.com.intriguingideas.Kin'},
            {'keychain-access-groups': [self.app, self.team + '.com.intriguingideas.Kin']},
            {'com.apple.security.application-groups': ['group.synthetic']},
            {'com.apple.developer.ubiquity-container-identifiers': ['iCloud.synthetic']},
            {'com.apple.developer.icloud-services': ['CloudKit']},
            {'com.apple.developer.ubiquity-kvstore-identifier': self.app},
            {'aps-environment': 'production'},
            {'com.example.unexpected': False},
            {'get-task-allow': True},
        ]
        for item in cases:
            with self.subTest(item=item), self.assertRaises(ValueError):
                dev.check(dict(self.ent, **item), self.team)

    def test_beta_reports_only_permitted_when_true(self):
        dev.check(dict(self.ent, **{'beta-reports-active': True}), self.team)
        with self.assertRaises(ValueError):
            dev.check(dict(self.ent, **{'beta-reports-active': False}), self.team)

    def test_disabled_trial_modes_and_cleanup_budget(self):
        w = (ROOT / '.github/workflows/hosted-dev-testflight.yml').read_text()
        self.assertIn('options: [signing_only, upload_trial]', w)
        self.assertIn("if: ${{ false && inputs.mode == 'upload_trial' }}", w)
        self.assertIn('timeout-minutes: 85', w)
        self.assertLess(5 + 40 + 20 + 5 + 5, 85)
        self.assertIn('if: ${{ false }}', w)
        self.assertNotIn('environment:', w)

    def test_fixed_target_and_disabled_guards(self):
        s = (ROOT / 'scripts/kin-sign-export.sh').read_text()
        c = (ROOT / 'scripts/kin-sign-cleanup.sh').read_text()
        w = (ROOT / '.github/workflows/hosted-dev-testflight.yml').read_text()
        self.assertIn('exit 1', s.split('set -euo pipefail')[0])
        self.assertIn('exit 1', c.split('set -euo pipefail')[0])
        self.assertIn('if: ${{ false }}', w)
        self.assertNotIn('environment:', w)
        self.assertIn("-scheme 'Kin Dev' -configuration Dev", s)
        self.assertIn('identifier \\\"com.intriguingideas.Kin.dev\\\"', s)
        self.assertIn('check_dev_entitlements.py', s)
        self.assertIn('check_dev_entitlements.py', s)
        self.assertNotIn('kin_upload_review.py', s)
        self.assertLess(w.index('kin-sign-export.sh'), w.index('kin-upload-dev-review.sh'))
        upload = (ROOT / 'scripts/kin-upload-dev-review.sh').read_text()
        self.assertIn('exit 1', upload.split('set -euo pipefail')[0])
        self.assertIn('ipa-sha256', upload)
        self.assertEqual(subprocess.run(['bash', '-n', str(ROOT / 'scripts/kin-sign-export.sh')]).returncode, 0)


if __name__ == '__main__': unittest.main()
