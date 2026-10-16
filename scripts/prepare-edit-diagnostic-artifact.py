#!/usr/bin/env python3
"""Retain only explicitly named synthetic Edit evidence, never raw runner logs."""
import ast
import json
import math
import re
import shutil
import sys
import uuid
from pathlib import Path

raw_log, exported, output = map(Path, sys.argv[1:4])
output.mkdir(parents=True, exist_ok=False)
records = []
for line in raw_log.read_text(errors='replace').splitlines():
    marker = 'KIN_EDIT_DIAGNOSTIC '
    if marker not in line:
        continue
    record = json.loads(line.split(marker, 1)[1])
    stages = {'baseline teardown', 'baseline editor outcome', 'strict teardown',
              'strict editor outcome', 'observe entry', 'observe settled', 'parent action editor'}
    if record.get('stage') == 'parent action outcome':
        assert set(record) == {'stage', 'editorIdentity'}
        assert record['editorIdentity'] in {'parent', 'unnamed child', 'other'}
    else:
        assert set(record) == {'stage', 'parentID', 'childBarCount', 'globalEditCount', 'controls'}
        assert record['stage'] in stages
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
    records.append(record)
(output / 'control-observations.json').write_text(json.dumps(records, indent=2) + '\n')
manifest_file = exported / 'manifest.json'
manifest = json.loads(manifest_file.read_text()) if manifest_file.exists() else []
retained = []
for test in manifest:
    for item in test['attachments']:
        label = item['suggestedHumanReadableName']
        if not label.startswith('Synthetic Edit diagnostic '):
            continue
        name = item['exportedFileName']
        assert Path(name).name == name
        source = exported / name
        assert source.suffix in {'.png', '.txt'}
        data = source.read_bytes()
        if source.suffix == '.png':
            assert data.startswith(b'\x89PNG\r\n\x1a\n')
        else:
            text = data.decode('utf-8')
            users = re.findall(r'/(?:Users|home)/([^/\s]+)', text)
            assert all(user == 'runner' for user in users), 'unexpected host path'
            assert not re.search(r'github_pat_|gh[pousr]_[A-Za-z0-9_]{20,}|PRIVATE KEY|AKIA[A-Z0-9]{16}', text)
            assert not re.search(r'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b', text), 'physical device identifier'
            emails = re.findall(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', text)
            assert all(email == 'kin-support@intriguingideas.com' for email in emails)
        shutil.copyfile(source, output / name)
        retained.append({'test': test.get('testIdentifier'), 'label': label, 'file': name})
(output / 'attachments.json').write_text(json.dumps(retained, indent=2) + '\n')
# No complete xcresult, raw build log, environment dump, or device inventory is uploaded.
print(f'Reviewed synthetic evidence: {len(records)} observations, {len(retained)} attachments.')
