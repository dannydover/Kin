#!/usr/bin/env python3
"""Check selected build settings without emitting the JSON or identifiers."""
import json
import sys
from pathlib import Path

MAX_BYTES = 8 * 1024 * 1024

def check(path):
    try:
        with Path(path).open('rb') as source:
            data = source.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            return 'unavailable'
        entries = json.loads(data)
        if not isinstance(entries, list):
            return 'unavailable'
        targets = [v for v in entries if isinstance(v, dict) and v.get('target') == 'Kin']
        if len(targets) != 1 or not isinstance(targets[0].get('buildSettings'), dict):
            return 'unavailable'
        s = targets[0]['buildSettings']
        if s.get('CODE_SIGN_IDENTITY') == 'Apple Distribution':
            identity = 'distribution'
        elif s.get('CODE_SIGN_IDENTITY') == 'Apple Development':
            identity = 'development'
        else:
            identity = 'other-or-missing'
        if s.get('CONFIGURATION') != 'Dev' or s.get('PRODUCT_BUNDLE_IDENTIFIER') != 'com.intriguingideas.Kin.dev' or s.get('MARKETING_VERSION') != '1.3.0' or s.get('CURRENT_PROJECT_VERSION') != '7':
            return 'identity-' + identity + ' configuration-mismatch'
        if s.get('CODE_SIGN_STYLE') != 'Manual' or s.get('CODE_SIGNING_ALLOWED') != 'NO' or s.get('CODE_SIGNING_REQUIRED') != 'NO':
            return 'identity-' + identity + ' signing-settings-mismatch'
        return 'identity-' + identity + ' settings-match'
    except (OSError, ValueError, TypeError):
        return 'unavailable'

def main():
    result = check(sys.argv[1]) if len(sys.argv) == 2 else 'unavailable'
    print('KIN_DEV_SETTINGS ' + result)
    return 0 if result == 'identity-distribution settings-match' else 1

if __name__ == '__main__':
    raise SystemExit(main())
