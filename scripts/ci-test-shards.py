#!/usr/bin/env python3
"""Partition current XCTest UI methods without dropping any test target."""
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
GROUPS = ('unit', 'ui-0', 'ui-1', 'ui-2')

def discover(root=ROOT):
    ids = []
    for path in sorted((root / 'KinUITests').glob('*.swift')):
        text = path.read_text()
        classes = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', text)
        methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', text)
        if len(classes) != 1 or not methods:
            raise ValueError(f'Unrecognized UI test structure: {path.name}')
        ids.extend(f'KinUITests/{classes[0]}/{method}' for method in methods)
    if not ids or len(ids) != len(set(ids)):
        raise ValueError('Missing or duplicate UI test IDs')
    scheme = ET.parse(root / 'Kin.xcodeproj/xcshareddata/xcschemes/Kin.xcscheme')
    targets = [x.find('BuildableReference').get('BlueprintName') for x in scheme.findall('.//TestableReference') if x.get('skipped') != 'YES']
    if sorted(targets) != ['KinTests', 'KinUITests']:
        raise ValueError('Test targets changed; update shard coverage explicitly')
    return sorted(ids)

def selections(group, root=ROOT):
    ids = discover(root)
    if group == 'unit':
        return ['KinTests']
    if group not in GROUPS:
        raise ValueError('Unknown shard')
    return ids[int(group[-1])::3]

if __name__ == '__main__':
    group = sys.argv[1]
    selected = selections(group)
    if len(sys.argv) == 2:
        print(' '.join('-only-testing:' + item for item in selected))
    else:
        summary = json.loads(Path(sys.argv[2]).read_text())
        if group != 'unit' and summary.get('totalTestCount') != len(selected):
            sys.exit('Finalized UI count does not match the exact selected test manifest')
        print(f'{group}: expected UI count verified' if group != 'unit' else 'unit: complete KinTests target selected')
