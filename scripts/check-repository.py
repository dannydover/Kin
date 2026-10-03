#!/usr/bin/env python3
"""Fail closed on unintended repository data; inspect Git's staged content, not logs.

This deterministic guard complements human review. It cannot prove that arbitrary
prose is fictional or detect every possible secret. Review changed fixtures and
artwork before updating the allowlist.
"""
from pathlib import PurePosixPath
import hashlib
import re
import struct
import subprocess
import sys

APPROVED_PNG = {
    # Approved parent-child K artwork; no contact photos or screenshots.
    'Kin/Assets.xcassets/AppIcon.appiconset/AppIcon.png': '0ddf69cc402573ea9abd38f78c76bac5fbdf47732707679bce4347c91e00fa52',
    'Kin/Assets.xcassets/KinLogo.imageset/KinLogo.png': '0ddf69cc402573ea9abd38f78c76bac5fbdf47732707679bce4347c91e00fa52',
}
ROOT_FILES = {'.gitignore', 'LICENSE', 'README.md', 'SECURITY.md', 'Package.swift'}
TEXT_SUFFIXES = {'.swift', '.json', '.svg', '.py', '.sh', '.pbxproj', '.xcscheme', '.xcworkspacedata', '.xcprivacy', '.md', '.yml'}
PREFIXES = ('Kin/', 'KinTests/', 'KinUITests/', 'Kin.xcodeproj/', 'scripts/', '.github/workflows/')
BLOCKED_PARTS = {'xcuserdata', '__pycache__', '.build', 'DerivedData', 'evidence', '.swiftpm'}
PATTERNS = {
    'personal filesystem path': rb'/(?:Users|home)/[^/\s]+|/(?:Volumes)/|/var/(?:folders)/',
    'private key': rb'-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----',
    'access token': rb'(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|sk-[A-Za-z0-9]{20,}',
    'signing team': rb'(?:DEVELOPMENT_TEAM|DevelopmentTeam)\s*=\s*(?!"";)[^;\s]+',
    'provisioning profile': rb'PROVISIONING_PROFILE(?:_SPECIFIER)?\s*=\s*(?!"";)[^;\s]+',
    'device identifier': rb'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b',
    'literal UUID': rb'\b[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b',
}

def inspect(name, data, mode='100644'):
    errors = []
    path = PurePosixPath(name)
    if mode not in {'100644', '100755'}:
        errors.append('symlinks and submodules are not allowed')
    if any(part in BLOCKED_PARTS for part in path.parts):
        errors.append('private/generated directory')
    if name not in ROOT_FILES and not (name.startswith(PREFIXES) and path.suffix in TEXT_SUFFIXES) and name not in APPROVED_PNG:
        errors.append('file is outside the reviewed source/asset allowlist')
    if name in APPROVED_PNG:
        if hashlib.sha256(data).hexdigest() != APPROVED_PNG[name]:
            errors.append('artwork changed: requires visual and metadata review')
        if not data.startswith(b'\x89PNG\r\n\x1a\n'):
            errors.append('invalid PNG')
        else:
            offset = 8
            while offset + 12 <= len(data):
                size = struct.unpack('>I', data[offset:offset + 4])[0]
                kind = data[offset + 4:offset + 8]
                if kind not in {b'IHDR', b'IDAT', b'IEND', b'sRGB', b'gAMA', b'cHRM', b'pHYs'}:
                    errors.append('unreviewed PNG metadata')
                offset += size + 12
            if offset != len(data): errors.append('invalid PNG chunk size')
    else:
        try: data.decode('utf-8')
        except UnicodeDecodeError: errors.append('unexpected binary data')
        for label, pattern in PATTERNS.items():
            if re.search(pattern, data): errors.append(label)
        emails = re.findall(rb'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', data)
        if any(email != b'kin-support@intriguingideas.com' for email in emails):
            errors.append('unreviewed email address')
    return errors

def main():
    entries = subprocess.check_output(['git', 'ls-files', '--stage', '-z']).split(b'\0')
    failures = []
    count = 0
    for entry in entries:
        if not entry: continue
        header, raw_name = entry.split(b'\t', 1)
        mode, oid, stage = header.decode().split()
        name = raw_name.decode()
        if stage != '0': failures.append((name, 'unmerged index entry')); continue
        data = subprocess.check_output(['git', 'cat-file', 'blob', oid])
        failures.extend((name, error) for error in inspect(name, data, mode))
        count += 1
    for name, reason in failures:
        print(f'{name}: {reason}')  # Never print matched private values.
    if failures: return 1
    print(f'Repository guard passed: {count} indexed files; reviewed artwork and no prohibited data patterns.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
