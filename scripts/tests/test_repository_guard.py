"""Synthetic negative cases for the publication guard; never use real secrets."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'guard', Path(__file__).resolve().parents[1] / 'check-repository.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class RepositoryGuardTests(unittest.TestCase):
    def test_private_values_are_rejected_without_echoing_them(self):
        samples = [
            b'/' + b'Users/example/project',
            b'/' + b'home/example/project',
            b'/' + b'Volumes/Example/project',
            b'/' + b'var/folders/example',
            b'DEVELOPMENT_' + b'TEAM = SYNTHETIC;',
            b'PROVISIONING_' + b'PROFILE_SPECIFIER = synthetic;',
            b'-----BEGIN ' + b'PRIVATE KEY-----',
            b'ghp_' + b'x' * 30,
            b'00000000-' + b'0000000000000000',
            b'00000000-' + b'0000-0000-0000-000000000000',
            b'synthetic' + b'@example.invalid',
        ]
        for value in samples:
            with self.subTest(value_type=samples.index(value)):
                errors = guard.inspect('Kin/Core/Example.swift', value)
                self.assertTrue(errors)
                self.assertNotIn(value.decode(), ' '.join(errors))

    def test_private_files_and_links_are_rejected(self):
        for name in ['evidence/result.md', 'Kin/contacts.vcf',
                     'Kin/photo.jpg', 'Kin/secret.p12', 'Kin/data.sqlite',
                     'Kin.xcodeproj/xcuserdata/settings.json']:
            self.assertTrue(guard.inspect(name, b'{}'))
        self.assertTrue(guard.inspect('Kin/Core/Example.swift', b'{}', '120000'))

    def test_artwork_changes_require_review(self):
        for name in guard.APPROVED_PNG:
            self.assertEqual(guard.inspect(name, Path(name).read_bytes()), [])
            self.assertTrue(guard.inspect(name, Path(name).read_bytes() + b'changed'))

    def test_source_and_empty_team_are_allowed(self):
        self.assertEqual(guard.inspect('Kin/Core/Example.swift', b'let id = UUID()'), [])
        self.assertEqual(guard.inspect('Kin.xcodeproj/project.pbxproj',
                                      b'DEVELOPMENT_' + b'TEAM = "";'), [])


if __name__ == '__main__':
    unittest.main()
