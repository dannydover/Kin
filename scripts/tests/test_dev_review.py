import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('dev', ROOT / 'scripts/check_dev_entitlements.py')
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)
guard_spec = importlib.util.spec_from_file_location('guard', ROOT / 'scripts/check-repository.py')
guard = importlib.util.module_from_spec(guard_spec)
guard_spec.loader.exec_module(guard)


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

    def test_dev_privacy_exception_is_exact_and_path_scoped(self):
        target = 'scripts/kin-sign-dev-review.sh'
        team = b'DEVELOPMENT_' + b'TEAM'
        profile = b'PROVISIONING_' + b'PROFILE_SPECIFIER'
        valid = b' "' + team + b'=$TEAM_ID" "' + profile + b'=$PROFILE_UUID"\n'
        self.assertEqual(guard.inspect(target, valid), [])
        self.assertIn('signing team', guard.inspect('scripts/other.sh', valid))
        cases = [(b' "' + team + b'=ABCDEFGHIJ"\n', 'signing team'),
                 (b' "' + team + b'=$TEAM_ID' + b'A"\n', 'signing team'),
                 (b' "' + team + b'=$TEAM_ID";echo\n', 'signing team'),
                 (b' "' + profile + b'=$PROFILE_UUID' + b'A"\n', 'provisioning profile'),
                 (b'TEAM_ID="ABCDEFGHIJ"\n', 'signing input assignment'),
                 (b'-----BEGIN ' + b'PRIVATE KEY-----', 'private key')]
        for data, expected in cases:
            with self.subTest(expected=expected):
                self.assertIn(expected, guard.inspect(target, data))

    def test_signing_only_trial_mode_and_cleanup_budget(self):
        w = (ROOT / '.github/workflows/hosted-dev-testflight.yml').read_text()
        self.assertIn('options: [signing_only, upload_trial]', w)
        self.assertIn("if: ${{ false && inputs.mode == 'upload_trial' }}", w)
        self.assertIn('test "$TRIAL_MODE" = signing_only', w)
        self.assertIn('timeout-minutes: 85', w)
        self.assertLess(5 + 40 + 20 + 5 + 5, 85)
        self.assertIn("if: ${{ inputs.mode == 'signing_only' }}", w)
        self.assertIn('environment: kin-dev-signing', w)
        self.assertIn('needs: [source, tests]', w)

    def test_fixed_target_and_disabled_guards(self):
        s = (ROOT / 'scripts/kin-sign-dev-review.sh').read_text()
        c = (ROOT / 'scripts/kin-sign-cleanup.sh').read_text()
        w = (ROOT / '.github/workflows/hosted-dev-testflight.yml').read_text()
        self.assertIn('exit 1', s.split('set -euo pipefail')[0])
        self.assertIn('exit 1', c.split('set -euo pipefail')[0])
        self.assertIn("if: ${{ inputs.mode == 'signing_only' }}", w)
        self.assertIn('environment: kin-dev-signing', w)
        self.assertIn("if: ${{ false && inputs.mode == 'upload_trial' }}", w)
        cleanup = ROOT / 'scripts/kin-sign-dev-cleanup.sh'
        self.assertEqual(cleanup.read_text().split('set +x', 1)[1],
                         c.split('set +x', 1)[1])
        for path in (ROOT / 'scripts/kin-sign-dev-review.sh', cleanup):
            result = subprocess.run(['bash', str(path)], env={'PATH':'/usr/bin:/bin'},
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            self.assertNotEqual(result.returncode, 0)
        self.assertIn("-scheme 'Kin Dev' -configuration Dev", s)
        self.assertIn('identifier \\\"com.intriguingideas.Kin.dev\\\"', s)
        self.assertIn('check_dev_entitlements.py', s)
        self.assertIn('check_dev_entitlements.py', s)
        self.assertNotIn('kin_upload_review.py', s)
        self.assertLess(w.index('kin-sign-dev-review.sh'), w.index('kin-upload-dev-review.sh'))
        upload = (ROOT / 'scripts/kin-upload-dev-review.sh').read_text()
        self.assertIn('exit 1', upload.split('set -euo pipefail')[0])
        self.assertIn('ipa-sha256', upload)
        self.assertEqual(subprocess.run(['bash', '-n', str(ROOT / 'scripts/kin-sign-dev-review.sh')]).returncode, 0)


if __name__ == '__main__': unittest.main()
