#!/usr/bin/env python3
"""Validate an unsigned Release app without installing or distributing it."""
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def main():
    app = Path(sys.argv[1])
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    failures = []
    for key, expected in [('MinimumOSVersion', '26.0'), ('UIDeviceFamily', [1]),
                          ('CFBundleIdentifier', 'com.intriguingideas.Kin')]:
        if info.get(key) != expected:
            failures.append(f'unexpected {key}')
    privacy = plistlib.loads((app / 'PrivacyInfo.xcprivacy').read_bytes())
    if privacy.get('NSPrivacyTracking') is not False:
        failures.append('tracking declaration changed')
    for key in ['NSPrivacyTrackingDomains', 'NSPrivacyCollectedDataTypes',
                'NSPrivacyAccessedAPITypes']:
        if privacy.get(key) != []:
            failures.append(f'unexpected {key}')
    executable = (app / info['CFBundleExecutable']).read_bytes()
    patterns = {
        'personal build path': rb'/(?:Users|home)/[^/\s]+|/(?:Volumes)/|/var/(?:folders)/',
        'debug preview code': rb'--kin-preview|DemoFamilies|DevelopmentPreview',
    }
    for label, pattern in patterns.items():
        if re.search(pattern, executable):
            failures.append(label)
    if (app / '_CodeSignature').exists() or (app / 'embedded.mobileprovision').exists():
        failures.append('signing or provisioning material present')
    signing = subprocess.run(['codesign', '--display', '--verbose=4', str(app)], capture_output=True)
    unsigned = signing.returncode != 0 and b'code object is not signed at all' in signing.stderr
    # The simulator linker can embed an ad-hoc signature even with code signing
    # disabled. It uses no developer identity, certificate, team or provisioning.
    simulator_linker_signature = (
        info.get('DTPlatformName') == 'iphonesimulator'
        and signing.returncode == 0
        and b'Signature=adhoc' in signing.stderr
        and b'linker-signed' in signing.stderr
        and b'TeamIdentifier=not set' in signing.stderr
        and b'Authority=' not in signing.stderr
    )
    if not (unsigned or simulator_linker_signature):
        failures.append('unexpected signature or developer signing identity')
    if failures:
        for failure in failures:
            print(f'Release validation failed: {failure}')
        return 1
    print('Release validation passed: no developer signing, iPhone-only app, iOS 26 minimum, '
          'privacy manifest present, no personal build paths or debug previews.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
