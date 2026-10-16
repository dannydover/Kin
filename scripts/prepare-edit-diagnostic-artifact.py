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
                   'completed', 'teardown requested', 'evidence write failed',
                   'entry snapshot saved', 'control query requested'}

BUILD_STAGES = {'dependency-graph', 'build-description', 'asset-compile', 'swift-driver',
                'swift-compile', 'swift-module', 'clang-compile', 'link', 'copy',
                'metadata', 'validate', 'build-succeeded', 'build-failed'}

def validate_build(record):
    assert isinstance(record, dict) and set(record) == {'stage', 'count', 'total', 'elapsedSeconds'}
    assert record['stage'] in BUILD_STAGES
    assert all(type(record[key]) is int and 0 <= record[key] <= 1000000 for key in ['count', 'total', 'elapsedSeconds'])
    assert 1 <= record['count'] <= record['total']
    return record

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

def sanitize_issue(item, phase):
    assert isinstance(item, dict) and set(item) == {'probe', 'source', 'line', 'message', 'detail', 'operation', 'operationLine'}
    assert item['probe'] in {'baseline', 'strict', 'observe'}
    if phase and item['probe'] != phase:
        return None
    assert type(item['line']) is int and 0 <= item['line'] < 100000
    assert isinstance(item['source'], str) and len(item['source']) < 256
    assert item['operation'] in {'setup', 'baseline broad Edit tap', 'observer entry controls',
                                  'observer settled controls', 'parent action tap', 'entry screenshot',
                                  'entry hierarchy', 'injected ambiguous query'}
    assert type(item['operationLine']) is int and 0 <= item['operationLine'] < 100000
    redactions = 0
    def sanitize(text):
        nonlocal redactions
        assert isinstance(text, str) and len(text) <= 128 * 1024
        # Exact XCTest wording is retained except host paths, credentials,
        # email addresses and physical-device identifiers. Synthetic fixture only.
        for pattern in [r'file://[^\n\'\"]+',
                        r'/(?:Users|home|Volumes|private|var|tmp)/[^\n\'\"]+',
                        r'github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]+|AKIA[A-Z0-9]{16}|sk-[A-Za-z0-9]{20,}',
                        r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
                        r'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b']:
            text, count = re.subn(pattern, '<redacted>', text)
            redactions += count
        assert 'PRIVATE KEY' not in text
        assert all(ord(c) >= 32 or c in '\n\t' for c in text)
        return text
    message, detail = sanitize(item['message']), sanitize(item['detail'])
    combined = message + '\n' + detail
    category = ('multiple-matches' if 'Multiple matching elements' in combined else
                'injected-query-failure' if 'Synthetic injected query failure' in combined else
                'snapshot-failure' if 'snapshot' in combined.lower() else 'other-xctest-failure')
    return {'probe': item['probe'], 'source': item['source'] if item['source'] == 'EditIdentityDiagnosticTests.swift' else 'unknown',
            'line': item['line'], 'operation': item['operation'], 'operationLine': item['operationLine'], 'category': category, 'message': message, 'detail': detail, 'redactions': redactions}

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
    records, progress, attachments, issues, captures, build = [], [], [], [], [], []
    rejected = 0
    if raw_log.exists():
        for line in raw_log.read_text(errors='replace').splitlines():
            for marker, validator, destination in [('KIN_EDIT_DIAGNOSTIC ', validate_observation, records),
                                                    ('KIN_EDIT_PROGRESS ', validate_progress, progress),
                                                    ('KIN_EDIT_BUILD ', validate_build, build)]:
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
                stem = metadata.name.split('.')[0]
                uuid.UUID(stem)
                item = json.loads(metadata.read_text())
                if metadata.name == stem + '.issue.json':
                    issue = sanitize_issue(item, phase)
                    if issue is not None:
                        issues.append(issue)
                    continue
                if metadata.name == stem + '.capture.json':
                    assert set(item) == {'captureStage', 'parentID', 'image', 'hierarchy', 'label'}
                    assert item['captureStage'] == 'observe entry'
                    assert isinstance(item['parentID'], str) and item['parentID'].startswith('edit-person-')
                    uuid.UUID(item['parentID'][len('edit-person-'):])
                    if phase and phase != 'observe':
                        continue
                    assert item['label'] == 'Synthetic Edit diagnostic observe entry snapshot'
                    assert item['image'] == stem + '.png'
                    assert item['hierarchy'] in {None, stem + '.txt'}
                    names = [item['image']] + ([item['hierarchy']] if item['hierarchy'] else [])
                    validated = [(name, safe_file(live / name, live)) for name in names]
                    for name, data in validated:
                        (output / ('live-' + name)).write_bytes(data)
                        attachments.append({'label': item['label'], 'file': 'live-' + name, 'source': 'pre-query-capture'})
                    captures.append({'stage': item['captureStage'], 'parentID': item['parentID'], 'image': 'live-' + item['image'],
                                     'hierarchy': 'live-' + item['hierarchy'] if item['hierarchy'] else None})
                    continue
                assert metadata.name == stem + '.json'
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
    (output / 'build-progress.json').write_text(json.dumps(build, indent=2) + '\n')
    (output / 'xctest-issues.json').write_text(json.dumps(issues, indent=2) + '\n')
    (output / 'entry-captures.json').write_text(json.dumps(captures, indent=2) + '\n')
    (output / 'control-observations.json').write_text(json.dumps(records, indent=2) + '\n')
    (output / 'progress.json').write_text(json.dumps(progress, indent=2) + '\n')
    (output / 'attachments.json').write_text(json.dumps(attachments, indent=2) + '\n')
    summary = {'observations': len(records), 'progressEvents': len(progress), 'attachments': len(attachments), 'rejectedItems': rejected, 'xctestIssues': len(issues), 'entryCaptures': len(captures), 'buildProgressEvents': len(build)}
    (output / 'filter-status.json').write_text(json.dumps(summary, indent=2) + '\n')
    print('KIN_EDIT_FILTER ' + json.dumps(summary), flush=True)
    return summary

if __name__ == '__main__':
    prepare(*map(Path, sys.argv[1:4]))
