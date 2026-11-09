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

    def test_failure_stages_are_fixed_and_raw_tool_output_stays_private(self):
        tool = self.bin / 'xcodebuild'
        tool.write_text(tool.read_text().replace('if [[ "$FAKE_STAGE"',
            'printf "%s\\n" "private /fake/path synthetic-password"; printf "%s\\n" "private /fake/path synthetic-password" >&2; if [[ "$FAKE_STAGE"'))
        for stage, code in [('archive', 17), ('export', 19)]:
            with self.subTest(stage=stage):
                env = dict(self.env, FAKE_STAGE=stage)
                result = subprocess.run(['bash', str(self.root / 'export-test.sh')], env=env,
                    cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
                self.assertEqual(result.returncode, code)
                self.assertEqual(result.stderr, ('Kin Dev signing failed at stage: ' + stage + '\n').encode())
                self.assertNotIn(b'synthetic-password', result.stdout + result.stderr)
                cleanup = subprocess.run(['bash', str(self.root / 'cleanup-test.sh')], env=env,
                    cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
                self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
                self.assertEqual(list(self.runner.iterdir()), [])

    def test_input_failure_reports_only_input_stage(self):
        result = subprocess.run(['bash', str(self.root / 'export-test.sh')],
            env=dict(self.env, PROFILE_BASE64=''), cwd=self.root,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr, b'Kin Dev signing failed at stage: input_validation\n')
        self.assertFalse((self.root / 'security-calls').exists())

    def test_keychain_failure_is_redacted_and_cleanup_runs(self):
        tool = self.bin / 'security'
        tool.write_text(tool.read_text().replace('create-keychain) for last',
            'create-keychain) printf "private /fake/path synthetic-password\\n" >&2; exit 42; for last'))
        env = dict(self.env, FAKE_STAGE='success')
        result = subprocess.run(['bash', str(self.root / 'export-test.sh')], env=env,
            cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        self.assertEqual(result.returncode, 42)
        self.assertEqual(result.stderr, b'Kin Dev signing failed at stage: keychain_setup\n')
        cleanup = subprocess.run(['bash', str(self.root / 'cleanup-test.sh')], env=env,
            cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
        self.assertEqual(list(self.runner.iterdir()), [])

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
