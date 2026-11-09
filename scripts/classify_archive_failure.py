#!/usr/bin/env python3
"""Emit only fixed hints from a bounded private Xcode archive log."""
import os
import stat
import sys

MAX_BYTES = 8 * 1024 * 1024
PATTERNS = {
    'missing-profile': (('no profiles for ', ' were found'), ('requires a provisioning profile',)),
    'missing-certificate': (('no signing certificate ', ' found'), ('no certificate for team ', ' matching')),
    'profile-certificate-mismatch': (('provisioning profile ', "doesn't include signing certificate"),),
    'signing-conflict': (('conflicting provisioning settings',), ('does not support automatic signing',)),
    'missing-team': (('requires a development team',),),
    'swift-compile': (('swift compiler error',), ('swift compile error',), ('.swift:', ': error:')),
    'linker': (('linker command failed',), ('undefined symbols for architecture',)),
    'missing-input': (('build input file cannot be found',),),
}

def classify(path):
    flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0)
    try:
        fd = os.open(path, flags)
        with os.fdopen(fd, 'rb') as source:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_BYTES:
                return 'unavailable'
            data = source.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            return 'unavailable'
        lines = data.decode('utf-8', 'replace').lower().splitlines()
        found = [label for label, groups in PATTERNS.items()
                 if any(all(phrase in line for phrase in group)
                        for line in lines for group in groups)]
        return found[0] if len(found) == 1 else 'multiple' if found else 'unclassified'
    except (OSError, ValueError):
        return 'unavailable'

def main():
    category = classify(sys.argv[1]) if len(sys.argv) == 2 else 'unavailable'
    print('Kin Dev archive diagnostic hint: ' + category)

if __name__ == '__main__':
    main()
