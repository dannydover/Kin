#!/usr/bin/env python3
"""Single bounded synthetic diagnostic. Raw test logs/results never uploaded."""
import hashlib, json, os, re, subprocess, zipfile
from pathlib import Path

SOURCE = '208cb6a1500ccc8f5d0bd4f6be254b36ab9e5f92'
APP_TREE = 'b9bd5e8ae1b14556d19a1f992a746fc0a529c684'
TEST_BLOB = '12c13e5fe35b59830aacc9a5415d3efc4fbe983e'

def clean_env(root):
    # Synthetic hosted runner only: do not pass Actions/GitHub token variables
    # to the test process or its retained result bundle.
    return {'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','HOME':os.environ['HOME'],
            'TMPDIR':str(root),'DEVELOPER_DIR':'/Applications/Xcode_27.app/Contents/Developer',
            'LANG':'en_US.UTF-8','LC_ALL':'en_US.UTF-8','NSUnbufferedIO':'YES'}


def retain_result(result, destination):
    assert (result/'Info.plist').is_file()
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,allowZip64=True) as out:
        for path in sorted(result.rglob('*')):
            if path.is_symlink(): raise RuntimeError('result_contains_symlink')
            if path.is_file(): out.write(path,Path(result.name)/path.relative_to(result))
    with zipfile.ZipFile(destination) as check:
        if check.testzip() is not None: raise RuntimeError('result_zip_corrupt')
        assert result.name+'/Info.plist' in check.namelist()
    return hashlib.sha256(destination.read_bytes()).hexdigest()

TESTS = ['KinUITests/IndexMembershipUITests/testClearAllPeopleSearchRestoresPeopleWithoutChangingRecords',
         ]

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
    s = s.replace(old,new)
    old_fixture = '        let app = XCUIApplication(); launch(app)\n        for (name, category) in [("Alex Morgan", ""), ("Jamie Patel", "Friend"), ("Robin Chen", "Family")] {'
    new_fixture = '        let app = XCUIApplication()\n        print("KIN_SEARCH_DIAGNOSTIC stage=fixture_launch_start")\n        launch(app)\n        print("KIN_SEARCH_DIAGNOSTIC stage=fixture_launch_end")\n        var diagnosticIndex = 0\n        for (name, category) in [("Alex Morgan", ""), ("Jamie Patel", "Friend"), ("Robin Chen", "Family")] {\n            diagnosticIndex += 1\n            print("KIN_SEARCH_DIAGNOSTIC stage=fixture_person_start index=\\(diagnosticIndex)")'
    assert s.count(old_fixture) == 1
    s = s.replace(old_fixture,new_fixture)
    old_fixture_end = '            XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: 5))\n        }\n        return app'
    new_fixture_end = '            XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: 5))\n            print("KIN_SEARCH_DIAGNOSTIC stage=fixture_person_end index=\\(diagnosticIndex)")\n        }\n        return app'
    assert s.count(old_fixture_end) == 1
    s = s.replace(old_fixture_end,new_fixture_end)
    a = s.index('    @MainActor func testClearAllPeopleSearchRestoresPeopleWithoutChangingRecords()')
    b = s.index('    @MainActor func testClearSearchAndFiltersOnEmptyNotebookAtLargestText()',a)
    method = s[a:b]
    for old_action,new_action in [
      ('        app.buttons["people-menu"].tap(); app.buttons["All people"].tap()', '        print("KIN_SEARCH_DIAGNOSTIC stage=allpeople_start")\n        app.buttons["people-menu"].tap(); app.buttons["All people"].tap()'),
      ('        search.tap(); search.typeText("NoSuchFictionalPerson")', '        print("KIN_SEARCH_DIAGNOSTIC stage=search_start")\n        search.tap(); search.typeText("NoSuchFictionalPerson")\n        print("KIN_SEARCH_DIAGNOSTIC stage=search_end")'),
      ('        clear.tap(); assertClearSearchRestored(app)', '        print("KIN_SEARCH_DIAGNOSTIC stage=clear_start")\n        clear.tap()\n        print("KIN_SEARCH_DIAGNOSTIC stage=clear_end")\n        assertClearSearchRestored(app)')]:
        assert method.count(old_action) == 1
        method = method.replace(old_action,new_action)
    s = s[:a] + method + s[b:]
    p.write_text(s)

def main():
    root=Path(os.environ['RUNNER_TEMP'])/'KinSearchDiagnostic'; public=root/'public'; public.mkdir(parents=True)
    m={'status':'preflight','purpose':'single-test stage diagnostic, not release validation','source':SOURCE,'application_tree':APP_TREE,'tests':TESTS,'raw_user_logs_uploaded':False,'full_synthetic_xcresult_bundle':True,'permission_grants':[]}
    device=None; result=root/'result.xcresult'
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
        cmd=['xcodebuild','-project','Kin.xcodeproj','-scheme','Kin','-configuration','Debug','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath',str(root/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-test-timeouts-enabled','YES','-default-test-execution-time-allowance','240','-maximum-test-execution-time-allowance','600']
        cmd += ['-only-testing:'+test for test in TESTS]
        cmd += ['test','CODE_SIGNING_ALLOWED=NO']
        with (root/'test.log').open('w') as log: code=subprocess.run(cmd,stdout=log,stderr=log,env=clean_env(root)).returncode
        raw=(root/'test.log').read_text(errors='replace')
        pattern=r'KIN_SEARCH_DIAGNOSTIC stage=(?:before_largest_launch|after_largest_launch|fixture_launch_start|fixture_launch_end|fixture_person_start index=[0-3]|fixture_person_end index=[0-3]|allpeople_start|search_start|search_end|clear_start|clear_end|recovery nav=(?:true|false) categoryAll=(?:true|false) count=[0-9]{1,4} alex=(?:true|false) clear=(?:true|false) keyboard=(?:true|false))'
        (public/'markers.txt').write_text('\n'.join(re.findall(pattern,raw))+'\n')
        summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],text=True,env=clean_env(root)))
        m['summary']={k:summary.get(k) for k in ['totalTestCount','passedTests','failedTests','skippedTests','result']};m['xcodebuild_exit']=code
        allowed={t.removeprefix('KinUITests/') for t in TESTS}; failures=[]
        for f in summary.get('testFailures',[]):
            ident=f.get('testIdentifierString','').removesuffix('()')
            if ident not in allowed: continue
            message=str(f.get('failureText','')).lower()
            classes=[label for term,label in [('launch','launch'),('timed out','timeout'),('failed to get matching','query'),('assert','assertion'),('keyboard','keyboard'),('background assertion','background_assertion'),('exceed','exceeded'),('failed','failed'),('error','error'),('wait','wait'),('element','element'),('match','matching'),('process','process'),('tap','tap'),('application','application'),('terminated','terminated'),('quiescen','quiescence'),('interrupt','interrupted')] if term in message]
            failures.append({'test':ident,'message_categories':classes,'message_length':len(message),'source_references':sorted(set(re.findall(r'IndexMembershipUITests\.swift:[0-9]+',message,flags=re.I)))})
        m['failures']=failures;m['status']='completed';assert summary.get('totalTestCount')==len(TESTS)
    except Exception as e:
        m['status']='diagnostic_error';m['error_type']=type(e).__name__
    finally:
        if result.is_dir() and (result/'Info.plist').is_file():
            try:
                m['result_zip_sha256']=retain_result(result,public/'synthetic-xcresult.zip')
                m['result_bundle_retained']=True
            except Exception as error:
                m['result_bundle_retained']=False;m['result_retention_error_type']=type(error).__name__
        else:
            m['result_bundle_retained']=False
        if m['status'] == 'completed' and not m['result_bundle_retained']:
            m['status'] = 'result_retention_failed'
        if device:
            subprocess.run(['xcrun','simctl','shutdown',device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            m['owned_simulator_removed']=subprocess.run(['xcrun','simctl','delete',device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
        (public/'manifest.json').write_text(json.dumps(m,indent=2)+'\n');print(json.dumps(m))
    return 0 if m['status']=='completed' else 1

if __name__=='__main__': raise SystemExit(main())
