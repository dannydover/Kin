"""Synthetic GitHub responses; no credentials, GitHub writes or signing."""
import copy
import contextlib
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('evidence', Path(__file__).resolve().parents[1] / 'verify-hosted-ci-evidence.py')
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class HostedEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.sha = 'a' * 40
        self.run = {'id': 4, 'created_at': '2026-11-01T00:00:00Z', 'head_sha': self.sha,
                    'head_branch': 'main', 'event': 'push', 'path': '.github/workflows/ci.yml',
                    'status': 'completed', 'conclusion': 'success', 'run_attempt': 1}
        self.response = {'total_count': 1, 'workflow_runs': [self.run]}
        self.jobs = {'total_count': 5, 'jobs': [{'name': n, 'status': 'completed', 'conclusion': 'success',
                                                'run_id': 4, 'run_attempt': 1, 'head_sha': self.sha}
                                               for n in sorted(evidence.REQUIRED)]}

    def check(self, response=None, jobs=None):
        return evidence.verify_latest(self.sha, response or self.response, lambda *_: jobs or self.jobs)

    def test_exact_success(self):
        self.assertEqual(self.check(), (4, 1))

    def test_latest_failure_not_replaced_with_older_pass(self):
        newer = dict(self.run, id=5, created_at='2026-11-02T00:00:00Z', conclusion='failure')
        with self.assertRaises(ValueError): self.check({'total_count': 2, 'workflow_runs': [self.run, newer]})

    def test_wrong_run_identity_or_incomplete_run_fails(self):
        for key, value in [('head_sha', 'b' * 40), ('head_branch', 'other'), ('event', 'pull_request'),
                           ('path', '.github/workflows/other.yml'), ('status', 'in_progress'),
                           ('conclusion', 'failure'), ('run_attempt', 0)]:
            with self.subTest(key=key):
                response = copy.deepcopy(self.response); response['workflow_runs'][0][key] = value
                with self.assertRaises(ValueError): self.check(response)

    def test_incomplete_or_oversized_run_list_fails(self):
        for response in ({'total_count': 0, 'workflow_runs': []}, {'total_count': 2, 'workflow_runs': [self.run]},
                         {'total_count': 101, 'workflow_runs': [self.run]}):
            with self.subTest(response=response):
                with self.assertRaises(ValueError): self.check(response)

    def test_missing_duplicate_failed_or_other_attempt_jobs_fail(self):
        for change in ('missing', 'duplicate', 'failure', 'attempt', 'source', 'incomplete'):
            with self.subTest(change=change):
                jobs = copy.deepcopy(self.jobs)
                if change == 'missing': jobs['jobs'].pop(); jobs['total_count'] = 4
                if change == 'duplicate': jobs['jobs'][0]['name'] = jobs['jobs'][1]['name']
                if change == 'failure': jobs['jobs'][0]['conclusion'] = 'failure'
                if change == 'attempt': jobs['jobs'][0]['run_attempt'] = 2
                if change == 'source': jobs['jobs'][0]['head_sha'] = 'b' * 40
                if change == 'incomplete': jobs['total_count'] = 6
                with self.assertRaises(ValueError): self.check(jobs=jobs)

    def test_github_redirects_are_not_followed(self):
        self.assertIsNone(evidence.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://example.invalid'))

    def test_main_checks_exact_checkout_workflow_and_toolchain(self):
        environment = {'GITHUB_SHA': self.sha, 'GITHUB_TOKEN': 'synthetic-token',
                       'GITHUB_REPOSITORY': evidence.REPOSITORY, 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                       'GITHUB_REF': 'refs/heads/main'}
        values = {('git', 'rev-parse', 'HEAD'): self.sha,
                  ('git', 'rev-parse', 'refs/remotes/origin/main'): self.sha,
                  ('git', 'status', '--porcelain'): '',
                  ('xcodebuild', '-version'): 'Xcode 27.0\nBuild version 27A266a', ('uname', '-m'): 'arm64'}
        def fetch(path, token):
            self.assertEqual(token, 'synthetic-token')
            if path == '/git/ref/heads/main':
                return {'ref': 'refs/heads/main', 'object': {'type': 'commit', 'sha': self.sha}}
            if '/jobs?' in path: return self.jobs
            if path == '/actions/runs/4': return self.run
            return self.response
        def call():
            with mock.patch.dict(os.environ, environment, clear=True), mock.patch.object(evidence, 'command', side_effect=lambda *a: values[a]), \
                 mock.patch.object(evidence, 'fetch', side_effect=fetch), mock.patch.object(Path, 'read_bytes', return_value=b'synthetic-ci'), \
                 mock.patch.object(evidence, 'CI_SHA256', hashlib.sha256(b'synthetic-ci').hexdigest()):
                evidence.main()
        with contextlib.redirect_stdout(io.StringIO()) as output: call()
        self.assertNotIn('synthetic-token', output.getvalue())
        for key, value in [(('git', 'rev-parse', 'HEAD'), 'b' * 40),
                           (('git', 'rev-parse', 'refs/remotes/origin/main'), 'b' * 40),
                           (('git', 'status', '--porcelain'), 'dirty'),
                           (('xcodebuild', '-version'), 'Xcode 27.1'), (('uname', '-m'), 'x86_64')]:
            with self.subTest(key=key):
                original = values[key]; values[key] = value
                with self.assertRaises(ValueError): call()
                values[key] = original

    def test_main_rejects_wrong_event_without_api_access(self):
        env = {'GITHUB_SHA': self.sha, 'GITHUB_TOKEN': 'synthetic-token', 'GITHUB_REPOSITORY': evidence.REPOSITORY,
               'GITHUB_EVENT_NAME': 'pull_request', 'GITHUB_REF': 'refs/heads/main'}
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(evidence, 'fetch') as fetch:
            with self.assertRaises(ValueError): evidence.main()
            fetch.assert_not_called()

    def test_midflight_main_or_ci_change_fails(self):
        env = {'GITHUB_SHA': self.sha, 'GITHUB_TOKEN': 'synthetic-token', 'GITHUB_REPOSITORY': evidence.REPOSITORY,
               'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_REF': 'refs/heads/main'}
        values = {('git', 'rev-parse', 'HEAD'): self.sha, ('git', 'rev-parse', 'refs/remotes/origin/main'): self.sha,
                  ('git', 'status', '--porcelain'): '', ('xcodebuild', '-version'): 'Xcode 27.0\nBuild version 27A266a',
                  ('uname', '-m'): 'arm64'}
        for scenario in ('main', 'ci'):
            seen = {'main': 0, 'runs': 0}
            def fetch(path, _):
                if path == '/git/ref/heads/main':
                    seen['main'] += 1
                    sha = 'b' * 40 if scenario == 'main' and seen['main'] == 2 else self.sha
                    return {'ref': 'refs/heads/main', 'object': {'type': 'commit', 'sha': sha}}
                if '/jobs?' in path: return self.jobs
                if path == '/actions/runs/4': return self.run
                seen['runs'] += 1
                if scenario == 'ci' and seen['runs'] == 2:
                    newer = dict(self.run, id=5, created_at='2026-11-02T00:00:00Z', conclusion='failure')
                    return {'total_count': 2, 'workflow_runs': [self.run, newer]}
                return self.response
            with self.subTest(scenario=scenario), mock.patch.dict(os.environ, env, clear=True), \
                 mock.patch.object(evidence, 'command', side_effect=lambda *a: values[a]), \
                 mock.patch.object(evidence, 'fetch', side_effect=fetch), mock.patch.object(Path, 'read_bytes', return_value=b'synthetic-ci'), \
                 mock.patch.object(evidence, 'CI_SHA256', hashlib.sha256(b'synthetic-ci').hexdigest()):
                with self.assertRaises(ValueError): evidence.main()


if __name__ == '__main__': unittest.main()
