#!/usr/bin/env python3
"""Synthetic simulator: compare simctl launch PID to scoped launchd entry."""
import os
import re
import subprocess
import sys
import time

BUNDLE = 'com.intriguingideas.Kin'
LABEL = re.compile(r'^(?:com\.apple\.)?UIKitApplication:com\.intriguingideas\.Kin(?:\[[^\]\r\n]+\])+$|^application<com\.intriguingideas\.Kin>$')


def candidates(output):
    found = []
    for line in output.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and LABEL.fullmatch(parts[2]):
            found.append(int(parts[0]) if parts[0].isdigit() and int(parts[0]) > 0 else None)
    return found


def run(*args, timeout=15):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True, timeout=timeout, check=True).stdout


def main():
    device = os.environ['KIN_CI_SIMULATOR']
    try:
        output = run('xcrun', 'simctl', 'launch', device, BUNDLE, '--kin-preview', 'import-preservation')
        match = re.fullmatch(re.escape(BUNDLE) + r':\s*(\d+)\s*', output)
        if not match or int(match.group(1)) <= 0:
            return 'unknown'
        launched = int(match.group(1))
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            found = candidates(run('xcrun', 'simctl', 'spawn', device, 'launchctl', 'list', timeout=min(5, remaining)))
            if len(found) == 1 and found[0] == launched:
                return 'verified'
            time.sleep(min(2, max(0, deadline - time.monotonic())))
    except (subprocess.SubprocessError, OSError, ValueError):
        pass
    return 'unknown'


if __name__ == '__main__':
    result = main()
    print('KIN_LIFECYCLE_PREFLIGHT identity=' + result)
    sys.exit(0 if result == 'verified' else 1)
