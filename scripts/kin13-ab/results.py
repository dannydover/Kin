#!/usr/bin/env python3
"""Fail-closed comparison metadata; never publish raw app or host values."""
import hashlib
import importlib.util
import json
import os
import sys
from pathlib import Path

GROUPS = ('unit', 'ui-0', 'ui-1', 'ui-2', 'ui-3')
SCOPES = {
    'KinUITests/NativeContactsTests/testNativeFullBirthdayAndPhotoImportForAdult': 'native-adult',
    'KinUITests/NativeContactsTests/testNativeFullBirthdayAndPhotoImportForMinor': 'native-minor',
    'KinUITests/ExistingContactPreservationUITests/testExistingBirthInformationSurvivesMissingAndYearlessContactsReview': 'preservation',
    'KinUITests/KinUITests/testContactMissingBirthdayPromptCancellationAndEstimatedImport': 'missing-birthday',
}


def test_ids(tree):
    found = []
    def visit(node):
        if not isinstance(node, dict): raise ValueError('Malformed tree')
        if node.get('nodeType') == 'Test Case':
            ident = node.get('nodeIdentifier')
            if not isinstance(ident, str) or not ident: raise ValueError('Missing identity')
            found.append(ident)
        children = node.get('children', [])
        if not isinstance(children, list): raise ValueError('Malformed children')
        for child in children: visit(child)
    nodes = tree.get('testNodes')
    if not isinstance(nodes, list): raise ValueError('Missing test tree')
    for node in nodes: visit(node)
    return found


def validate(summary, tree, progress, cleanup, group, selected, verify_ui):
    if group not in GROUPS: raise ValueError('Unknown group')
    if not isinstance(summary, dict) or summary.get('result') not in ('Passed', 'Failed'): raise ValueError('Unfinalized summary')
    keys = ('totalTestCount','passedTests','failedTests','skippedTests','expectedFailures')
    if any(type(summary.get(k)) is not int for k in keys): raise ValueError('Invalid counts')
    total, passed, failed, skipped, expected = (summary[k] for k in keys)
    if total <= 0 or passed + failed != total or skipped or expected: raise ValueError('Incomplete or skipped tests')
    if (summary['result'] == 'Passed') != (failed == 0): raise ValueError('Inconsistent result')
    ids = test_ids(tree)
    if len(ids) != total: raise ValueError('Identity count mismatch')
    if group == 'unit':
        if selected != ['KinTests'] or total != 146: raise ValueError('Unit selection changed')
    else:
        if total != len(selected): raise ValueError('UI selection count changed')
        verify_ui(tree, selected)
    if cleanup != {'shutdown':'success','delete':'success','inventory':'absent'}: raise ValueError('Simulator cleanup not verified')
    if not isinstance(progress, list): raise ValueError('Missing progress')
    exits = [v for v in progress if v.get('kind') == 'exit']
    if len(exits) != 1 or exits[0].get('interrupted') is not False or type(exits[0].get('code')) is not int:
        raise ValueError('Missing test exit')
    code = exits[0]['code']
    if (code == 0) != (failed == 0): raise ValueError('Infrastructure or test-exit mismatch')
    if group != 'unit' and {v.get('state') for v in progress if v.get('kind') == 'authorization'} != {'authorized'}:
        raise ValueError('Contacts runner authorization not verified')
    expected_scopes = {SCOPES[i] for i in selected if i in SCOPES}
    records = [v for v in progress if v.get('kind') == 'contact_cleanup_accounting']
    if len(records) != len(expected_scopes) or {v.get('scope') for v in records} != expected_scopes:
        raise ValueError('Missing or duplicate contact scope')
    if any(v.get('status') != 'verified' for v in records): raise ValueError('Contacts cleanup not verified')
    digest = hashlib.sha256(json.dumps(sorted(ids), separators=(',', ':')).encode()).hexdigest()
    return {'comparable':True, 'group':group, 'total':total, 'passed':passed, 'failed':failed,
            'skipped':skipped, 'identity_sha256':digest}


def validate_outcome(result, outcome):
    if outcome not in ('success','failure') or (outcome == 'success') != (result['failed'] == 0):
        raise ValueError('Observer outcome does not match test results')


def main():
    group = os.environ['KIN_AB_GROUP']
    root = Path(os.environ['RUNNER_TEMP'])
    target = root / 'KinAB-status.json'
    result = {'comparable':False, 'group':group}
    try:
        if os.environ.get('KIN_AB_EVIDENCE_OK') != 'true': raise ValueError('Result evidence not retained')
        spec=importlib.util.spec_from_file_location('shards', Path.cwd()/'scripts/ci-test-shards.py')
        shards=importlib.util.module_from_spec(spec);spec.loader.exec_module(shards)
        read=lambda name: json.loads((root/name).read_text())
        progress=[json.loads(line) for line in (root/'KinTests-progress.jsonl').read_text().splitlines()]
        result=validate(read('KinTests-summary.json'),read('KinTests-test-tree.json'),progress,
                        read('KinTests-cleanup.json'),group,shards.selections(group),shards.verify_test_ids)
        validate_outcome(result,os.environ.get('KIN_AB_TEST_OUTCOME'))
        result.update({'image':os.environ['KIN_AB_IMAGE'], 'runtime':'24A434',
                       'product_sha256':os.environ['KIN_AB_PRODUCT_SHA'], 'manifest_sha256':os.environ['KIN_AB_MANIFEST_SHA'],
                       'arm':os.environ['KIN_AB_ARM'], 'toolchain':os.environ['KIN_AB_TOOLCHAIN']})
    except (OSError,ValueError,KeyError,TypeError,AttributeError,ImportError) as e:
        safe = {'Result evidence not retained','Unknown group','Unfinalized summary','Invalid counts','Incomplete or skipped tests',
                'Inconsistent result','Identity count mismatch','Unit selection changed',
                'UI selection count changed','Simulator cleanup not verified','Missing progress',
                'Missing test exit','Infrastructure or test-exit mismatch','Missing or duplicate contact scope',
                'Contacts cleanup not verified','Contacts runner authorization not verified',
                'Observer outcome does not match test results','Missing test tree','Malformed tree','Malformed children',
                'Missing identity','Missing XCTest test tree','Malformed XCTest test tree',
                'Unsupported XCTest test identifier'}
        result={'comparable':False, 'group':group, 'error_type':type(e).__name__,
                'reason':str(e) if str(e) in safe else 'unavailable or invalid data'}
    target.write_text(json.dumps(result,sort_keys=True)+'\n')
    print('KIN_AB_STATUS',group,'comparable='+str(result['comparable']).lower(), 'reason='+result.get('reason','none'))
    return 0 if result['comparable'] else 1

if __name__ == '__main__':sys.exit(main())
