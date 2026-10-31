#!/usr/bin/env python3
"""Partition current XCTest UI methods without dropping any test target."""
import json
import os
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
GROUPS = ('unit', 'ui-0', 'ui-1', 'ui-2', 'ui-3')
TIMINGS = ROOT / 'scripts/ci-ui-timings.json'

def discover(root=ROOT):
    ids = []
    for path in sorted((root / 'KinUITests').glob('*.swift')):
        text = path.read_text()
        classes = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', text)
        methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', text)
        # This shared UI helper contains no XCTestCase or test methods.
        # If that changes, require explicit discovery instead of dropping tests.
        if path.name == 'EditorTestSupport.swift' and not classes and not methods:
            continue
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

def allocate(ids, timings, fallback, group_count=4):
    """Deterministic longest-first balancing; unmeasured tests remain blocking."""
    if type(fallback) not in (int, float) or not 0 < fallback <= 3600:
        raise ValueError('Invalid timing fallback')
    if not isinstance(timings, dict) or any(
        not isinstance(k, str) or type(v) not in (int, float) or not 0 < v <= 3600
        for k, v in timings.items()
    ):
        raise ValueError('Invalid UI timings')
    if not ids or len(ids) != len(set(ids)):
        raise ValueError('Missing or duplicate UI test IDs')
    if type(group_count) is not int or group_count not in (4, 8):
        raise ValueError('UI shard count must be 4 or 8')
    bins = [[] for _ in range(group_count)]
    loads = [0] * len(bins)
    for ident in sorted(ids, key=lambda item: (-timings.get(item, fallback), item)):
        index = min(range(len(bins)), key=lambda i: (loads[i], i))
        bins[index].append(ident)
        loads[index] += timings.get(ident, fallback)
    return [sorted(group) for group in bins]


def selections(group, root=ROOT, group_count=None):
    if group_count is None:
        raw_count = os.environ.get('KIN_UI_SHARD_COUNT', '4')
        if raw_count not in ('4', '8'):
            raise ValueError('UI shard count must be 4 or 8')
        group_count = int(raw_count)
    if type(group_count) is not int or group_count not in (4, 8):
        raise ValueError('UI shard count must be 4 or 8')
    ids = discover(root)
    if group == 'unit':
        return ['KinTests']
    if group not in tuple(f'ui-{i}' for i in range(group_count)):
        raise ValueError('Unknown shard')
    baseline = json.loads((root / 'scripts/ci-ui-timings.json').read_text())
    return allocate(ids, baseline['seconds'], baseline['fallback_seconds'], group_count)[int(group[-1])]


def verify_test_ids(report, selected):
    """Verify finalized result-bundle test identities, not just the count."""
    found = []
    def visit(node):
        if not isinstance(node, dict):
            raise ValueError('Malformed XCTest test tree')
        if node.get('nodeType') == 'Test Case':
            ident = node.get('nodeIdentifier')
            if not isinstance(ident, str) or not re.fullmatch(r'\w+/test\w+\(\)', ident):
                raise ValueError('Unsupported XCTest test identifier')
            found.append('KinUITests/' + ident[:-2])
        children = node.get('children', [])
        if not isinstance(children, list):
            raise ValueError('Malformed XCTest child list')
        for child in children:
            visit(child)
    nodes = report.get('testNodes')
    if not isinstance(nodes, list):
        raise ValueError('Missing XCTest test tree')
    for node in nodes:
        visit(node)
    if len(found) != len(set(found)) or sorted(found) != sorted(selected):
        raise ValueError('Finalized UI test identities do not match selected shard')

if __name__ == '__main__':
    group = sys.argv[1]
    selected = selections(group)
    if len(sys.argv) == 2:
        print(' '.join('-only-testing:' + item for item in selected))
    else:
        summary = json.loads(Path(sys.argv[2]).read_text())
        if group != 'unit' and summary.get('totalTestCount') != len(selected):
            sys.exit('Finalized UI count does not match the exact selected test manifest')
        if group != 'unit':
            if len(sys.argv) != 4:
                sys.exit('Finalized UI test identity tree is required')
            verify_test_ids(json.loads(Path(sys.argv[3]).read_text()), selected)
        print(f'{group}: expected UI identities verified' if group != 'unit' else 'unit: complete KinTests target selected')
