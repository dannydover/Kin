#!/usr/bin/env python3
"""Record only bounded synthetic runner setup or cleanup outcomes."""
import json,os,subprocess,sys,time
from pathlib import Path
root=Path(os.environ['RUNNER_TEMP']);device=os.environ['KIN_CI_SIMULATOR'];mode=sys.argv[1]
if mode=='grant':
    start=time.monotonic();result=subprocess.run(['xcrun','simctl','privacy',device,'grant','contacts','com.intriguingideas.KinUITests.xctrunner'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    (root/'KinTests-setup.json').write_text(json.dumps({'grant_exit':result.returncode,'grant_seconds':round(time.monotonic()-start,1)})+'\n')
    sys.exit(result.returncode)
elif mode=='cleanup':
    records={}
    for action in ('shutdown','delete'):
        try:
            r=subprocess.run(['xcrun','simctl',action,device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=60)
            records[action]='success' if r.returncode==0 else 'failed'
        except subprocess.TimeoutExpired:records[action]='timeout'
    try:
        data=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','-j'],text=True,timeout=60))
        present=any(x.get('udid')==device for group in data.get('devices',{}).values() for x in group)
        records['inventory']='present' if present else 'absent'
    except (subprocess.SubprocessError,ValueError,OSError):records['inventory']='unknown'
    (root/'KinTests-cleanup.json').write_text(json.dumps(records)+'\n')
    sys.exit(0 if records.get('delete')=='success' and records.get('inventory')=='absent' else 1)
else:sys.exit(2)
