"""Exercise the proposed Dev signing-only flow using disposable fake tools."""
import os
from pathlib import Path
import subprocess
import test_hosted_sign_failures as baseline


class DevSignTrialTests(baseline.SignFailureTests):
    def setUp(self):
        super().setUp()
        scripts = self.root / 'scripts'
        (scripts / 'check_dev_entitlements.py').write_bytes(
            (baseline.HERE / 'check_dev_entitlements.py').read_bytes())
        (self.root / 'export-test.sh').write_bytes(
            (baseline.HERE / 'kin-sign-dev-review.sh').read_bytes())
        (self.root / 'cleanup-test.sh').write_bytes(
            (baseline.HERE / 'kin-sign-dev-cleanup.sh').read_bytes())
        build = self.root / 'fake-build.py'
        build.write_text(build.read_text().replace('com.intriguingideas.Kin',
                                                   'com.intriguingideas.Kin.dev'))
        (self.root / 'fake-entitlements.py').write_text(
            'import os,plistlib,sys\n'
            'team=os.environ["TEAM_ID"]; app=team+".com.intriguingideas.Kin.dev"\n'
            'sys.stdout.buffer.write(plistlib.dumps({"get-task-allow":os.environ.get("FAKE_DEBUG")=="yes",'
            '"application-identifier":app,"keychain-access-groups":[app],'
            '"com.apple.developer.team-identifier":team}))\n')
        self.env['KIN_DEV_SIGNING_ONLY'] = '1'

    def test_synthetic_output_check_and_debug_entitlement_failure(self):
        for debug in ('no', 'yes'):
            with self.subTest(debug=debug):
                env = dict(self.env, FAKE_STAGE='success', FAKE_DEBUG=debug)
                result = subprocess.run(['bash', str(self.root / 'export-test.sh')], env=env,
                                        cwd=self.root, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, timeout=10)
                if debug == 'no':
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(b'Dev candidate verified', result.stdout)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn(b'Dev candidate verified', result.stdout)
                cleanup = subprocess.run(['bash', str(self.root / 'cleanup-test.sh')], env=env,
                                         cwd=self.root, stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE, timeout=10)
                self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
                self.assertEqual(list(self.runner.iterdir()), [])
