import stat
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path
from unittest import mock
import importlib.util
spec = importlib.util.spec_from_file_location('check_ipa_layout', Path(__file__).resolve().parents[1] / 'check_ipa_layout.py')
check_ipa_layout = importlib.util.module_from_spec(spec); spec.loader.exec_module(check_ipa_layout)


class IpaLayoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.ipa = Path(self.temp.name) / 'synthetic.ipa'

    def create(self, extra=()):
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(self.ipa, 'w') as out:
                out.writestr('Payload/Kin.app/Info.plist', b'synthetic')
                out.writestr('Payload/Kin.app/Kin', b'synthetic')
                for name, data in extra: out.writestr(name, data)

    def test_expected_app_and_non_payload_metadata_are_allowed(self):
        self.create([('SwiftSupport/example', b'fake')])
        self.assertTrue(check_ipa_layout.check(self.ipa))

    def test_traversal_absolute_backslash_and_payload_conflicts_fail(self):
        for name in ('../escape', '/absolute', 'Payload/Kin.app/../../escape',
                     'Payload/Kin.app/evil\\path', 'Payload/Other.app/Info.plist',
                     'Payload/unexpected', 'Payload/Kin.app/Info.plist', 'Payload/Kin.app/Info.plist/'):
            with self.subTest(name=name):
                self.create([(name, b'fake')])
                with self.assertRaises(ValueError): check_ipa_layout.check(self.ipa)

    def test_symlinks_and_setid_are_rejected(self):
        for mode in (stat.S_IFLNK | 0o777, stat.S_IFREG | 0o4755):
            item = zipfile.ZipInfo('Payload/Kin.app/link'); item.create_system = 3; item.external_attr = mode << 16
            self.create([(item, b'fake')])
            with self.assertRaises(ValueError): check_ipa_layout.check(self.ipa)

    def test_truncated_symlinked_and_resource_limit_fail(self):
        self.ipa.write_bytes(b'not zip')
        with self.assertRaises(ValueError): check_ipa_layout.check(self.ipa)
        self.create(); link = Path(self.temp.name) / 'linked.ipa'; link.symlink_to(self.ipa)
        with self.assertRaises(ValueError): check_ipa_layout.check(link)
        with mock.patch.object(zipfile.ZipFile, 'infolist', return_value=[None] * 10001):
            with self.assertRaisesRegex(ValueError, 'entry-limit'): check_ipa_layout.check(self.ipa)


if __name__ == '__main__': unittest.main()
