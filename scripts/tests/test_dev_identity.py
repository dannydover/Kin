"""Guard dev identity isolation and the frozen production configuration."""
import json
from pathlib import Path
import subprocess
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
BASE = 'b3f5bba74fcc6ecfd1cb52020a06ca8c3e1a2e6c'

def project(data):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', '-'], input=data))['objects']

class DevIdentityTests(unittest.TestCase):
    def test_production_configuration_protection_and_identity_unchanged(self):
        path = 'Kin.xcodeproj/project.pbxproj'
        original = project(subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT))
        current = project((ROOT / path).read_bytes())
        for key, value in original.items():
            if value['isa'] == 'XCConfigurationList':
                self.assertEqual(current[key]['buildConfigurations'][:2], value['buildConfigurations'])
                for field in ('defaultConfigurationName', 'defaultConfigurationIsVisible'):
                    self.assertEqual(current[key].get(field), value.get(field))
            elif value['isa'] == 'XCBuildConfiguration' and value.get('buildSettings', {}).get('PRODUCT_BUNDLE_IDENTIFIER') == 'com.intriguingideas.Kin':
                expected = json.loads(json.dumps(value))
                expected['buildSettings']['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'Kin'
                # Deliberate next-release metadata; all other production settings stay frozen.
                expected['buildSettings']['MARKETING_VERSION'] = '1.1.0'
                expected['buildSettings']['CURRENT_PROJECT_VERSION'] = '5'
                self.assertEqual(current[key], expected, key)
            else:
                self.assertEqual(current[key], value, key)
        changed = subprocess.check_output(['git', 'diff', BASE, '--name-only', '--', 'Kin/Core/NotebookProtection.swift', 'Kin/PrivacyInfo.xcprivacy'], cwd=ROOT).decode().splitlines()
        # Post-v1 UI and explicit list membership are authorized on this branch.
        # The approved icon selector changes; protection, schema, privacy and bundle identity stay frozen.
        self.assertEqual(changed, [])
        path = 'Kin/Core/KinStore.swift'
        original_store = subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT).decode()
        current_store = (ROOT / path).read_text()
        def schema(source):
            return source.split('private static let model:', 1)[1].split('/// A supplied SQLite URL', 1)[0]
        self.assertEqual(schema(current_store), schema(original_store))

    def test_dev_configuration(self):
        objects = project((ROOT / 'Kin.xcodeproj/project.pbxproj').read_bytes())
        configs = [x['buildSettings'] for x in objects.values() if x.get('isa') == 'XCBuildConfiguration' and x.get('name') == 'Dev']
        self.assertEqual(len(configs), 4)
        ids = {c.get('PRODUCT_BUNDLE_IDENTIFIER') for c in configs if c.get('PRODUCT_BUNDLE_IDENTIFIER')}
        self.assertEqual(ids, {'com.intriguingideas.Kin.dev', 'com.intriguingideas.Kin.dev.tests', 'com.intriguingideas.Kin.dev.uitests'})
        app = next(c for c in configs if c.get('PRODUCT_BUNDLE_IDENTIFIER') == 'com.intriguingideas.Kin.dev')
        self.assertEqual(app['INFOPLIST_KEY_CFBundleDisplayName'], 'Kin Dev')
        self.assertEqual(app['MARKETING_VERSION'], '1.1.0')
        self.assertEqual(app['CURRENT_PROJECT_VERSION'], '5')
        self.assertEqual(app['ASSETCATALOG_COMPILER_APPICON_NAME'], 'AppIconDev')
        self.assertEqual(app['CODE_SIGN_ENTITLEMENTS'], 'Development/KinDev.entitlements')
        import plistlib
        self.assertEqual(plistlib.loads((ROOT / app['CODE_SIGN_ENTITLEMENTS']).read_bytes()), {})
        for c in configs:
            for key in c:
                self.assertFalse(any(term in key for term in ['APP_GROUP', 'ICLOUD', 'KEYCHAIN']), key)
        self.assertEqual(len([x for x in objects.values() if x.get('isa') == 'PBXNativeTarget']), 3, 'No new extensions')

    def test_dev_scheme_never_selects_production_configuration(self):
        scheme = ET.parse(ROOT / 'Kin.xcodeproj/xcshareddata/xcschemes/Kin Dev.xcscheme')
        for action in scheme.getroot():
            if 'buildConfiguration' in action.attrib:
                self.assertEqual(action.attrib['buildConfiguration'], 'Dev')
        self.assertEqual((ROOT / 'Kin.xcodeproj/xcshareddata/xcschemes/Kin.xcscheme').read_bytes(), subprocess.check_output(['git', 'show', f'{BASE}:Kin.xcodeproj/xcshareddata/xcschemes/Kin.xcscheme'], cwd=ROOT))

class CompiledIdentityTests(unittest.TestCase):
    def test_install_guard_rejects_production_identity_and_shared_capabilities(self):
        import importlib.util
        import plistlib
        import tempfile
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location('check_dev_app', ROOT / 'scripts/check-dev-app.py')
        guard = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(guard)
        info = {'CFBundleIdentifier': guard.DEV_ID, 'CFBundleDisplayName': 'Kin Dev',
                'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIconDev'}}}
        unsigned = subprocess.CompletedProcess([], 1, b'', b'unsigned')
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            def write_info():
                (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            write_info()
            with patch.object(guard.subprocess, 'run', return_value=unsigned):
                guard.validate(app)
                info['CFBundleIdentifier'] = 'com.intriguingideas.Kin'
                write_info()
                with self.assertRaisesRegex(AssertionError, 'Wrong bundle ID'):
                    guard.validate(app)
                info['CFBundleIdentifier'] = guard.DEV_ID
                write_info()
                (app / 'PlugIns').mkdir()
                with self.assertRaisesRegex(AssertionError, 'extensions'):
                    guard.validate(app)
                (app / 'PlugIns').rmdir()
            for entitlement in [
                {'com.apple.security.application-groups': ['group.example.production']},
                {'application-identifier': 'TEAM.' + guard.DEV_ID,
                 'keychain-access-groups': ['TEAM.com.intriguingideas.Kin']},
            ]:
                signed = subprocess.CompletedProcess([], 0, plistlib.dumps(entitlement), b'')
                with patch.object(guard.subprocess, 'run', return_value=signed):
                    with self.assertRaises(AssertionError):
                        guard.validate(app)

if __name__ == '__main__':
    unittest.main()
