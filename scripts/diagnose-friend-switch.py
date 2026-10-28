#!/usr/bin/env python3
"""One control and one keyboard-dismissal comparison; never release validation."""
import hashlib, json, os, platform, subprocess, zipfile
from pathlib import Path

TEST = 'KinUITests/KinUITests/testBlankNameEditsCancelAndLaterNamingPreserveEntry'
APP_TREE = 'b9bd5e8ae1b14556d19a1f992a746fc0a529c684'
ROOT = Path(os.environ['RUNNER_TEMP']) / 'FriendSwitchComparison'
PUBLIC = ROOT / 'public'
PUBLIC.mkdir(parents=True, exist_ok=True)
ENV = {'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','HOME':os.environ['HOME'], 'TMPDIR':str(ROOT),
       'DEVELOPER_DIR':'/Applications/Xcode_27.app/Contents/Developer','LANG':'en_US.UTF-8',
       'LC_ALL':'en_US.UTF-8','NSUnbufferedIO':'YES'}

def retain(path, dest):
    if not (path/'Info.plist').is_file(): raise RuntimeError('result_not_finalized')
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,allowZip64=True) as z:
        for p in sorted(path.rglob('*')):
            if p.is_symlink(): raise RuntimeError('unexpected_symlink')
            if p.is_file(): z.write(p,Path(path.name)/p.relative_to(path))
    with zipfile.ZipFile(dest) as z:
        if z.testzip() or path.name+'/Info.plist' not in z.namelist(): raise RuntimeError('result_zip_invalid')
    return hashlib.sha256(dest.read_bytes()).hexdigest()

def main():
    report={'purpose':'One control and one keyboard-dismissal comparison; synthetic only; not release validation',
            'stopping_rule':'Run each variant once. No retry and no release conclusion.', 'runs':[]}
    device=None
    try:
        assert subprocess.check_output(['xcodebuild','-version'],text=True).strip() == 'Xcode 27.0\nBuild version 27A266a'
        assert platform.machine() == 'arm64'
        assert subprocess.check_output(['git','rev-parse','HEAD:Kin'],text=True).strip() == APP_TREE
        runtime=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','-j'],text=True))['runtimes']
        assert any(x['identifier']=='com.apple.CoreSimulator.SimRuntime.iOS-27-0' and x['buildversion']=='24A434' and x['isAvailable'] for x in runtime)
        testfile=Path('KinUITests/KinUITests.swift'); original=testfile.read_text()
        needle='        controls.element.tap()\n        let save = editor.buttons.matching(identifier: "Save")'
        assert original.count(needle)==1
        device=subprocess.check_output(['xcrun','simctl','create','Synthetic Friend diagnostic','com.apple.CoreSimulator.SimDeviceType.iPhone-17','com.apple.CoreSimulator.SimRuntime.iOS-27-0'],text=True).strip()
        subprocess.run(['xcrun','simctl','boot',device],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        subprocess.run(['xcrun','simctl','bootstatus',device,'-b'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        for variant in ['control','keyboard_dismissed']:
            if variant == 'keyboard_dismissed':
                replacement='''        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            let returnKey = keyboard.buttons["Return"]
            XCTAssertTrue(returnKey.waitForExistence(timeout: 5))
            returnKey.tap()
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        }
        controls.element.tap()
        let save = editor.buttons.matching(identifier: "Save")'''
                testfile.write_text(original.replace(needle,replacement))
            result=ROOT/(variant+'.xcresult'); derived=ROOT/('Derived-'+variant)
            cmd=['xcodebuild','-project','Kin.xcodeproj','-scheme','Kin','-configuration','Debug','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath',str(derived),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-test-timeouts-enabled','YES','-default-test-execution-time-allowance','240','-maximum-test-execution-time-allowance','600','-only-testing:'+TEST,'test','CODE_SIGNING_ALLOWED=NO']
            with (ROOT/(variant+'.log')).open('w') as log:
                code=subprocess.run(cmd,stdout=log,stderr=log,env=ENV,timeout=900).returncode
            summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],text=True,env=ENV,timeout=60))
            entry={'variant':variant,'xcodebuild_exit':code,'summary':{k:summary.get(k) for k in ('totalTestCount','passedTests','failedTests','skippedTests','result')}}
            entry['bundle_sha256']=retain(result,PUBLIC/(variant+'-xcresult.zip'))
            if entry['summary']['totalTestCount'] != 1 or entry['summary']['skippedTests'] != 0: raise RuntimeError('unexpected_test_count')
            report['runs'].append(entry)
            (PUBLIC/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
        report['status']='completed'
    except Exception as e:
        report['status']='diagnostic_error';report['error_type']=type(e).__name__
    finally:
        if device:
            try: subprocess.run(['xcrun','simctl','shutdown',device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
            except subprocess.TimeoutExpired: pass
            try: subprocess.run(['xcrun','simctl','delete',device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
            except subprocess.TimeoutExpired: pass
        (PUBLIC/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    return 0 if report['status']=='completed' else 1
if __name__=='__main__': raise SystemExit(main())
