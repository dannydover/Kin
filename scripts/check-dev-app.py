#!/usr/bin/env python3
"""Fail closed before installing Kin Dev; never installs or provisions anything."""
import argparse
from pathlib import Path
import plistlib
import subprocess

DEV_ID = 'com.intriguingideas.Kin.dev'

def validate(app, require_signed=False):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == DEV_ID, 'Wrong bundle ID: installation forbidden'
    assert info['CFBundleDisplayName'] == 'Kin Dev', 'Wrong display name'
    assert info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'] == 'AppIconDev', 'Wrong icon'
    assert not (app / 'PlugIns').exists(), 'Unexpected extensions'
    assert not info.get('CFBundleURLTypes'), 'Unexpected shared URL handlers'
    assert not info.get('UIFileSharingEnabled'), 'Unexpected file sharing'
    signature = subprocess.run(['codesign', '--display', '--entitlements', ':-', str(app)], capture_output=True)
    entitlements = plistlib.loads(signature.stdout) if signature.returncode == 0 and signature.stdout.strip() else {}
    allowed = {'application-identifier', 'keychain-access-groups', 'get-task-allow', 'com.apple.developer.team-identifier'}
    assert set(entitlements) <= allowed, 'Unexpected shared/service entitlements'
    if entitlements:
        app_identifier = entitlements.get('application-identifier', '')
        assert app_identifier.endswith('.' + DEV_ID), 'Wrong signed identity'
        assert entitlements.get('keychain-access-groups', []) in ([], [app_identifier]), 'Shared keychain group'
    if require_signed:
        subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
        assert (app / 'embedded.mobileprovision').exists(), 'No embedded provisioning profile'
        profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')]))
        assert profile['Entitlements']['get-task-allow'] is True, 'Not a development profile'
        assert entitlements.get('get-task-allow') is True, 'Development debugging entitlement missing'
        team = entitlements['com.apple.developer.team-identifier']
        app_identifier = entitlements['application-identifier']
        assert app_identifier.endswith('.' + DEV_ID), 'Wrong signed identity'
        assert team in profile['TeamIdentifier'], 'Wrong profile team'
        assert entitlements.get('keychain-access-groups', []) in ([], [app_identifier]), 'Shared keychain group'
    print(f'Kin Dev identity/isolation passed ({"signed" if require_signed else "unsigned compilation check"}): {DEV_ID}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--require-signed', action='store_true')
    args = parser.parse_args()
    validate(args.app, args.require_signed)
