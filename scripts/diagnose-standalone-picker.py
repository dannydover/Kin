#!/usr/bin/env python3
"""One pure UIKit synthetic picker diagnostic; not release validation.

A fresh simulator and a separate app are used. Complete synthetic xcresult is
retained; app/service lifecycle trace is allowlist-filtered. No account data,
credentials, personal contacts, raw user logs, or signing assets are used.
"""
import hashlib, json, os, platform, re, subprocess, threading, zipfile
from pathlib import Path

TEST='StandalonePickerUITests/PickerUITests/testNativePickerShowsSyntheticContact'
EVENTS={'presenter.didLoad','presenter.didAppear','present.before','present.after','present.complete','present.snapshot','picker.cancel'}
FIELDS={'event','wall','uptime','presenterWindow','pickerLoaded','pickerWindow'}

def clean_env(root):
    return {'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','HOME':os.environ['HOME'],
            'TMPDIR':str(root),'DEVELOPER_DIR':'/Applications/Xcode_27.app/Contents/Developer',
            'LANG':'en_US.UTF-8','LC_ALL':'en_US.UTF-8','NSUnbufferedIO':'YES'}

def sanitized(record):
    message=record.get('eventMessage','')
    if not isinstance(message,str): return None
    result={}
    if 'STANDALONE_PICKER ' in message:
        try: data=json.loads(message.split('STANDALONE_PICKER ',1)[1].strip())
        except (ValueError,TypeError): return None
        if not isinstance(data,dict) or set(data)!=FIELDS or data.get('event') not in EVENTS: return None
        if any(type(data.get(k)) not in (int,float) for k in ('wall','uptime')): return None
        if any(type(data.get(k)) is not bool for k in ('presenterWindow','pickerLoaded','pickerWindow')): return None
        result['direct']=data
    codes=[]
    if 'delayed appearance timed out' in message.lower(): codes.append('appearance_timeout')
    match=re.search(r'Error Domain=([A-Za-z0-9._-]+) Code=(-?\d+)',message)
    if match and match.group(1) in ('NSCocoaErrorDomain','NSPOSIXErrorDomain','NSOSStatusErrorDomain','NSMachErrorDomain','CNErrorDomain'):
        result['error_domain']=match.group(1);result['error_code']=int(match.group(2))
    if not result and not codes:return None
    stamp=str(record.get('timestamp',''))
    result['timestamp']=stamp if re.fullmatch(r'[0-9T :.+Z-]{10,40}',stamp) else 'unavailable'
    result['process']='standalone' if Path(str(record.get('processImagePath',''))).name=='StandalonePicker' else 'contacts_or_framework'
    result['events']=codes
    return result

def retain_result(result,destination):
    assert (result/'Info.plist').is_file()
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,allowZip64=True) as out:
        for path in sorted(result.rglob('*')):
            if path.is_symlink(): raise RuntimeError('result_contains_symlink')
            if path.is_file(): out.write(path,Path(result.name)/path.relative_to(result))
    with zipfile.ZipFile(destination) as check:
        if check.testzip() is not None: raise RuntimeError('result_zip_corrupt')
        assert result.name+'/Info.plist' in check.namelist()
    return hashlib.sha256(destination.read_bytes()).hexdigest()

def main():
    root=Path(os.environ['RUNNER_TEMP'])/'StandalonePickerDiagnostic';public=root/'public';public.mkdir(parents=True)
    result=root/'standalone.xcresult';device=None;stream=None;collector=None;err=None
    m={'status':'preflight','purpose':'one standalone UIKit synthetic diagnostic, not release validation',
       'comparison':'One fresh-simulator result compared with previously recorded UIKit-hosted-in-Kin and Kin-wrapper runs; same hosted Xcode27.0/runtime, different runners and times.',
       'stopping_rule':'One run only; failure at Contacts readiness reproduces independently of Kin/SwiftUI; a pass is inconclusive. Neither outcome proves framework defect or failure rate. No blind reruns.',
       'test':TEST,'permission_grants':[],'raw_user_logs_uploaded':False,'full_synthetic_xcresult_bundle':True}
    def save(): (public/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
    save()
    try:
        v=subprocess.check_output(['xcodebuild','-version'],text=True).strip();assert v=='Xcode 27.0\nBuild version 27A266a';m['toolchain']=v
        assert platform.machine() == 'arm64'
        runtimes=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','-j'],text=True))['runtimes']
        runtime=next(x for x in runtimes if x['identifier']=='com.apple.CoreSimulator.SimRuntime.iOS-27-0' and x['isAvailable'])
        assert runtime['buildversion']=='24A434';m['runtime_preflight']={'version':runtime['version'],'build':runtime['buildversion'],'arch':'arm64'}
        m['head']=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
        device=subprocess.check_output(['xcrun','simctl','create','Standalone synthetic Contacts diagnostic','com.apple.CoreSimulator.SimDeviceType.iPhone-17','com.apple.CoreSimulator.SimRuntime.iOS-27-0'],text=True).strip()
        with (root/'boot.log').open('w') as boot:
            subprocess.run(['xcrun','simctl','boot',device],stdout=boot,stderr=boot,check=True)
            subprocess.run(['xcrun','simctl','bootstatus',device,'-b'],stdout=boot,stderr=boot,check=True)
        predicate='process == "StandalonePicker" OR process CONTAINS[c] "Contacts" OR subsystem BEGINSWITH "com.apple.Contacts"'
        err=(root/'stream-error.log').open('w');stream=subprocess.Popen(['xcrun','simctl','spawn',device,'log','stream','--style','ndjson','--level','debug','--predicate',predicate],stdout=subprocess.PIPE,stderr=err,text=True)
        def collect():
            with (public/'lifecycle.jsonl').open('w') as out:
                for line in stream.stdout:
                    try:event=sanitized(json.loads(line))
                    except (ValueError,TypeError):continue
                    if event:out.write(json.dumps(event)+'\n');out.flush()
        collector=threading.Thread(target=collect,daemon=True);collector.start()
        cmd=['xcodebuild','-project','Diagnostics/StandalonePicker/StandalonePicker.xcodeproj','-scheme','StandalonePicker','-configuration','Debug',
             '-destination','platform=iOS Simulator,id='+device,'-derivedDataPath',str(root/'DerivedData'),'-resultBundlePath',str(result),
             '-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-test-timeouts-enabled','YES',
             '-default-test-execution-time-allowance','240','-maximum-test-execution-time-allowance','600',
             '-only-testing:'+TEST,'test','CODE_SIGNING_ALLOWED=NO']
        with (root/'test.log').open('w') as log:m['xcodebuild_exit']=subprocess.run(cmd,stdout=log,stderr=log,env=clean_env(root)).returncode
        s=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],text=True,env=clean_env(root)))
        m['summary']={k:s.get(k) for k in ('totalTestCount','passedTests','failedTests','skippedTests','result')};m['failure_count']=len(s.get('testFailures',[]))
        configs=s.get('devicesAndConfigurations',[])
        if configs:m['runtime']={k:configs[0].get('device',{}).get(k) for k in ('osVersion','osBuildNumber','modelName')}
        m['status']='completed' if s.get('totalTestCount')==1 and s.get('skippedTests')==0 else 'unexpected_test_count'
    except Exception as e:
        m['status']='diagnostic_error';m['error_type']=type(e).__name__
    finally:
        if stream is not None:
            m['stream_ended_before_test']=stream.poll() is not None;stream.terminate()
            try:stream.wait(timeout=10)
            except subprocess.TimeoutExpired:stream.kill();stream.wait()
            collector.join(timeout=10);err.close();m['lifecycle_rows']=sum(1 for _ in (public/'lifecycle.jsonl').open())
        if result.is_dir() and (result/'Info.plist').is_file():
            try:m['result_zip_sha256']=retain_result(result,public/'standalone-xcresult.zip');m['result_bundle_retained']=True
            except Exception as e:m['result_bundle_retained']=False;m['retention_error_type']=type(e).__name__
        else:m['result_bundle_retained']=False
        if m['status']=='completed' and not m['result_bundle_retained']:m['status']='result_retention_failed'
        if device is not None:
            subprocess.run(['xcrun','simctl','shutdown',device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            m['owned_simulator_removed']=subprocess.run(['xcrun','simctl','delete',device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
        save();print(json.dumps(m))
    return 0 if m['status']=='completed' else 1

if __name__=='__main__':raise SystemExit(main())
