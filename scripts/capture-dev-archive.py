#!/usr/bin/env python3
"""Drain all Xcode output, retaining a bounded private prefix and fixed hints."""
import os
import re
import stat
import sys

LIMIT = 8 * 1024 * 1024
PATTERNS = {
    'file-size-limit': (r'file too large', r'file size limit exceeded'),
    'signing-profile': (r'no profiles for .+ were found', r'requires a provisioning profile', r'no signing certificate .+ found'),
    'sdk-toolchain': (r'sdk .+ cannot be located', r'unable to find utility', r'sdk .+ not found'),
    'missing-input': (r'build input file cannot be found', r'no such file or directory'),
    'duplicate-output': (r'multiple commands produce',),
    'swift-compile': (r'swiftcompile.+failed', r'swift compiler error', r'swift compile error'),
    'linker': (r'linker command failed', r'undefined symbols for architecture'),
    'xcode-internal': (r'build service could not create build operation', r'unable to initiate pif transfer session'),
}

def capture(path):
    remaining = LIMIT
    truncated = False
    with open(path, 'xb') as output:
        while True:
            chunk = sys.stdin.buffer.read(65536)
            if not chunk:
                break
            if len(chunk) > remaining:
                truncated = True
            if remaining:
                part = chunk[:remaining]
                output.write(part)
                remaining -= len(part)
        if truncated:
            output.write(b'\n')

def classify(path):
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0))
        with os.fdopen(fd, 'rb') as source:
            if not stat.S_ISREG(os.fstat(source.fileno()).st_mode): return 'unavailable'
            data = source.read(LIMIT + 1)
        if len(data) > LIMIT: return 'unavailable'
        text = data.decode('utf-8', 'replace')
        matches = [label for label, patterns in PATTERNS.items() if any(re.search(pattern, text, re.IGNORECASE) for pattern in patterns)]
        return matches[0] if len(matches) == 1 else 'multiple' if matches else 'unclassified'
    except (OSError, ValueError):
        return 'unavailable'

def main():
    if len(sys.argv) != 3: return 1
    if sys.argv[1] == 'capture':
        try: capture(sys.argv[2]); return 0
        except OSError: return 1
    if sys.argv[1] == 'classify':
        print('KIN_DEV_ARCHIVE_HINT ' + classify(sys.argv[2])); return 0
    return 1

if __name__ == '__main__':
    raise SystemExit(main())
