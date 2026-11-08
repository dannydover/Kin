"""Exercise disposable copies with fake tools; never sign or contact GitHub."""
import base64
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid

HERE = Path(__file__).resolve().parents[1]


class SignFailureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.home = self.root / 'home'; self.home.mkdir()
        self.runner = self.root / 'runner'; self.runner.mkdir()
        self.bin = self.root / 'bin'; self.bin.mkdir()
        tools = {
            'git': 'case "$1" in rev-parse) printf "%s\\n" "$GITHUB_SHA";; status) :;; ls-remote) printf "call\\n" >> "$FAKE_GIT_LOG"; if [[ "${FAKE_DRIFT:-}" == yes && $(/usr/bin/wc -l < "$FAKE_GIT_LOG") -gt 1 ]]; then printf "%040d\\trefs/heads/main\\n" 0; else printf "%s\\trefs/heads/main\\n" "$GITHUB_SHA"; fi;; *) exit 4;; esac',
            'uname': 'printf "arm64\\n"',
            'security': 'printf "%s\\n" "$1" >> "$FAKE_SECURITY_LOG"; case "$1" in list-keychains) if [[ "$*" != *" -s "* ]]; then printf "\\\"/synthetic/original.keychain\\\"\\n"; fi;; create-keychain) for last in "$@"; do :; done; : > "$last";; delete-keychain) /bin/rm -f -- "$2";; esac',
            'xcodebuild': 'printf "%s\\n" "$1" >> "$FAKE_XCODE_LOG"; case "$1" in -version) printf "Xcode 27.0\\nBuild version 27A266a\\n";; -project) if [[ "$FAKE_STAGE" == archive ]]; then exit 17; fi;; -exportArchive) if [[ "$FAKE_STAGE" == export ]]; then exit 19; fi; while [[ $# -gt 0 ]]; do if [[ "$1" == -exportPath ]]; then shift; out="$1"; break; fi; shift; done; /usr/bin/python3 "$FAKE_BUILD" "$out";; *) exit 5;; esac',
            'ditto': '/usr/bin/python3 -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$3" "$4"',
            'codesign': 'case "$*" in *--extract-certificates*) printf fake-cert > codesign0;; *--entitlements*) /usr/bin/python3 "$FAKE_ENTITLEMENTS";; *--verify*) :;; *) exit 6;; esac',
        }
        for name, body in tools.items():
            path = self.bin / name; path.write_text('#!/bin/bash\n' + body + '\n'); path.chmod(0o755)
        (self.root / 'fake-build.py').write_text('import os,pathlib,plistlib,sys,zipfile\n'
            'p=pathlib.Path(sys.argv[1]); p.mkdir(); profile=pathlib.Path(os.environ["HOME"])/"Library/MobileDevice/Provisioning Profiles"/(os.environ["PROFILE_UUID"]+".mobileprovision")\n'
            'info={"CFBundleIdentifier":"com.intriguingideas.Kin","CFBundleShortVersionString":os.environ["VERSION"],"CFBundleVersion":os.environ["BUILD"]}\n'
            'with zipfile.ZipFile(p/"Kin.ipa","w") as z:\n'
            ' z.writestr("Payload/Kin.app/Info.plist",plistlib.dumps(info)); z.writestr("Payload/Kin.app/Kin",b"fake"); z.writestr("Payload/Kin.app/embedded.mobileprovision",profile.read_bytes())\n')
        (self.root / 'fake-entitlements.py').write_text('import os,plistlib,sys\nsys.stdout.buffer.write(plistlib.dumps({"get-task-allow":os.environ.get("FAKE_DEBUG")=="yes","com.apple.developer.team-identifier":os.environ["TEAM_ID"]}))\n')
        scripts = self.root / 'scripts'; scripts.mkdir()
        (scripts / 'check_ipa_layout.py').write_bytes((HERE / 'check_ipa_layout.py').read_bytes())
        # Only disposable test copies lose the unconditional guards.
        for source, target in [('kin-sign-export.sh', 'export-test.sh'),
                               ('kin-sign-cleanup.sh', 'cleanup-test.sh')]:
            text = (HERE / source).read_text(); self.assertIn('exit 1\n\n', text)
            (self.root / target).write_text('#!/bin/bash\n' + text.split('exit 1\n\n', 1)[1])
        self.profile_uuid = str(uuid.UUID(int=1)).upper()
        self.env = {'PATH': str(self.bin) + ':/usr/bin:/bin', 'HOME': str(self.home),
                    'RUNNER_TEMP': str(self.runner), 'GITHUB_RUN_ID': '7', 'GITHUB_RUN_ATTEMPT': '1',
                    'GITHUB_REF': 'refs/heads/main', 'GITHUB_SHA': 'a' * 40,
                    'TEAM_ID': 'A' * 10, 'PROFILE_UUID': self.profile_uuid,
                    'VERSION': '1.3.0', 'BUILD': '7', 'CERT_SHA256': hashlib.sha256(b'fake-cert').hexdigest(),
                    'P12_BASE64': base64.b64encode(b'synthetic-p12').decode(),
                    'P12_PASSWORD': 'synthetic-password',
                    'PROFILE_BASE64': base64.b64encode(b'synthetic-profile').decode(),
                    'FAKE_SECURITY_LOG': str(self.root / 'security-calls'),
                    'FAKE_XCODE_LOG': str(self.root / 'xcode-calls'),
                    'FAKE_GIT_LOG': str(self.root / 'git-calls'), 'FAKE_BUILD': str(self.root / 'fake-build.py'),
                    'FAKE_ENTITLEMENTS': str(self.root / 'fake-entitlements.py')}

    def test_archive_and_export_failure_preserve_failure_and_cleanup(self):
        for stage, code in [('archive', 17), ('export', 19)]:
            with self.subTest(stage=stage):
                env = dict(self.env, FAKE_STAGE=stage)
                result = subprocess.run(['bash', str(self.root / 'export-test.sh')], env=env, cwd=self.root,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertNotIn(b'synthetic-password', result.stdout + result.stderr)
                cleanup = subprocess.run(['bash', str(self.root / 'cleanup-test.sh')], env=env, cwd=self.root,
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
                self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
                self.assertEqual(list(self.runner.iterdir()), [])
                profile = self.home / 'Library/MobileDevice/Provisioning Profiles' / (self.profile_uuid + '.mobileprovision')
                self.assertFalse(profile.exists())
                self.assertIn('delete-keychain', (self.root / 'security-calls').read_text().splitlines())
                calls = (self.root / 'xcode-calls').read_text().splitlines()
                self.assertEqual(calls[-1], '-project' if stage == 'archive' else '-exportArchive')

    def test_missing_input_stops_before_staging(self):
        env = dict(self.env, FAKE_STAGE='archive', PROFILE_BASE64='')
        result = subprocess.run(['bash', str(self.root / 'export-test.sh')], env=env, cwd=self.root,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.runner.iterdir()), [])
        self.assertFalse((self.root / 'security-calls').exists())

    def test_postbuild_main_drift_fails_and_cleanup_still_runs(self):
        env = dict(self.env, FAKE_STAGE='success', FAKE_DRIFT='yes')
        result = subprocess.run(['bash', str(self.root / 'export-test.sh')], env=env, cwd=self.root,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(b'Local candidate inspected', result.stdout)
        self.assertEqual((self.root / 'git-calls').read_text().splitlines(), ['call', 'call'], result.stderr)
        cleanup = subprocess.run(['bash', str(self.root / 'cleanup-test.sh')], env=env, cwd=self.root,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
        self.assertEqual(list(self.runner.iterdir()), [])

    def test_synthetic_output_check_and_debug_entitlement_failure(self):
        for debug in ('no', 'yes'):
            with self.subTest(debug=debug):
                (self.root / 'git-calls').unlink(missing_ok=True)
                env = dict(self.env, FAKE_STAGE='success', FAKE_DEBUG=debug)
                result = subprocess.run(['bash', str(self.root / 'export-test.sh')], env=env, cwd=self.root,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
                if debug == 'no':
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(b'Local candidate inspected', result.stdout)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn(b'Local candidate inspected', result.stdout)
                cleanup = subprocess.run(['bash', str(self.root / 'cleanup-test.sh')], env=env, cwd=self.root,
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
                self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
                self.assertEqual(list(self.runner.iterdir()), [])


if __name__ == '__main__': unittest.main()
