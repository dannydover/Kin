#!/usr/bin/env python3
"""One paired synthetic diagnostic; never release validation.

The two arms run serially on fresh owned simulators under the same hosted
Xcode. Full finalized xcresult bundles are zipped; only lifecycle events are
filtered. No user account or personal contacts are present on the runner.
"""
import hashlib, importlib.util, json, os, re, subprocess, threading, zipfile
from pathlib import Path

ARMS = [('uikit','KinUITests/UIKitPickerComparisonUITests/testDirectUIKitPickerShowsSyntheticContact'),
        ('kin','KinUITests/KinUITests/testNewImportSavesReviewedNamesForEveryEntryPoint')]
SOURCE='208cb6a1500ccc8f5d0bd4f6be254b36ab9e5f92'


def clean_env(root):
    # Explicit whitelist: no GitHub/Actions tokens, auth material or host account
    # environment reaches xcodebuild or its synthetic simulator test processes.
    return {'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','HOME':os.environ['HOME'],
            'TMPDIR':str(root),'DEVELOPER_DIR':'/Applications/Xcode_27.app/Contents/Developer',
            'LANG':'en_US.UTF-8','LC_ALL':'en_US.UTF-8','NSUnbufferedIO':'YES'}


def zip_result(result, destination):
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
    root=Path(os.environ['RUNNER_TEMP'])/'KinUIKitComparison'; public=root/'public'; public.mkdir(parents=True)
    manifest={'status':'preflight','purpose':'single paired synthetic diagnostic; not release validation',
      'release_source':SOURCE,'comparison':'Direct UIKit presenter versus unchanged Kin wrapper; fresh simulator per arm, same runner/toolchain. Single pair cannot establish failure rates.',
      'stopping_rule':'One pair only. A path difference is an association, not proof; both pass or both fail leaves cause unresolved. No retry to obtain green.',
      'permission_grants':[],'raw_user_logs_uploaded':False,'full_xcresult_bundles':True,'arms':[]}
    def save(): (public/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    save()
    try:
        version=subprocess.check_output(['xcodebuild','-version'],text=True).strip();assert version=='Xcode 27.0\nBuild version 27A266a'
        manifest['toolchain']=version
        manifest['head']=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
        manifest['diagnostic_app_tree']=subprocess.check_output(['git','rev-parse','HEAD:Kin'],text=True).strip()
        spec=importlib.util.spec_from_file_location('picker','scripts/diagnose-picker.py');picker=importlib.util.module_from_spec(spec);spec.loader.exec_module(picker)
        for label,test in ARMS:
            device=None;stream=None;collector=None;result=root/(label+'.xcresult');item={'arm':label,'test':test};manifest['arms'].append(item);save()
            try:
                device=subprocess.check_output(['xcrun','simctl','create','Kin synthetic '+label+' comparison','com.apple.CoreSimulator.SimDeviceType.iPhone-17','com.apple.CoreSimulator.SimRuntime.iOS-27-0'],text=True).strip()
                with (root/(label+'-boot.log')).open('w') as boot:
                    subprocess.run(['xcrun','simctl','boot',device],stdout=boot,stderr=boot,check=True)
                    subprocess.run(['xcrun','simctl','bootstatus',device,'-b'],stdout=boot,stderr=boot,check=True)
                    photo=root/'SyntheticPhoto.png'
                    subprocess.run(['python3','scripts/create-simulator-photo.py',str(photo)],stdout=boot,stderr=boot,check=True)
                    subprocess.run(['xcrun','simctl','addmedia',device,str(photo)],stdout=boot,stderr=boot,check=True)
                pred='process == "Kin" OR process CONTAINS[c] "Contacts" OR subsystem BEGINSWITH "com.apple.Contacts"'
                err=(root/(label+'-stream.log')).open('w')
                stream=subprocess.Popen(['xcrun','simctl','spawn',device,'log','stream','--style','ndjson','--level','debug','--predicate',pred],stdout=subprocess.PIPE,stderr=err,text=True)
                def collect():
                    with (public/(label+'-lifecycle.jsonl')).open('w') as out:
                        for line in stream.stdout:
                            try:event=picker.sanitized_event(json.loads(line))
                            except (ValueError,TypeError):continue
                            if event:out.write(json.dumps(event)+'\n');out.flush()
                collector=threading.Thread(target=collect,daemon=True);collector.start()
                cmd=['xcodebuild','-project','Kin.xcodeproj','-scheme','Kin','-configuration','Debug',
                  '-destination','platform=iOS Simulator,id='+device,'-derivedDataPath',str(root/'DerivedData'),
                  '-resultBundlePath',str(result),'-parallel-testing-enabled','NO','-collect-test-diagnostics','never',
                  '-test-timeouts-enabled','YES','-default-test-execution-time-allowance','240','-maximum-test-execution-time-allowance','600',
                  '-only-testing:'+test,'test','CODE_SIGNING_ALLOWED=NO',
                  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG KIN_UIKIT_COMPARISON KIN_PICKER_LIFECYCLE_DIAGNOSTIC']
                with (root/(label+'-build.log')).open('w') as log:
                    item['xcodebuild_exit']=subprocess.run(cmd,stdout=log,stderr=log,env=clean_env(root)).returncode
                summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],text=True,env=clean_env(root)))
                item['summary']={k:summary.get(k) for k in ('totalTestCount','passedTests','failedTests','skippedTests','result')}
                item['failure_count']=len(summary.get('testFailures',[]));item['finalized']=True
                item['result_zip_sha256']=zip_result(result,public/(label+'-xcresult.zip'))
                if summary.get('totalTestCount') != 1 or summary.get('skippedTests') != 0:
                    item['finalized']=False;item['coverage_error']='expected_one_unskipped_test'
            except Exception as e:
                item['error_type']=type(e).__name__;item['finalized']=False
                if result.is_dir() and (result/'Info.plist').is_file():
                    try:item['incomplete_result_zip_sha256']=zip_result(result,public/(label+'-incomplete-xcresult.zip'))
                    except Exception as archive_error:item['result_retention_error_type']=type(archive_error).__name__
            finally:
                if stream is not None:
                    item['log_stream_ended_before_test']=stream.poll() is not None
                    stream.terminate()
                    try:stream.wait(timeout=10)
                    except subprocess.TimeoutExpired:stream.kill();stream.wait()
                    collector.join(timeout=10);err.close()
                    item['lifecycle_rows']=sum(1 for _ in (public/(label+'-lifecycle.jsonl')).open())
                if device is not None:
                    subprocess.run(['xcrun','simctl','shutdown',device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                    item['owned_simulator_removed']=subprocess.run(['xcrun','simctl','delete',device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
                save()
            if not item.get('finalized'):
                break
        manifest['status']='completed' if len(manifest['arms'])==2 and all(x.get('finalized') for x in manifest['arms']) else 'incomplete'
    except Exception as e:
        manifest['status']='diagnostic_error';manifest['error_type']=type(e).__name__
    finally:
        save();print(json.dumps(manifest))
    return 0 if manifest['status']=='completed' else 1

if __name__=='__main__':raise SystemExit(main())
