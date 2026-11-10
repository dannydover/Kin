#!/usr/bin/env python3
"""Fail closed on shared-data entitlements in a proposed signed Kin Dev app."""
import plistlib
import re
import sys


def check(e, team):
    if not isinstance(team, str) or not re.fullmatch(r'[A-Z0-9]{10}', team) or not isinstance(e, dict):
        raise ValueError('invalid team or entitlements')
    app_id = team + '.com.intriguingideas.Kin.dev'
    if e.get('application-identifier') != app_id:
        raise ValueError('wrong application identifier')
    if e.get('com.apple.developer.team-identifier') != team:
        raise ValueError('wrong team')
    if e.get('get-task-allow', False) is not False:
        raise ValueError('debug entitlement enabled')
    # Apple derives the app's own group from application-identifier when this
    # optional entitlement is absent. If present, permit only that same group.
    if 'keychain-access-groups' in e and e['keychain-access-groups'] != [app_id]:
        raise ValueError('unexpected keychain access groups')
    allowed = {'application-identifier', 'com.apple.developer.team-identifier',
               'get-task-allow', 'keychain-access-groups', 'beta-reports-active'}
    if set(e) - allowed:
        raise ValueError('unexpected entitlement')
    if 'beta-reports-active' in e and e['beta-reports-active'] is not True:
        raise ValueError('unexpected beta reports entitlement')


if __name__ == '__main__':
    with open(sys.argv[1], 'rb') as f: check(plistlib.load(f), sys.argv[2])
