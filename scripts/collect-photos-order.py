#!/usr/bin/env python3
"""Retain only fixed-field synthetic order, readiness and failure evidence."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys

spec=importlib.util.spec_from_file_location('diag','scripts/ci-photos-order.py')
diag=importlib.util.module_from_spec(spec);spec.loader.exec_module(diag)


def category(text):
    if 'execution time allowance' in text: return 'test_timeout'
    if 'Timed out while evaluating UI query' in text: return 'ui_query_timeout'
    if 'Timed out while synthesizing event' in text: return 'event_synthesis_timeout'
    if 'XCTAssert' in text: return 'assertion_failure'
    return 'other'


def main():
    mode=sys.argv[1];expected=diag.selected(mode)
    root=Path(os.environ['RUNNER_TEMP']);out=root/'KinPhotosOrder';out.mkdir(exist_ok=True)
    manifest={'mode':mode,'source_sha':os.environ.get('GITHUB_SHA','unknown'),
              'expected':expected,'status':'partial','order_verified':False,
              'raw_bundle_retained':False,'reason':'may contain unrelated runner diagnostics'}
    try:
        progress=root/'KinTests-progress.jsonl'
        records=[json.loads(line) for line in progress.read_text().splitlines()]
        starts=[r['id'] for r in records if r.get('kind')=='test' and r.get('event')=='started']
        manifest['order_verified']=starts == expected
        manifest['observed_starts']=starts
        # ci-photos-order.py writes only fixed allowlisted records.
        shutil.copyfile(progress,out/'progress.jsonl')
        summary=json.loads((root/'KinTests-summary.json').read_text())
        tree=json.loads((root/'KinTests-test-tree.json').read_text())
        diag.shards.verify_test_ids(tree,expected)
        keys=('totalTestCount','passedTests','failedTests','skippedTests','expectedFailures')
        if any(type(summary.get(k)) is not int for k in keys):
            raise ValueError('Invalid result counts')
        counts={k:summary[k] for k in keys}
        if (counts['totalTestCount'] != len(expected)
            or sum(counts[k] for k in ('passedTests','failedTests','skippedTests')) != len(expected)
            or summary.get('result') not in ('Passed','Failed')):
            raise ValueError('Incomplete result')
        failures=[]
        for f in summary.get('testFailures',[]):
            identifier=f.get('testIdentifierString','')
            ident='KinUITests/'+identifier.removesuffix('()')
            if ident not in expected: raise ValueError('Unexpected failure identity')
            message=f.get('failureText','')
            if not isinstance(message,str): raise ValueError('Invalid failure')
            failures.append({'id':ident,'category':category(message),
                             'sha256':hashlib.sha256(message.encode()).hexdigest()})
        if len({f['id'] for f in failures}) != counts['failedTests']:
            raise ValueError('Missing failure records')
        manifest.update(status='finalized',result=summary['result'],counts=counts,failures=failures)
    except (OSError,ValueError,KeyError,TypeError):
        pass
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return 0 if manifest['status']=='finalized' and manifest['order_verified'] else 1


if __name__=='__main__':
    sys.exit(main())
