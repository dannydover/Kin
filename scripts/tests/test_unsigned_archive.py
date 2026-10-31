"""Synthetic checks for unsigned archive identity; no signing or Apple access."""
import importlib.util
from pathlib import Path
import unittest
import uuid

spec = importlib.util.spec_from_file_location('archive', Path(__file__).parents[1] / 'verify-unsigned-archive.py')
archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive)


class ArchiveMetadataTests(unittest.TestCase):
    def setUp(self):
        self.version, self.build, self.sdk = '1.3.0', '7', '27.0'
        self.sdk_build, self.xcode_build = 'SDKBUILD', 'XCODEBUILD'
        self.app = {'CFBundleIdentifier': archive.BUNDLE, 'CFBundleShortVersionString': self.version,
                    'CFBundleVersion': self.build, 'CFBundleExecutable': 'Kin',
                    'DTPlatformName': 'iphoneos', 'DTSDKName': 'iphoneos' + self.sdk,
                    'DTSDKBuild': self.sdk_build, 'DTXcodeBuild': self.xcode_build}
        self.info = {'ApplicationProperties': {'CFBundleIdentifier': archive.BUNDLE,
                     'CFBundleShortVersionString': self.version, 'CFBundleVersion': self.build,
                     'ApplicationPath': 'Applications/Kin.app', 'Architectures': ['arm64'], 'Team': '', 'SigningIdentity': ''}}
        self.ident = str(uuid.UUID(int=1)).upper()
        self.pairs = [('arm64', self.ident)]

    def check(self):
        archive.validate_metadata(self.app, self.info, self.version, self.build, self.sdk, self.sdk_build, self.xcode_build,
                                  self.pairs, self.pairs)

    def test_valid_identity_and_uuid(self):
        self.check()
        self.assertEqual(archive.parse_uuids(f'UUID: {self.ident} (arm64) synthetic-path'), self.pairs)

    def test_app_identity_platform_and_sdk_fail_closed(self):
        for key, value in [('CFBundleIdentifier', 'other'), ('CFBundleShortVersionString', '1.2.0'),
                           ('CFBundleVersion', '8'), ('CFBundleExecutable', '../Kin'),
                           ('DTPlatformName', 'iphonesimulator'), ('DTSDKName', 'iphoneos27.1'),
                           ('DTSDKBuild', 'OTHER'), ('DTXcodeBuild', 'OTHER')]:
            with self.subTest(key=key):
                old = self.app[key]; self.app[key] = value
                with self.assertRaises(ValueError): self.check()
                self.app[key] = old

    def test_archive_identity_and_signing_fail_closed(self):
        props = self.info['ApplicationProperties']
        for key, value in [('CFBundleIdentifier', 'other'), ('CFBundleShortVersionString', '1.2.0'),
                           ('CFBundleVersion', '8'), ('ApplicationPath', '../Kin.app'),
                           ('Team', 'unexpected'), ('SigningIdentity', 'unexpected'), ('Architectures', ['x86_64'])]:
            with self.subTest(key=key):
                old = props[key]; props[key] = value
                with self.assertRaises(ValueError): self.check()
                props[key] = old

    def test_dsym_mismatch_and_wrong_architecture_fail(self):
        for binary, dsym in [(self.pairs, []), (self.pairs, [('arm64', str(uuid.UUID(int=2)).upper())]),
                             ([('x86_64', self.ident)], [('x86_64', self.ident)])]:
            with self.assertRaises(ValueError):
                archive.validate_metadata(self.app, self.info, self.version, self.build, self.sdk, self.sdk_build, self.xcode_build, binary, dsym)

    def test_uuid_output_requires_unique_canonical_entries(self):
        line = f'UUID: {self.ident} (arm64) synthetic-path'
        for bad in ['', 'invalid', f'UUID: {"-" * 36} (arm64) synthetic-path', line + '\n' + line,
                    line + '\n' + f'UUID: {str(uuid.UUID(int=2)).upper()} (arm64) other']:
            with self.subTest(bad=bad), self.assertRaises(ValueError): archive.parse_uuids(bad)

    def test_invalid_version_build_or_sdk_fail(self):
        for version, build, sdk in [('1.3.0', '0', '27.0'), ('current', '7', '27.0'),
                                    ('1.3.0', '7', 'current')]:
            with self.assertRaises(ValueError):
                archive.validate_metadata(self.app, self.info, version, build, sdk, self.sdk_build, self.xcode_build, self.pairs, self.pairs)

class ArchiveCommandTests(unittest.TestCase):
    def test_complete_command_writes_only_sanitized_manifest_and_invalidates_stale(self):
        import contextlib
        import io
        import os
        import plistlib
        import subprocess
        import sys
        import tempfile
        from unittest import mock
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); p = root / 'unsigned.xcarchive'; app = p / 'Products/Applications/Kin.app'
            dsym = p / 'dSYMs/Kin.app.dSYM/Contents/Resources/DWARF/Kin'
            app.mkdir(parents=True); dsym.parent.mkdir(parents=True)
            (app / 'Kin').write_bytes(b'synthetic-binary'); dsym.write_bytes(b'synthetic-dsym')
            spec = importlib.util.spec_from_file_location('release', archive.ROOT / 'scripts/draft-release.py')
            release = importlib.util.module_from_spec(spec); spec.loader.exec_module(release)
            version, build = release.project_identity((archive.ROOT / 'Kin.xcodeproj/project.pbxproj').read_text())
            props = {'CFBundleIdentifier': archive.BUNDLE, 'CFBundleShortVersionString': version,
                     'CFBundleVersion': build}
            appinfo = dict(props, CFBundleExecutable='Kin', DTPlatformName='iphoneos',
                           DTSDKName='iphoneos27.0', DTSDKBuild='SDKBUILD', DTXcodeBuild='XCODEBUILD')
            info = {'ApplicationProperties': dict(props, ApplicationPath='Applications/Kin.app',
                                                   Architectures=['arm64'], Team='', SigningIdentity='')}
            (app / 'Info.plist').write_bytes(plistlib.dumps(appinfo)); (p / 'Info.plist').write_bytes(plistlib.dumps(info))
            ident = str(uuid.UUID(int=3)).upper(); head = 'a' * 40; tree = 'b' * 40; app_tree = 'c' * 40
            def fake_run(*args):
                if args == ('git', 'rev-parse', 'HEAD'): return head
                if args == ('git', 'rev-parse', 'HEAD^{tree}'): return tree
                if args == ('git', 'rev-parse', 'HEAD:Kin'): return app_tree
                if args == ('git', 'status', '--porcelain'): return ''
                if args == ('xcodebuild', '-version'): return 'Xcode 27.0\nBuild version XCODEBUILD'
                if args == ('xcodebuild', '-version', '-sdk', 'iphoneos', 'SDKVersion'): return '27.0'
                if args == ('xcodebuild', '-version', '-sdk', 'iphoneos', 'ProductBuildVersion'): return 'SDKBUILD'
                if args[:3] == ('xcrun', 'dwarfdump', '--uuid'): return f'UUID: {ident} (arm64) synthetic-path'
                raise AssertionError(args)
            out = root / 'manifest.json'
            with mock.patch.object(sys, 'argv', ['verify', str(p), str(out)]), \
                 mock.patch.dict(os.environ, {'GITHUB_SHA': head}), mock.patch.object(archive, 'run', side_effect=fake_run), \
                 mock.patch.object(archive.subprocess, 'run') as checker, contextlib.redirect_stdout(io.StringIO()):
                archive.main(); checker.assert_called_once()
                payload = out.read_text(); self.assertNotIn(d, payload); self.assertNotIn('synthetic-binary', payload)
                self.assertIn(head, payload); self.assertIn('"signed": false', payload)
                checker.side_effect = subprocess.CalledProcessError(1, ['synthetic'])
                with self.assertRaises(subprocess.CalledProcessError): archive.main()
                self.assertFalse(out.exists(), 'Failure must invalidate any earlier manifest')

    def test_checkout_mismatch_or_dirty_tree_invalidates_stale(self):
        import os
        import sys
        import tempfile
        from unittest import mock
        with tempfile.TemporaryDirectory() as d:
            output = Path(d) / 'manifest.json'; source = Path(d) / 'unused.xcarchive'
            head, tree, app_tree = 'a' * 40, 'b' * 40, 'c' * 40
            def fake_run(*args):
                return {('git', 'rev-parse', 'HEAD'): head,
                        ('git', 'rev-parse', 'HEAD^{tree}'): tree,
                        ('git', 'rev-parse', 'HEAD:Kin'): app_tree,
                        ('git', 'status', '--porcelain'): ' M synthetic'}[args]
            with mock.patch.object(sys, 'argv', ['verify', str(source), str(output)]), \
                 mock.patch.object(archive, 'run', side_effect=fake_run):
                for event_head in ('d' * 40, head):
                    output.write_text('stale')
                    with mock.patch.dict(os.environ, {'GITHUB_SHA': event_head}), self.assertRaises(ValueError):
                        archive.main()
                    self.assertFalse(output.exists())


class WorkflowBoundaryTests(unittest.TestCase):
    def test_pr_only_exercise_retains_only_sanitized_manifest(self):
        workflow = (archive.ROOT / '.github/workflows/ci.yml').read_text()
        exercise = (archive.ROOT / '.github/workflows/unsigned-archive-exercise.yml').read_text()
        self.assertIn('  pull_request:', exercise)
        job = exercise.split('  unsigned-archive-exercise:\n', 1)[1]
        self.assertIn("github.event_name == 'pull_request'", job)
        self.assertIn("github.head_ref == 'feature/kin-1.3-unsigned-archive'", job)
        self.assertIn('github.event.pull_request.head.repo.full_name == github.repository', job)
        self.assertIn('contents: read', job)
        self.assertIn('CODE_SIGNING_ALLOWED=NO', job)
        self.assertIn('archive', job)
        self.assertIn('path: ${{ runner.temp }}/KinUnsigned-manifest.json', job)
        self.assertIn('if-no-files-found: error', job)
        self.assertNotIn('secrets.', job)
        self.assertNotIn('contents: write', job)
        self.assertNotIn('KinUnsigned.xcarchive\n', job)
        self.assertIn('needs: [core-validation, simulator-tests, release-validation]', workflow)


if __name__ == '__main__': unittest.main()
