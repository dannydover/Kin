"""Verify distribution isolation with synthetic entitlements only."""
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('dev_entitlements', ROOT / 'scripts/check_dev_entitlements.py')
guard = importlib.util.module_from_spec(spec); spec.loader.exec_module(guard)
TEAM = 'ABCDEFGHIJ'
APP = TEAM + '.com.intriguingideas.Kin.dev'

def base():
    return {'application-identifier': APP, 'com.apple.developer.team-identifier': TEAM,
            'get-task-allow': False, 'beta-reports-active': True}

class DistributionIsolationTests(unittest.TestCase):
    def test_absent_or_exact_own_group_is_allowed(self):
        for groups in (None, [APP]):
            item = base()
            if groups is not None: item['keychain-access-groups'] = groups
            guard.check(item, TEAM)

    def test_foreign_shared_or_malformed_groups_are_rejected(self):
        for groups in ([], [TEAM + '.com.intriguingideas.Kin'], [APP, 'shared'],
                       ['shared'], APP, None, {}, [None]):
            with self.subTest(groups=groups):
                item = base(); item['keychain-access-groups'] = groups
                with self.assertRaises(ValueError): guard.check(item, TEAM)

    def test_wrong_identity_team_debug_and_extra_entitlements_are_rejected(self):
        changes = (
            {'application-identifier': TEAM + '.com.intriguingideas.Kin'},
            {'application-identifier': 'OTHERTEAM1.com.intriguingideas.Kin.dev'},
            {'com.apple.developer.team-identifier': 'OTHERTEAM1'},
            {'get-task-allow': True}, {'get-task-allow': 0},
            {'beta-reports-active': False},
            {'com.apple.security.application-groups': []},
            {'com.apple.developer.icloud-container-identifiers': []},
            {'com.apple.developer.ubiquity-kvstore-identifier': 'shared'},
            {'unexpected-entitlement': True},
        )
        for change in changes:
            with self.subTest(change=change):
                item = base(); item.update(change)
                with self.assertRaises(ValueError): guard.check(item, TEAM)
        for team in ('', 'bad', 'ABC-123456', None):
            with self.subTest(team=team):
                with self.assertRaises(ValueError): guard.check(base(), team)

    def test_dev_archive_generates_dsym_without_changing_release(self):
        data = subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(ROOT/'Kin.xcodeproj/project.pbxproj')])
        objects = json.loads(data)['objects']
        configs = [o for o in objects.values() if o.get('isa') == 'XCBuildConfiguration']
        project_dev = [o['buildSettings'] for o in configs if o.get('name') == 'Dev' and 'DEBUG_INFORMATION_FORMAT' in o['buildSettings']]
        project_release = [o['buildSettings'] for o in configs if o.get('name') == 'Release' and 'DEBUG_INFORMATION_FORMAT' in o['buildSettings']]
        self.assertEqual(len(project_dev), 1); self.assertEqual(project_dev[0]['DEBUG_INFORMATION_FORMAT'], 'dwarf-with-dsym')
        self.assertEqual(len(project_release), 1); self.assertEqual(project_release[0]['DEBUG_INFORMATION_FORMAT'], 'dwarf-with-dsym')

if __name__ == '__main__': unittest.main()
