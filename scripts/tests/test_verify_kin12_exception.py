"""The one-time preflight is fail-closed and never publishes a release."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('exception', Path(__file__).parents[1] / 'verify-kin12-exception.py')
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)
VALIDATION = 'b' * 40


def fake_git(changed):
    def run(*args):
        if args[0] == 'rev-parse':
            return args[1].removesuffix('^{commit}')
        if args[0] == 'merge-base':
            return ''
        if args[0] == 'diff':
            if '--diff-filter=DT' in args:
                return ''
            return '\0'.join(changed) + '\0'
        raise AssertionError(args)
    return run


class OneTimePreflightTests(unittest.TestCase):
    def test_accepts_only_allowed_test_and_ci_paths(self):
        self.assertEqual(policy.verify(VALIDATION, fake_git(['KinUITests/KinUITests.swift'])),
                         ['KinUITests/KinUITests.swift'])

    def test_rejects_app_build_project_and_unlisted_paths(self):
        for path in ('Kin/Views/PersonEditor.swift', 'Kin.xcodeproj/project.pbxproj',
                     'scripts/new-build-script.py', '.github/workflows/draft-release.yml'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                policy.verify(VALIDATION, fake_git([path]))

    def test_rejects_short_or_symbolic_revision(self):
        for revision in ('main', 'b' * 39, 'B' * 40):
            with self.subTest(revision=revision), self.assertRaises(ValueError):
                policy.verify(revision, fake_git([]))

    def test_rejects_policy_or_ci_only_changes(self):
        for changed in ([], ['scripts/RELEASING.md'], ['.github/workflows/ci.yml']):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                policy.verify(VALIDATION, fake_git(changed))

    def test_rejects_deletions_and_type_changes_even_at_allowed_paths(self):
        def diff_with_removal(*args):
            if '--diff-filter=DT' in args:
                return 'KinUITests/KinUITests.swift\0'
            return fake_git(['KinUITests/KinUITests.swift'])(*args)
        with self.assertRaises(ValueError):
            policy.verify(VALIDATION, diff_with_removal)

    def test_rejects_missing_ancestry(self):
        def fail(*args):
            if args[0] == 'merge-base':
                raise __import__('subprocess').CalledProcessError(1, args)
            return fake_git([])(*args)
        with self.assertRaises(__import__('subprocess').CalledProcessError):
            policy.verify(VALIDATION, fail)


if __name__ == '__main__':
    unittest.main()
