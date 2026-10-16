#!/usr/bin/env python3
"""Schema-check synthetic evidence; raw logs/result bundles are never retained."""
import ast
import json
import math
import re
import shutil
import sys
import uuid
from pathlib import Path

STAGES = {'baseline teardown', 'baseline editor outcome', 'strict teardown',
          'strict editor outcome', 'observe entry', 'observe settled', 'parent action editor'}
PROGRESS_STAGES = {'started', 'launch requested', 'launched', 'child navigation requested',
                   'child navigation completed', 'edit requested', 'edit dispatched',
                   'completed', 'teardown requested', 'evidence write failed'}

def validate_observation(record):
    assert isinstance(record, dict)
    if record.get('stage') == 'parent action outcome':
        assert set(record) == {'stage', 'editorIdentity'}
        assert record['editorIdentity'] in {'parent', 'unnamed child', 'other'}
        return record
    assert set(record) == {'stage', 'parentID', 'childBarCount', 'globalEditCount', 'controls'}
    assert record['stage'] in STAGES
    assert isinstance(record['parentID'], str) and record['parentID'].startswith('edit-person-')
    uuid.UUID(record['parentID'][len('edit-person-'):])
    for key in ['childBarCount', 'globalEditCount']:
        assert type(record[key]) is int and 0 <= record[key] <= 16
    assert isinstance(record['controls'], list) and len(record['controls']) <= 16
    for control in record['controls']:
        assert set(control) == {'id', 'isParent', 'hittable', 'frame'}
        assert isinstance(control['id'], str) and control['id'].startswith('edit-person-')
        uuid.UUID(control['id'][len('edit-person-'):])
        assert type(control['isParent']) is bool and type(control['hittable']) is bool
        assert control['isParent'] == (control['id'] == record['parentID'])
        assert isinstance(control['frame'], str)
        frame = ast.literal_eval(control['frame'])
        assert isinstance(frame, tuple) and len(frame) == 4
        assert all(type(value) in {int, float} and math.isfinite(value) for value in frame)
    return record

def validate_progress(record):
    assert isinstance(record, dict) and set(record) == {'probe', 'stage'}
    assert record['probe'] in {'baseline', 'strict', 'observe'}
    assert record['stage'] in PROGRESS_STAGES
    return record

def safe_file(path, root):
    assert not path.is_symlink() and path.is_file()
    assert path.resolve().parent == root.resolve()
    assert path.stat().st_size <= 8 * 1024 * 1024
    data = path.read_bytes()
    if path.suffix == '.png':
        assert data.startswith(b'\x89PNG\r\n\x1a\n')
    else:
        assert path.suffix == '.txt'
        text = data.decode('utf-8')
        assert all(user == 'runner' for user in re.findall(r'/(?:Users|home)/([^/\s]+)', text))
        assert not re.search(r'github_pat_|gh[pousr]_[A-Za-z0-9_]{20,}|PRIVATE KEY|AKIA[A-Z0-9]{16}', text)
        assert not re.search(r'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b', text)
        assert all(email == 'kin-support@intriguingideas.com' for email in re.findall(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', text))
    return data

def prepare(raw_log, exported, output, live=None, phase=None):
    output.mkdir(parents=True, exist_ok=False)
    records, progress, attachments = [], [], []
    rejected = 0
    if raw_log.exists():
        for line in raw_log.read_text(errors='replace').splitlines():
            for marker, validator, destination in [('KIN_EDIT_DIAGNOSTIC ', validate_observation, records),
                                                    ('KIN_EDIT_PROGRESS ', validate_progress, progress)]:
                if marker in line:
                    try:
                        destination.append(validator(json.loads(line.split(marker, 1)[1])))
                    except (AssertionError, ValueError, TypeError, SyntaxError, KeyError):
                        rejected += 1
    manifest_file = exported / 'manifest.json'
    manifest = []
    if manifest_file.exists():
        try:
            assert manifest_file.is_file() and not manifest_file.is_symlink()
            manifest = json.loads(manifest_file.read_text())
            assert isinstance(manifest, list)
        except (AssertionError, ValueError, TypeError, OSError):
            rejected += 1
            manifest = []
    for test in manifest:
        try:
            assert isinstance(test, dict) and isinstance(test['attachments'], list)
            items = test['attachments']
        except (AssertionError, KeyError, TypeError):
            rejected += 1
            continue
        for item in items:
            try:
                label, name = item['suggestedHumanReadableName'], item['exportedFileName']
                assert isinstance(label, str) and isinstance(name, str)
                if not label.startswith('Synthetic Edit diagnostic '):
                    continue
                assert Path(name).name == name
                source = exported / name
                data = safe_file(source, exported)
                (output / name).write_bytes(data)
                attachments.append({'label': label, 'file': name, 'source': 'xcresult'})
            except (AssertionError, ValueError, TypeError, KeyError, OSError):
                rejected += 1
    # An atomic metadata sidecar is the commit marker for a complete live capture.
    if live is not None and live.exists():
        assert live.is_dir() and not live.is_symlink()
        for metadata in live.glob('*.json'):
            try:
                assert not metadata.is_symlink() and metadata.stat().st_size < 128 * 1024
                uuid.UUID(metadata.stem)
                item = json.loads(metadata.read_text())
                assert set(item) == {'observation', 'image', 'hierarchy', 'label'}
                observation = validate_observation(item['observation'])
                if phase and not (observation['stage'].startswith(phase) or phase == 'observe' and observation['stage'].startswith('parent action')):
                    continue
                assert item['label'] == 'Synthetic Edit diagnostic ' + observation['stage']
                assert item['image'] == metadata.stem + '.png' and item['hierarchy'] == metadata.stem + '.txt'
                images = [(live / item[key], item[key]) for key in ['image', 'hierarchy']]
                validated = [(name, safe_file(source, live)) for source, name in images]
                for name, data in validated:
                    (output / ('live-' + name)).write_bytes(data)
                    attachments.append({'label': item['label'], 'file': 'live-' + name, 'source': 'atomic-sidecar'})
                if observation not in records:
                    records.append(observation)
            except (AssertionError, ValueError, TypeError, SyntaxError, KeyError, OSError):
                rejected += 1
    (output / 'control-observations.json').write_text(json.dumps(records, indent=2) + '\n')
    (output / 'progress.json').write_text(json.dumps(progress, indent=2) + '\n')
    (output / 'attachments.json').write_text(json.dumps(attachments, indent=2) + '\n')
    summary = {'observations': len(records), 'progressEvents': len(progress), 'attachments': len(attachments), 'rejectedItems': rejected}
    (output / 'filter-status.json').write_text(json.dumps(summary, indent=2) + '\n')
    print('KIN_EDIT_FILTER ' + json.dumps(summary), flush=True)
    return summary

if __name__ == '__main__':
    prepare(*map(Path, sys.argv[1:4]))
