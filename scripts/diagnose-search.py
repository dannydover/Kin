#!/usr/bin/env python3
"""Single bounded synthetic diagnostic. Raw test logs/results never uploaded."""
import json, os, re, subprocess
from pathlib import Path

SOURCE = '208cb6a1500ccc8f5d0bd4f6be254b36ab9e5f92'
APP_TREE = 'b9bd5e8ae1b14556d19a1f992a746fc0a529c684'
TEST_BLOB = '12c13e5fe35b59830aacc9a5415d3efc4fbe983e'
TESTS = ['KinUITests/IndexMembershipUITests/testClearAllPeopleSearchRestoresPeopleWithoutChangingRecords',
         'KinUITests/IndexMembershipUITests/testClearSearchAndFiltersOnEmptyNotebookAtLargestText']

def instrument():
    p = Path('KinUITests/IndexMembershipUITests.swift')
    assert subprocess.check_output(['git','hash-object',str(p)],text=True).strip() == TEST_BLOB
    s = p.read_text()
    old = '        XCTAssertEqual(XCTWaiter.wait(for: [restored],timeout: 5),.completed)'
    new = '''        let diagnosticWait = XCTWaiter.wait(for: [restored],timeout: 5)
        if diagnosticWait != .completed {
            let category = app.buttons["category-filter"].value as? String == "All"
            print("KIN_SEARCH_DIAGNOSTIC stage=recovery nav=\\(app.navigationBars[\"People\"].exists) categoryAll=\\(category) count=\\(app.cells.count) alex=\\(app.staticTexts[\"Alex Morgan\"].exists) clear=\\(clear.exists) keyboard=\\(app.keyboards.firstMatch.exists)")
        }
        XCTAssertEqual(diagnosticWait,.completed)'''
    assert s.count(old) == 1
    s = s.replace(old,new)
    old = '''        app.launchArguments = ["--kin-preview","empty","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); defer { app.terminate() }'''
    new = '''        app.launchArguments = ["--kin-preview","empty","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        print("KIN_SEARCH_DIAGNOSTIC stage=before_largest_launch")
        app.launch()
        print("KIN_SEARCH_DIAGNOSTIC stage=after_largest_launch")
        defer { app.terminate() }'''
    assert s.count(old) == 1
    p.write_text(s.replace(old,new))

def main():
    root=Path(os.environ['RUNNER_TEMP'])/'KinSearchDiagnostic'; public=root/'public'; public.mkdir(parents=True)
    m={'status':'preflight','purpose':'two-test diagnostic, not release validation','source':SOURCE,'application_tree':APP_TREE,'tests':TESTS,'raw_logs_uploaded':False,'permission_grants':[]}
    device=None
    try:
        version=subprocess.check_output(['xcodebuild','-version'],text=True).strip()
        assert version == 'Xcode 27.0\nBuild version 27A266a'
        assert subprocess.check_output(['git','rev-parse','HEAD:Kin'],text=True).strip() == APP_TREE
        m['head']=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip();m['toolchain']=version
        instrument()
        device=subprocess.check_output(['xcrun','simctl','create','Kin synthetic search diagnostic','com.apple.CoreSimulator.SimDeviceType.iPhone-17','com.apple.CoreSimulator.SimRuntime.iOS-27-0'],text=True).strip()
        with (root/'boot.log').open('w') as log:
            for args in [['xcrun','simctl','boot',device],['xcrun','simctl','bootstatus',device,'-b']]:
                subprocess.run(args,stdout=log,stderr=log,check=True)
            subprocess.run(['python3','scripts/create-simulator-photo.py',str(root/'SyntheticPhoto.png')],stdout=log,stderr=log,check=True)
            subprocess.run(['xcrun','simctl','addmedia',device,str(root/'SyntheticPhoto.png')],stdout=log,stderr=log,check=True)
        cmd=['xcodebuild','-project','Kin.xcodeproj','-scheme','Kin','-configuration','Debug','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath',str(root/'DerivedData'),'-resultBundlePath',str(root/'result.xcresult'),'-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-test-timeouts-enabled','YES','-default-test-execution-time-allowance','240','-maximum-test-execution-time-allowance','600']
        cmd += ['-only-testing:'+test for test in TESTS]
        cmd += ['test','CODE_SIGNING_ALLOWED=NO']
        with (root/'test.log').open('w') as log: code=subprocess.run(cmd,stdout=log,stderr=log).returncode
        raw=(root/'test.log').read_text(errors='replace')
        pattern=r'KIN_SEARCH_DIAGNOSTIC stage=(?:before_largest_launch|after_largest_launch|recovery nav=(?:true|false) categoryAll=(?:true|false) count=[0-9]{1,4} alex=(?:true|false) clear=(?:true|false) keyboard=(?:true|false))'
        (public/'markers.txt').write_text('\n'.join(re.findall(pattern,raw))+'\n')
        summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(root/'result.xcresult')],text=True))
        m['summary']={k:summary.get(k) for k in ['totalTestCount','passedTests','failedTests','skippedTests','result']};m['xcodebuild_exit']=code
        allowed={t.removeprefix('KinUITests/') for t in TESTS}; failures=[]
        for f in summary.get('testFailures',[]):
            ident=f.get('testIdentifierString','').removesuffix('()')
            if ident not in allowed: continue
            message=str(f.get('failureText','')).lower()
            classes=[label for term,label in [('launch','launch'),('timed out','timeout'),('failed to get matching','query'),('assert','assertion'),('keyboard','keyboard'),('background assertion','background_assertion')] if term in message]
            failures.append({'test':ident,'message_categories':classes})
        m['failures']=failures;m['status']='completed';assert summary.get('totalTestCount')==len(TESTS)
    except Exception as e:
        m['status']='diagnostic_error';m['error_type']=type(e).__name__
    finally:
        if device:
            subprocess.run(['xcrun','simctl','shutdown',device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            m['owned_simulator_removed']=subprocess.run(['xcrun','simctl','delete',device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
        (public/'manifest.json').write_text(json.dumps(m,indent=2)+'\n');print(json.dumps(m))
    return 0 if m['status']=='completed' else 1

if __name__=='__main__': raise SystemExit(main())
