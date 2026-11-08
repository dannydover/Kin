#!/usr/bin/env python3
"""Create fixed-field, non-secret upload outcome evidence for a disabled job."""
import json
import os
from pathlib import Path
import re
import sys


def summarize(root, run_id, attempt, sha, version='', build=''):
    if not re.fullmatch(r'[0-9]+', run_id) or not re.fullmatch(r'[0-9]+', attempt):
        raise ValueError('invalid run identity')
    if not re.fullmatch(r'[0-9a-f]{40}', sha): raise ValueError('invalid source identity')
    root = Path(root)
    marker = root / ('kin-upload-evidence-' + run_id + '-' + attempt) / 'upload-outcome'
    outcome = 'unknown'
    try:
        if marker.is_symlink() or not marker.is_file() or marker.stat().st_size > 128:
            raise ValueError('unavailable marker')
        value = marker.read_text(encoding='ascii').strip()
        if value in ('uncertain', 'tool-success-processing-unverified',
                     'processing-valid-metadata-match', 'apple-processing-failed'):
            outcome = value
    except (OSError, UnicodeError, ValueError):
        pass
    version = version if re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', version) else 'unknown'
    build = build if re.fullmatch(r'[1-9][0-9]*', build) else 'unknown'
    return {'schema': 1, 'source_sha': sha, 'run_id': run_id, 'attempt': attempt,
            'version': version, 'build': build,
            'bundle_id': 'com.intriguingideas.Kin.dev', 'upload': outcome,
            'apple_processing': ('valid-metadata-match' if outcome == 'processing-valid-metadata-match'
                                 else 'failed' if outcome == 'apple-processing-failed' else 'unverified'),
            'byte_identity': 'unverified', 'automatic_retry': False}


if __name__ == '__main__':
    data = summarize(os.environ['RUNNER_TEMP'], os.environ['GITHUB_RUN_ID'],
                     os.environ['GITHUB_RUN_ATTEMPT'], os.environ['GITHUB_SHA'],
                     os.environ.get('VERSION', ''), os.environ.get('BUILD', ''))
    out = Path(os.environ['RUNNER_TEMP']) / 'kin-upload-outcome.json'
    with out.open('x', encoding='utf-8') as f:
        json.dump(data, f, sort_keys=True); f.write('\n')
    print('Fixed-field upload outcome recorded; Apple processing is unverified.')
