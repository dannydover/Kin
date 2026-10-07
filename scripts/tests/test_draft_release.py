"""Exercise release policy and API writes entirely with synthetic state."""
import importlib.util
import io
import urllib.error
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('draft_release', Path(__file__).parents[1] / 'draft-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
SHA = 'a' * 40
OLD = 'b' * 40
PROJECT = '''isa = XCBuildConfiguration;
 buildSettings = { MARKETING_VERSION = 9.0; }; name = Debug;
 isa = XCBuildConfiguration;
 buildSettings = { PRODUCT_BUNDLE_IDENTIFIER = com.intriguingideas.Kin;
 MARKETING_VERSION = 1.0; CURRENT_PROJECT_VERSION = 7; }; name = Release;'''


class FakeAPI:
    def __init__(self):
        self.main = SHA
        self.releases = []
        self.tags = {}
        self.posts = []
        self.runs = [dict(id=3, run_number=3, run_attempt=1, head_sha=SHA,
                          event='push', head_branch='main', path='.github/workflows/ci.yml',
                          status='completed', conclusion='success')]
        self.jobs = [dict(name='validate', status='completed', conclusion='success')]

    def pages(self, path, key=None):
        if path == '/releases':
            return self.releases
        if path.startswith('/actions/workflows/'):
            return self.runs
        if '/attempts/1/jobs' in path:
            return self.jobs
        raise AssertionError(path)

    def request(self, path, data=None):
        if path == '/git/ref/heads/main':
            return {'object': {'sha': self.main}}
        self.posts.append((path, data))
        if path == '/releases/generate-notes':
            return {'body': 'Synthetic public changes.'}
        if path == '/releases':
            result = dict(data, html_url='https://github.com/example/repo/releases/1')
            self.releases.append(result)
            return result
        raise AssertionError(path)

    def tag_commit(self, tag):
        return self.tags.get(tag)


def fake_git(*args):
    if args[0] == 'rev-parse':
        return SHA
    if args[0] == 'show':
        return PROJECT
    if args[0] == 'diff':
        return ''
    raise AssertionError(args)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.api = FakeAPI()
        self.git = patch.object(release, 'git', side_effect=fake_git)
        self.ancestry = patch.object(release.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0))
        quiet = patch('builtins.print')
        quiet.start()
        self.addCleanup(quiet.stop)
        self.git.start()
        self.ancestry.start()
        self.addCleanup(self.git.stop)
        self.addCleanup(self.ancestry.stop)

    def create(self, **kwargs):
        values = dict(sha=SHA, version='1.0', build='7', previous='', main_sha=SHA)
        values.update(kwargs)
        release.create_draft(self.api, **values)

    def refused(self, **kwargs):
        with self.assertRaises(release.Refused):
            self.create(**kwargs)
        self.assertFalse(any(path == '/releases' for path, _ in self.api.posts))

    def test_creates_only_draft_with_exact_identity_and_no_assets(self):
        self.create()
        payload = self.api.posts[-1][1]
        self.assertEqual(payload['target_commitish'], SHA)
        self.assertEqual(payload['tag_name'], 'v1.0.0')
        self.assertIs(payload['draft'], True)
        self.assertIs(payload['prerelease'], False)
        self.assertEqual(payload['make_latest'], 'false')
        self.assertIn('build=7', payload['body'])
        self.assertEqual([p for p, _ in self.api.posts], ['/releases/generate-notes', '/releases'])

    def test_rerun_preserves_reviewed_draft_without_tag(self):
        self.create()
        self.api.releases[0]['body'] += '\nHuman-reviewed notes.'
        body = self.api.releases[0]['body']
        self.api.posts.clear()
        self.create()
        self.assertEqual(self.api.posts, [])
        self.assertEqual(self.api.releases[0]['body'], body)

    def test_rerun_preserves_published_release(self):
        self.create()
        self.api.releases[0]['draft'] = False
        self.api.tags['v1.0.0'] = SHA
        self.api.posts.clear()
        self.create()
        self.assertEqual(self.api.posts, [])

    def test_first_release_rerun_after_later_publication_is_noop(self):
        self.create()
        self.api.releases[0]['draft'] = False
        self.api.tags['v1.0.0'] = SHA
        self.api.releases.append(dict(tag_name='v2.0.0', draft=False, prerelease=False))
        self.api.posts.clear()
        self.create()
        self.assertEqual(self.api.posts, [])

    def test_rejects_moving_refs_invalid_version_and_build(self):
        for kwargs in [dict(sha='main'), dict(sha='a' * 39), dict(version='01.0'),
                       dict(version='1.0; echo unsafe'), dict(build='0'), dict(build='7.1')]:
            with self.subTest(kwargs=kwargs):
                self.refused(**kwargs)

    def test_rejects_source_version_or_build_mismatch(self):
        self.refused(version='2.0')
        self.refused(build='8')

    def test_rejects_ambiguous_project_settings(self):
        for project in [PROJECT + PROJECT, PROJECT.replace('MARKETING_VERSION = 1.0', 'MARKETING_VERSION = inherited')]:
            with self.subTest(project=project), patch.object(release, 'git', side_effect=lambda *a: project if a[0] == 'show' else fake_git(*a)):
                self.refused()

    def test_rejects_source_outside_main(self):
        with patch.object(release.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)):
            self.refused()

    def test_rejects_workflow_difference(self):
        with patch.object(release, 'git', side_effect=lambda *a: 'changed' if a[0] == 'diff' else fake_git(*a)):
            self.refused()

    def test_rejects_main_movement(self):
        self.api.main = OLD
        self.refused()

    def test_rejects_latest_failed_or_pending_ci_attempt(self):
        for status, conclusion in [('completed', 'failure'), ('in_progress', None), ('completed', 'cancelled')]:
            self.api.runs.append(dict(self.api.runs[0], run_attempt=2, status=status, conclusion=conclusion))
            self.refused()
            self.api.runs.pop()

    def test_rejects_wrong_ci_sha_event_branch_or_workflow(self):
        for key, value in [('head_sha', OLD), ('event', 'pull_request'), ('head_branch', 'other'), ('path', '.github/workflows/other.yml')]:
            original = self.api.runs[0][key]
            self.api.runs[0][key] = value
            self.refused()
            self.api.runs[0][key] = original

    def test_rejects_skipped_or_missing_validation_job(self):
        self.api.jobs[0]['conclusion'] = 'skipped'
        self.refused()
        self.api.jobs = []
        self.refused()

    def test_rejects_conflicting_tag_and_alternate_version_tag(self):
        self.api.tags['v1.0.0'] = OLD
        self.refused()
        self.api.tags.clear()
        self.api.tags['v1.0'] = SHA
        self.refused()
        self.api.tags.clear()
        self.api.releases = [dict(tag_name='v1.0')]
        self.refused()

    def test_rejects_unverifiable_release_or_changed_build(self):
        self.create()
        self.api.posts.clear()
        self.api.releases[0]['body'] = 'Manually created release with unknown identity.'
        self.refused()

    def test_accepts_matching_existing_annotated_or_lightweight_tag(self):
        self.api.tags['v1.0.0'] = SHA
        self.create()
        self.assertTrue(self.api.releases[0]['draft'])

    def test_requires_published_ancestor_for_previous_tag(self):
        self.api.releases = [dict(tag_name='v0.9.0', draft=False, prerelease=False)]
        self.api.tags['v0.9.0'] = OLD
        self.refused()
        self.create(previous='v0.9.0')
        self.assertEqual(self.api.posts[0][1]['previous_tag_name'], 'v0.9.0')

    def test_rejects_unpublished_or_nonancestor_previous(self):
        self.refused(previous='v0.9.0')
        self.api.releases = [dict(tag_name='v0.9.0', draft=False, prerelease=False)]
        self.api.tags['v0.9.0'] = OLD
        with patch.object(release.subprocess, 'run', side_effect=[subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 1)]):
            self.refused(previous='v0.9.0')

    def test_uncertain_create_response_is_safe_to_retry(self):
        original = self.api.request
        def request(path, data=None):
            result = original(path, data)
            if path == '/releases':
                raise release.Refused('Synthetic lost response')
            return result
        with patch.object(self.api, 'request', side_effect=request):
            with self.assertRaises(release.Refused):
                self.create()
        self.api.posts.clear()
        self.create()
        self.assertEqual(len(self.api.releases), 1)
        self.assertEqual(self.api.posts, [])

    def test_revalidates_state_after_note_generation(self):
        original = self.api.request
        def request(path, data=None):
            result = original(path, data)
            if path == '/releases/generate-notes':
                self.api.tags['v1.0.0'] = OLD
            return result
        with patch.object(self.api, 'request', side_effect=request):
            self.refused()


class ParsingTests(unittest.TestCase):
    def test_real_project_app_release_settings(self):
        project = Path(__file__).parents[2] / 'Kin.xcodeproj/project.pbxproj'
        version, build = release.project_identity(project.read_text())
        self.assertRegex(release.version_tag(version), r'^v[0-9]+\.[0-9]+\.[0-9]+$')
        self.assertRegex(build, r'^[1-9][0-9]*$')

    def test_version_aliases_use_one_tag(self):
        self.assertEqual(release.version_tag('1.0'), release.version_tag('1.0.0'))

    def test_dispatch_guard_rejects_wrong_repository_branch_event_and_missing_token(self):
        valid = dict(GITHUB_REPOSITORY='dannydover/Kin', GITHUB_REF='refs/heads/main',
                     GITHUB_EVENT_NAME='workflow_dispatch', GITHUB_TOKEN='synthetic')
        for key, value in [('GITHUB_REPOSITORY', 'other/repo'), ('GITHUB_REF', 'refs/heads/other'),
                           ('GITHUB_EVENT_NAME', 'push'), ('GITHUB_TOKEN', '')]:
            with self.subTest(key=key), patch.dict(release.os.environ, dict(valid, **{key: value}), clear=True):
                with patch.object(release, 'API') as api, self.assertRaises(release.Refused):
                    release.main()
                api.assert_not_called()

    def test_api_errors_do_not_echo_credentials_or_response_body(self):
        api = release.API('example/repo', 'synthetic-sensitive-token')
        for status in [403, 404, 422]:
            error = urllib.error.HTTPError('https://api.github.com/example', status,
                                          'synthetic-sensitive-token', {}, io.BytesIO(b'private body'))
            with patch.object(release.urllib.request, 'urlopen', side_effect=error):
                with self.assertRaises(release.Refused) as result:
                    api.request('/releases')
                self.assertNotIn('synthetic-sensitive-token', str(result.exception))
                self.assertNotIn('private body', str(result.exception))
                if status == 404:
                    self.assertIsNone(api.request('/git/ref/tags/v1.0.0', missing=True))

    def test_annotated_tag_resolution(self):
        api = release.API('example/repo', 'synthetic')
        with patch.object(api, 'request', side_effect=[{'object': {'type': 'tag', 'sha': OLD}},
                                                     {'object': {'type': 'commit', 'sha': SHA}}]):
            self.assertEqual(api.tag_commit('v1.0.0'), SHA)

    def test_pagination_includes_drafts_on_later_pages(self):
        api = release.API('example/repo', 'synthetic')
        with patch.object(api, 'request', side_effect=[[{}] * 100, [{'draft': True}]]) as request:
            self.assertEqual(len(api.pages('/releases')), 101)
            self.assertIn('page=2', request.call_args.args[0])


if __name__ == '__main__':
    unittest.main()
