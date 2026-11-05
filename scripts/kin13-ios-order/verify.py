#!/usr/bin/env python3
"""Fail closed on incomplete, changed, duplicate, skipped or unchanged tests."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

control = Path(__file__).resolve().parent
baseline = json.loads((control / 'baseline.json').read_text())
root = Path(os.environ['RUNNER_TEMP'])
identities = baseline['identities']
titles = baseline['start_title_hashes']
first, second = baseline['first_suites'], baseline['second_suites']
if (baseline.get('source_sha') != os.environ['EXPECTED_SOURCE'] or not identities or
    len(identities) != len(set(identities)) or len(titles) != len(set(titles)) or
    len(identities) != len(titles) or len(first) != len(set(first)) or
    len(second) != len(set(second)) or set(first) & set(second) or
    set(first) | set(second) != {x.split('/')[0] for x in identities}):
    raise SystemExit('Baseline source or partition is invalid')
all_ids, all_starts = [], []
for name in ('first', 'second'):
    batch = root / ('ios-order-' + name)
    result = batch / 'KinTests.xcresult'
    def report(kind):
        return json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', kind, '--path', str(result)], timeout=90))
    summary, tree = report('summary'), report('tests')
    expected = {x for x in baseline['identities'] if x.split('/')[0] in baseline[name + '_suites']}
    if (summary.get('result') != 'Passed' or summary.get('failedTests') != 0 or
        summary.get('skippedTests') != 0 or summary.get('expectedFailures') != 0 or
        summary.get('passedTests') != len(expected) or summary.get('totalTestCount') != len(expected)):
        raise SystemExit('Batch summary incomplete or failed')
    ids = []
    def visit(node):
        if node.get('nodeType') == 'Test Case': ids.append(node.get('nodeIdentifier'))
        for child in node.get('children', []): visit(child)
    for node in tree.get('testNodes', []): visit(node)
    if len(ids) != len(set(ids)) or set(ids) != expected:
        raise SystemExit('Batch identities differ from baseline selection')
    records = [json.loads(x) for x in (batch / 'KinTests-progress.jsonl').read_text().splitlines()]
    starts = [x['id'] for x in records if x.get('kind') == 'test_start_hash']
    exits = [x.get('code') for x in records if x.get('kind') == 'exit']
    if exits != [0] or len(starts) != len(expected) or len(starts) != len(set(starts)):
        raise SystemExit('Batch starts or exit incomplete')
    all_ids += ids; all_starts += starts
    print(name, 'passed identities:', len(ids))
if len(all_ids) != len(set(all_ids)) or set(all_ids) != set(baseline['identities']):
    raise SystemExit('Combined identities do not match baseline')
if len(all_starts) != len(set(all_starts)) or set(all_starts) != set(baseline['start_title_hashes']):
    raise SystemExit('Observed starts do not match baseline')
if all_starts == baseline['start_title_hashes']:
    raise SystemExit('Observed order did not change')
print('Verified', len(all_ids), 'identities, unchanged starts set, and changed observed order')
