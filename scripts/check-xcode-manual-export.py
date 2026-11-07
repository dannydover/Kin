#!/usr/bin/env python3
"""Read-only help probe; never archives, signs, uploads or reads credentials."""
import importlib.util
from pathlib import Path
import re
import sys

_spec = importlib.util.spec_from_file_location('candidate', Path(__file__).with_name('verify-signed-candidate.py'))
_candidate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_candidate)


def check(text):
    if not isinstance(text, str) or 'Available keys for -exportOptionsPlist:' not in text:
        raise ValueError('Export help unavailable')
    if '-exportArchive' not in text or '-exportOptionsPlist' not in text:
        raise ValueError('Archive export command unavailable')
    section = text.split('Available keys for -exportOptionsPlist:', 1)[1]
    headers = list(re.finditer(r'(?m)^\s*([A-Za-z][A-Za-z0-9]*)\s*:\s*(String|Dictionary|Bool)\s*$', section))
    blocks = {}
    for i, match in enumerate(headers):
        end = headers[i + 1].start() if i + 1 < len(headers) else len(section)
        if match.group(1) in blocks:
            raise ValueError('Duplicate option in help')
        blocks[match.group(1)] = (match.group(2), section[match.end():end].lower())
    for key, kind in [('destination', 'String'), ('method', 'String'), ('signingStyle', 'String'),
                      ('signingCertificate', 'String'), ('provisioningProfiles', 'Dictionary'), ('teamID', 'String')]:
        if key not in blocks or blocks[key][0] != kind:
            raise ValueError('Required export option unavailable')
    if not re.search(r'\bexport\b', blocks['destination'][1]):
        raise ValueError('Local export option unavailable')
    if 'app-store-connect' not in blocks['method'][1] or 'manual' not in blocks['signingStyle'][1]:
        raise ValueError('Manual App Store export option unavailable')
    return True


def main():
    data = _candidate._bounded_output(['/usr/bin/xcodebuild', '-help'], 'Xcode help', merge_stderr=True)
    check(data.decode('utf-8'))
    print('Manual archive export options appear in Xcode help; no signing or export was performed.')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Xcode manual-export help probe failed.', file=sys.stderr)
        sys.exit(1)
