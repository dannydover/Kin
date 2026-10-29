#!/usr/bin/env python3
"""Read-only file-diff preflight for the proposed Kin 1.2 exception.

This cannot verify CI, the signed archive, owner approval or App Store status.
It does not create, move or publish a tag or release.
"""
import re
import subprocess
import sys

SOURCE = '6172840e99687e917aa74db01442fbc4bfb0a6cc'
# Exact paths only. Any other difference, including an app build input, fails.
ALLOWED = frozenset({
    '.github/workflows/ci.yml',
    'KinUITests/EditorTestSupport.swift',
    'KinUITests/ExistingContactPreservationUITests.swift',
    'KinUITests/IndexMembershipUITests.swift',
    'KinUITests/KinUITests.swift',
    'KinUITests/NativeContactsTests.swift',
    'KinUITests/RelationshipChooserTests.swift',
    'scripts/ci-observe.py', 'scripts/ci-retain.py', 'scripts/ci-simulator.py',
    'scripts/tests/test_ci_observability.py',
    'scripts/RELEASING.md', 'scripts/verify-kin12-exception.py',
    'scripts/tests/test_verify_kin12_exception.py',
})


def verify(validation, git):
    if not re.fullmatch(r'[0-9a-f]{40}', validation):
        raise ValueError('Validation commit must be a full lowercase SHA.')
    if validation == SOURCE:
        raise ValueError('Validation must be a later distinct commit.')
    if git('rev-parse', SOURCE + '^{commit}').strip() != SOURCE:
        raise ValueError('Shipped source is not the expected exact commit.')
    if git('rev-parse', validation + '^{commit}').strip() != validation:
        raise ValueError('Validation commit does not resolve exactly.')
    if git('merge-base', '--is-ancestor', SOURCE, validation) != '':
        raise ValueError('Source ancestry could not be verified.')
    changed = set(filter(None, git('diff', '--name-only', '--no-renames', '-z', SOURCE, validation).split('\0')))
    removed_or_type_changed = git('diff', '--name-only', '--no-renames', '--diff-filter=DT', '-z', SOURCE, validation)
    if removed_or_type_changed:
        raise ValueError('Deleted or type-changed files require a different reviewed policy.')
    unexpected = sorted(changed - ALLOWED)
    if unexpected:
        raise ValueError('Non-allowlisted changes: ' + ', '.join(unexpected))
    if not any(path.startswith('KinUITests/') for path in changed):
        raise ValueError('Validation commit has no UI test changes to review.')
    return sorted(changed)


def git(*args):
    return subprocess.check_output(['git', *args], text=True)


def main():
    if len(sys.argv) != 2:
        sys.exit('Usage: verify-kin12-exception.py FULL_VALIDATION_SHA')
    try:
        changed = verify(sys.argv[1], git)
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit('Preflight refused: ' + str(error))
    print('Read-only file-diff preflight passed. Changed paths:')
    for path in changed:
        print('  ' + path)
    print('NOT release approval: separately verify build inputs, signed archive provenance,')
    print('exact validation main-push CI, reviews, release identity and App Store availability.')


if __name__ == '__main__':
    main()
