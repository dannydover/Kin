#!/usr/bin/env python3
"""Run existing CI selection with allowlisted progress and no raw test output."""
import importlib.util, json, os, re, select, signal, subprocess, sys, time
from pathlib import Path

spec=importlib.util.spec_from_file_location('shards','scripts/ci-test-shards.py'); shards=importlib.util.module_from_spec(spec);spec.loader.exec_module(shards)

def parse(line, allowed):
    m=re.search(r"Test Case '-\[(\w+)\.(\w+) (test\w+)\]' (started|passed|failed)",line)
    if m:
        ident=f'{m[1]}/{m[2]}/{m[3]}'
        return {'kind':'test','id':ident,'event':m[4]} if ident in allowed else None
    m=re.search(r'KIN_CI_AUTH (notDetermined|restricted|denied|authorized|limited|unknown)\b',line)
    if m:return {'kind':'authorization','state':m[1]}
    m=re.search(r'KIN_CI_FRIEND (before|after) keyboard=(true|false) wrapper=(on|off|unknown) control=(on|off|unknown) hittable=(true|false)',line)
    if m:return {'kind':'friend','stage':m[1],'keyboard':m[2]=='true','wrapper':m[3],'control':m[4],'hittable':m[5]=='true'}
    m=re.search(r'KIN_CI_DELETE before=([0-9]{1,4})\b',line)
    if m:return {'kind':'deletion','stage':'before','length':int(m[1])}
    m=re.search(r'KIN_CI_DELETE after=([0-9]{1,4}) completed=(true|false)\b',line)
    if m:return {'kind':'deletion','stage':'after','length':int(m[1]),'completed':m[2]=='true'}
    m=re.search(r'KIN_CI_CONTACT count=([0-9]{1,3})\b',line)
    if m:return {'kind':'contact_candidates','count':int(m[1])}
    m=re.search(r'KIN_CI_CONTACT candidate=([0-9]{1,3}) inside=(true|false)\b',line)
    if m:return {'kind':'contact_candidate','index':int(m[1]),'inside':m[2]=='true'}
    if re.search(r'\bt =\s*[0-9.]+s',line):
        for pattern,label in [(r'\bTap ','tap'),(r'\bDouble tap ','double_tap'),(r'\bWaiting ','wait'),(r'\bSwipe ','swipe'),(r'\bType ','type'),(r'\bLaunch ','launch'),(r'\bTerminate ','terminate'),(r'\bChecking existence','exists'),(r'\bSynthesize event','synthesize'),(r'\bWait for .* idle','idle')]:
            if re.search(pattern,line):return {'kind':'action','stage':label}
    return None

def append(out, record):
    out.write(json.dumps(record,separators=(',',':'))+'\n');out.flush();os.fsync(out.fileno())

def main():
    group=sys.argv[1];ids=shards.selections(group);allowed=set(ids)
    result=Path(os.environ['RUNNER_TEMP'])/'KinTests.xcresult';progress=Path(os.environ['RUNNER_TEMP'])/'KinTests-progress.jsonl'
    env={k:os.environ[k] for k in ('PATH','HOME','TMPDIR','DEVELOPER_DIR','LANG','LC_ALL') if k in os.environ}
    env['NSUnbufferedIO']='YES'
    cmd=['xcodebuild','-project','Kin.xcodeproj','-scheme','Kin','-destination','platform=iOS Simulator,id='+os.environ['KIN_CI_SIMULATOR'],'-derivedDataPath','DerivedData','-resultBundlePath',str(result),'-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-test-timeouts-enabled','YES','-default-test-execution-time-allowance','240','-maximum-test-execution-time-allowance','600']+['-only-testing:'+x for x in ids]+['clean','test','CODE_SIGNING_ALLOWED=NO']
    started=time.monotonic();current=None;authorization=set();interrupted=False
    with progress.open('w') as out:
        proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env,start_new_session=True,bufsize=0)
        def stop(signum,frame):
            nonlocal interrupted
            interrupted=True
            try:os.killpg(proc.pid,signal.SIGINT)
            except ProcessLookupError:pass
        signal.signal(signal.SIGINT,stop);signal.signal(signal.SIGTERM,stop)
        buf=b'';last=0
        while True:
            elapsed=round(time.monotonic()-started,1);ready,_,_=select.select([proc.stdout],[],[],1)
            if ready:
                chunk=os.read(proc.stdout.fileno(),65536)
                if chunk:
                    buf+=chunk
                    while b'\n' in buf:
                        line,buf=buf.split(b'\n',1);event=parse(line.decode('utf-8','replace'),allowed)
                        if event:
                            if event['kind']=='test':current=event['id'] if event['event']=='started' else None
                            if event['kind']=='authorization':authorization.add(event['state'])
                            event['elapsed']=elapsed
                            if current and event['kind'] in ('action','friend','deletion','contact_candidates','contact_candidate'):event['test']=current
                            append(out,event)
                            # Only allowlisted test IDs and fixed status tokens reach the live log.
                            # This records when a failure is observed, distinct from job failure.
                            if event['kind']=='test':
                                print(f"CI_TEST {event['event']} {event['id']} elapsed={elapsed}",flush=True)
                    if len(buf)>65536:buf=b''
                elif proc.poll() is not None:break
            if elapsed-last>=15:append(out,{'kind':'heartbeat','elapsed':elapsed,'test':current});last=elapsed
            if proc.poll() is not None and not ready:break
        code=proc.wait();append(out,{'kind':'exit','elapsed':round(time.monotonic()-started,1),'code':code,'interrupted':interrupted})
    if interrupted:return 1
    if code:return code if code>0 else 1
    if group!='unit' and authorization != {'authorized'}:
        print('CI runner Contacts authorization was not verified as authorized.',file=sys.stderr);return 1
    return 0
if __name__=='__main__':sys.exit(main())
