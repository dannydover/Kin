"""Synthetic guard and owned-cleanup cases; no real keychain or profile."""
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid


HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('proposed_guard', HERE / 'check-repository.py')
guard = importlib.util.module_from_spec(spec); spec.loader.exec_module(guard)
TARGET = 'scripts/kin-sign-export.sh'
TEAM = 'DEVELOPMENT_TEAM'
PROFILE = 'PROVISIONING_PROFILE_SPECIFIER'


class GuardTests(unittest.TestCase):
    def test_exact_variable_arguments_only_in_reviewed_file(self):
        arguments = (' "' + TEAM + '=$TEAM_ID" "' + PROFILE + '=$PROFILE_UUID"\n').encode()
        self.assertEqual(guard.inspect(TARGET, arguments), [])
        self.assertIn('signing team', guard.inspect('scripts/other.sh', arguments))
        self.assertIn('provisioning profile', guard.inspect('scripts/other.sh', arguments))
        self.assertEqual(guard.inspect(TARGET, (HERE / 'kin-sign-export.sh').read_bytes()), [])

    def test_literals_mixed_values_and_shell_near_matches_remain_blocked(self):
        team = 'A' * 10
        profile = str(uuid.UUID(int=1))
        cases = [('signing team', TEAM + '=' + team),
                 ('provisioning profile', PROFILE + '=' + profile),
                 ('signing team', '"' + TEAM + '=$TEAM_ID' + team + '"'),
                 ('provisioning profile', '"' + PROFILE + '=$PROFILE_UUID' + profile + '"'),
                 ('signing team', '"' + TEAM + '=$TEAM_ID"' + team),
                 ('signing team', '"' + TEAM + '=$TEAM_ID"\\\n' + team),
                 ('signing team', '"' + TEAM + '=$TEAM_ID";echo'),
                 ('signing team', TEAM + '=$TEAM_ID'),
                 ('provisioning profile', '"' + PROFILE + '=$PROFILE_UUID"$(echo x)'),
                 ('signing team', 'X="' + TEAM + '=$TEAM_ID"'),
                 ('signing team', '"' + TEAM + '=${TEAM_ID}"'),
                 ('provisioning profile', '"' + PROFILE + '=$OTHER"')]
        for expected, text in cases:
            with self.subTest(expected=expected, sample=text):
                self.assertIn(expected, guard.inspect(TARGET, (' ' + text + '\n').encode()))
        mixed = (' "' + TEAM + '=$TEAM_ID"\n' + TEAM + '=' + team + '\n').encode()
        self.assertIn('signing team', guard.inspect(TARGET, mixed))
        mixed = (' "' + PROFILE + '=$PROFILE_UUID"\n' + PROFILE + '=' + profile + '\n').encode()
        self.assertIn('provisioning profile', guard.inspect(TARGET, mixed))

    def test_source_variables_cannot_be_given_literals_or_mixed_values(self):
        for name, literal in [('TEAM_ID', 'A' * 10), ('PROFILE_UUID', str(uuid.UUID(int=1)))]:
            self.assertEqual(guard.inspect(TARGET, (name + '="$' + name + '"\n').encode()), [])
            for value in (literal, '"$' + name + literal + '"', '"$' + name + '"' + literal):
                with self.subTest(name=name, value=value):
                    self.assertIn('signing input assignment', guard.inspect(TARGET, (name + '=' + value + '\n').encode()))

    def test_other_secret_rules_still_scan_unmasked_original(self):
        text = (' "' + TEAM + '=$TEAM_ID"\n').encode() + b'-----BEGIN ' + b'PRIVATE KEY-----'
        self.assertIn('private key', guard.inspect(TARGET, text))
        text = (' "' + PROFILE + '=$PROFILE_UUID"\n').encode() + b'github_pat_' + b'Z' * 25
        self.assertIn('access token', guard.inspect(TARGET, text))
        text = (' "' + TEAM + '=$TEAM_ID"\n').encode() + b'/' + b'Users' + b'/' + b'someone/private'
        self.assertIn('personal filesystem path', guard.inspect(TARGET, text))


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve(); self.home = self.root / 'home'; self.home.mkdir()
        self.runner = self.root / 'runner'; self.runner.mkdir()
        self.bin = self.root / 'bin'; self.bin.mkdir()
        security = self.bin / 'security'
        security.write_text('#!/bin/bash\nprintf "%s\\n" "$1" >> "$FAKE_LOG"\n'
                            'if [[ "${FAKE_FAIL:-}" == "$1" ]]; then exit 1; fi\n'
                            'if [[ "$1" == list-keychains && "$*" == *" -s "* && "${FAKE_LIE:-}" != yes ]]; then printf "\\\"%s\\\"\\n" "${@:5}" > "$FAKE_SEARCH_STATE"; fi\n'
                            'if [[ "$1" == list-keychains && "$*" != *" -s "* ]]; then /bin/cat "$FAKE_SEARCH_STATE"; fi\n'
                            'if [[ "$1" == delete-keychain && "${FAKE_DELETE_LIE:-}" != yes ]]; then /bin/rm -f -- "$2"; fi\n')
        security.chmod(0o755)
        original = (HERE / 'kin-sign-cleanup.sh').read_text()
        self.assertIn('exit 1\n\nset +x\nset -euo pipefail\n', original)
        # A disposable copy omits the guard solely to exercise fake commands.
        body = original.split('exit 1\n\n', 1)[1]
        self.script = self.root / 'cleanup-test.sh'; self.script.write_text('#!/bin/bash\n' + body)
        self.work = self.runner / 'kin-sign-7-1'; self.work.mkdir()
        (self.work / 'search-list-original').write_text('"/synthetic/original.keychain"\n')
        (self.work / 'signing.keychain-db').write_bytes(b'fake')
        self.profile_uuid = str(uuid.UUID(int=1)).upper()
        directory = self.home / 'Library/MobileDevice/Provisioning Profiles'; directory.mkdir(parents=True)
        self.profile = directory / (self.profile_uuid + '.mobileprovision'); self.profile.write_bytes(b'synthetic')
        st = self.profile.stat()
        (self.work / 'owned-profile').write_text(str(self.profile) + '\n')
        (self.work / 'profile-identity').write_text('%d:%d\n' % (st.st_dev, st.st_ino))
        (self.work / 'profile-sha256').write_text(hashlib.sha256(b'synthetic').hexdigest() + '\n')
        (self.work / 'profile-staging').touch()
        (self.root / 'search-state').write_text('"/synthetic/other.keychain"\n')
        (self.work / 'identity.p12').write_bytes(b'synthetic-sensitive')
        (self.work / 'security.log').write_bytes(b'synthetic-sensitive')
        (self.work / 'codesign0').write_bytes(b'synthetic-certificate')
        self.env = {'PATH': str(self.bin) + ':/usr/bin:/bin', 'HOME': str(self.home),
                    'RUNNER_TEMP': str(self.runner), 'GITHUB_RUN_ID': '7', 'GITHUB_RUN_ATTEMPT': '1',
                    'PROFILE_UUID': self.profile_uuid, 'FAKE_LOG': str(self.root / 'calls'),
                    'FAKE_SEARCH_STATE': str(self.root / 'search-state')}

    def cleanup(self, fail=None):
        env = dict(self.env)
        if fail: env['FAKE_FAIL'] = fail
        return subprocess.run(['bash', str(self.script)], env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=5)

    def test_owned_cleanup_restores_and_removes_synthetic_material(self):
        result = self.cleanup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.profile.exists()); self.assertFalse(self.work.exists())
        self.assertEqual((self.root / 'calls').read_text().splitlines(), ['list-keychains', 'list-keychains', 'delete-keychain'])

    def test_changed_or_partial_profile_is_preserved_and_failure_reported(self):
        self.profile.write_bytes(b'changed')
        result = self.cleanup()
        self.assertNotEqual(result.returncode, 0); self.assertEqual(self.profile.read_bytes(), b'changed')
        self.assertTrue((self.work / 'owned-profile').is_file())
        self.assertTrue((self.work / 'profile-identity').is_file())
        self.assertFalse((self.work / 'identity.p12').exists()); self.assertFalse((self.work / 'security.log').exists())
        self.assertFalse((self.work / 'codesign0').exists())

    def test_incomplete_stage_never_deletes_unowned_profile(self):
        (self.work / 'owned-profile').unlink()
        result = self.cleanup()
        self.assertNotEqual(result.returncode, 0); self.assertEqual(self.profile.read_bytes(), b'synthetic')
        self.assertTrue((self.work / 'profile-staging').exists())

    def test_security_failure_is_not_reported_as_success(self):
        result = self.cleanup('delete-keychain')
        self.assertNotEqual(result.returncode, 0); self.assertIn(b'Cleanup incomplete', result.stderr)
        self.assertFalse(self.profile.exists()); self.assertTrue((self.work / 'signing.keychain-db').exists())
        self.assertTrue((self.work / 'search-list-original').exists()); self.assertFalse((self.work / 'identity.p12').exists())
        retry = self.cleanup()
        self.assertEqual(retry.returncode, 0, retry.stderr); self.assertFalse(self.work.exists())

    def test_search_list_restore_failure_is_not_reported_as_success(self):
        result = self.cleanup('list-keychains')
        self.assertNotEqual(result.returncode, 0); self.assertIn(b'Cleanup incomplete', result.stderr)
        self.assertFalse(self.profile.exists()); self.assertTrue((self.work / 'search-list-original').exists())
        self.assertIn('delete-keychain', (self.root / 'calls').read_text().splitlines())
        retry = self.cleanup()
        self.assertEqual(retry.returncode, 0, retry.stderr); self.assertFalse(self.work.exists())

    def test_restore_success_without_actual_state_change_fails_and_can_recover(self):
        env = dict(self.env, FAKE_LIE='yes')
        result = subprocess.run(['bash', str(self.script)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        self.assertNotEqual(result.returncode, 0); self.assertTrue((self.work / 'search-list-original').exists())
        retry = self.cleanup(); self.assertEqual(retry.returncode, 0, retry.stderr)

    def test_keychain_symlink_is_preserved_and_reported(self):
        keychain = self.work / 'signing.keychain-db'; keychain.unlink(); keychain.symlink_to(self.root / 'elsewhere')
        result = self.cleanup()
        self.assertNotEqual(result.returncode, 0); self.assertTrue(keychain.is_symlink())
        self.assertNotIn('delete-keychain', (self.root / 'calls').read_text().splitlines())

    def test_missing_or_linked_ownership_metadata_does_not_delete_profile(self):
        (self.work / 'profile-identity').unlink()
        (self.work / 'profile-identity').symlink_to(self.root / 'elsewhere')
        result = self.cleanup()
        self.assertNotEqual(result.returncode, 0); self.assertEqual(self.profile.read_bytes(), b'synthetic')
        self.assertTrue((self.work / 'owned-profile').is_file())

    def test_delete_success_without_removal_is_failure_with_recovery_evidence(self):
        result = subprocess.run(['bash', str(self.script)], env=dict(self.env, FAKE_DELETE_LIE='yes'),
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.work / 'signing.keychain-db').exists())
        self.assertTrue((self.work / 'search-list-original').exists())
        self.assertFalse((self.work / 'identity.p12').exists())
        retry = self.cleanup(); self.assertEqual(retry.returncode, 0, retry.stderr)

    def test_missing_search_list_or_workspace_is_unverified(self):
        (self.work / 'search-list-original').unlink()
        result = self.cleanup(); self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.work.exists())
        other = dict(self.env, GITHUB_RUN_ID='8')
        result = subprocess.run(['bash', str(self.script)], env=other, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=5)
        self.assertNotEqual(result.returncode, 0); self.assertIn(b'cannot be verified', result.stderr)

    def test_forged_owned_marker_does_not_remove_unrelated_profile(self):
        other = self.root / 'other-profile'; other.write_bytes(b'unrelated')
        (self.work / 'owned-profile').write_text(str(other) + '\n')
        result = self.cleanup(); self.assertNotEqual(result.returncode, 0)
        self.assertEqual(other.read_bytes(), b'unrelated'); self.assertTrue(self.profile.exists())


if __name__ == '__main__': unittest.main()
