#!/usr/bin/env python3
"""Validate fixed image/toolchain/runtime and aggregate comparable arm results."""
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

SOURCE = '022e405fe6d301df9b2e4c936f91f32065ba996d'
GROUPS = {'unit','ui-0','ui-1','ui-2','ui-3'}
BUILDS = {'27.0':'27A266a','27.1':'27A9275'}


def image_id(env):
    parts = [env.get('ImageOS', ''), env.get('ImageVersion', '')]
    if not all(re.fullmatch(r'[A-Za-z0-9_.-]+', p) for p in parts): raise ValueError('Missing image metadata')
    return ':'.join(parts)


def validate_env(image, expected, tool, version, arch, runtimes):
    if image != expected: raise ValueError('Runner image mismatch')
    if tool not in BUILDS or version != f'Xcode {tool}\nBuild version {BUILDS[tool]}': raise ValueError('Toolchain mismatch')
    if arch != 'arm64': raise ValueError('Architecture mismatch')
    entries = runtimes.get('runtimes')
    if not isinstance(entries, list): raise ValueError('Runtime metadata unavailable')
    matches = [x for x in entries if x.get('identifier') == 'com.apple.CoreSimulator.SimRuntime.iOS-27-0']
    if len(matches) != 1 or matches[0].get('buildversion') != '24A434' or matches[0].get('isAvailable') is not True:
        raise ValueError('Simulator runtime mismatch')


def environment(tool, expected):
    image=image_id(os.environ)
    def run(args):
        return subprocess.run(args, check=True, capture_output=True, text=True, timeout=60).stdout.strip()
    version=run(['xcodebuild','-version'])
    arch=run(['uname','-m'])
    runtime=json.loads(run(['xcrun','simctl','list','runtimes','-j']))
    validate_env(image,expected,tool,version,arch,runtime)
    print('KIN_AB_ENV verified toolchain='+tool+' runtime=24A434 image='+image)


def verify_product(path, expected):
    if not re.fullmatch(r'[0-9a-f]{64}', expected): raise ValueError('Invalid digest')
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''): h.update(chunk)
    if h.hexdigest()!=expected: raise ValueError('Product digest mismatch')


def validate_arm(records, arm, tool, image, product, manifest, expected_unit=None):
    if not re.fullmatch(r'[0-9a-f]{64}',product) or not re.fullmatch(r'[0-9a-f]{64}',manifest): raise ValueError('Invalid digest')
    if len(records)!=5 or {r.get('group') for r in records}!=GROUPS: raise ValueError('Incomplete groups')
    for r in records:
        if (r.get('comparable') is not True or r.get('arm')!=arm or r.get('toolchain')!=tool
            or r.get('image')!=image or r.get('runtime')!='24A434' or r.get('product_sha256')!=product
            or r.get('manifest_sha256')!=manifest):
            raise ValueError('Comparison controls differ')
        if not re.fullmatch(r'[0-9a-f]{64}',r.get('identity_sha256','')): raise ValueError('Missing identities')
    unit=next(r['identity_sha256'] for r in records if r['group']=='unit')
    if expected_unit and unit!=expected_unit: raise ValueError('Unit identities differ')
    return unit


def gate():
    root=Path(os.environ['KIN_AB_STATUSES']);files=list(root.rglob('KinAB-status.json'))
    records=[json.loads(p.read_text()) for p in files]
    unit=validate_arm(records,os.environ['KIN_AB_ARM'],os.environ['KIN_AB_TOOLCHAIN'],
                      os.environ['KIN_AB_IMAGE'],os.environ['KIN_AB_PRODUCT_SHA'],os.environ['KIN_AB_MANIFEST_SHA'],os.environ.get('KIN_AB_UNIT_IDS'))
    for r in sorted(records,key=lambda x:x['group']):
        print('KIN_AB_RESULT',r['group'],f"passed={r['passed']} failed={r['failed']} skipped={r['skipped']}")
    with open(os.environ['GITHUB_OUTPUT'],'a') as f:f.write('unit_ids='+unit+'\n')


def required_ci_finished(payload, head):
    runs = payload.get('workflow_runs')
    if not isinstance(runs, list): raise ValueError('Required CI metadata unavailable')
    if len(runs) >= 100: raise ValueError('Required CI result page incomplete')
    if any(not isinstance(r, dict) for r in runs): raise ValueError('Required CI metadata unavailable')
    matches = [r for r in runs if r.get('name') == 'Build and test'
               and r.get('event') == 'pull_request' and r.get('head_sha') == head]
    return bool(matches) and all(r.get('status') == 'completed' for r in matches)


def wait_for_required_ci(head):
    if not re.fullmatch(r'[0-9a-f]{40}', head): raise ValueError('Invalid control head')
    url = 'https://api.github.com/repos/dannydover/Kin/actions/runs?per_page=100&head_sha=' + head
    for _ in range(38):
        with urllib.request.urlopen(url, timeout=20) as response:
            payload = json.load(response)
        if required_ci_finished(payload, head):
            print('KIN_AB_REQUIRED_CI completed; outcome remains unchanged')
            return
        print('KIN_AB_REQUIRED_CI waiting', flush=True)
        time.sleep(60); time.sleep(60)
    raise ValueError('Required CI did not finish within the bound')

def main():
    try:
        if sys.argv[1]=='image':print(image_id(os.environ))
        elif sys.argv[1]=='env':environment(sys.argv[2],sys.argv[3])
        elif sys.argv[1]=='product':verify_product(sys.argv[2],sys.argv[3]);print('KIN_AB_PRODUCT verified')
        elif sys.argv[1]=='gate':gate()
        elif sys.argv[1]=='waitci':wait_for_required_ci(sys.argv[2])
        else:raise ValueError('Invalid mode')
    except (OSError, ValueError, KeyError, TypeError, IndexError, subprocess.SubprocessError, urllib.error.URLError) as e:
        safe={'Missing image metadata','Runner image mismatch','Toolchain mismatch','Architecture mismatch',
              'Runtime metadata unavailable','Simulator runtime mismatch','Invalid digest','Product digest mismatch',
              'Incomplete groups','Comparison controls differ','Missing identities','Unit identities differ',
              'Required CI metadata unavailable','Required CI result page incomplete','Invalid control head','Required CI did not finish within the bound'}
        reason=str(e) if str(e) in safe else 'unavailable or invalid data'
        print('KIN_AB_CONTROL failure='+type(e).__name__+' reason='+reason,file=sys.stderr);return 1
    return 0
if __name__=='__main__':sys.exit(main())
