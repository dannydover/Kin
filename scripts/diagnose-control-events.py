#!/usr/bin/env python3
"""Nonshipping synthetic event/state capture; not release validation."""
import datetime
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
APP_TREE = 'b9bd5e8ae1b14556d19a1f992a746fc0a529c684'
CASES = {
    'friend': 'KinUITests/KinUITests/testPhotoRemovalAlertHasVisibleCancelAndPreservesSavedPhoto',
    'clear': 'KinUITests/IndexMembershipUITests/testClearEmptyCategoryRestoresPeopleWithoutChangingRecords',
}


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise ValueError('Diagnostic source shape changed')
    return source.replace(before, after, 1)


def instrument(friend_test, clear_test, editor, content, app):
    friend_test = replace_once(friend_test, 'import XCTest\n', 'import XCTest\nimport OSLog\n')
    clear_test = replace_once(clear_test, 'import XCTest\n', 'import XCTest\nimport OSLog\n')
    before = '        recordFriendStage("before")\n        controls.element.tap()\n        recordFriendStage("after")'
    after = '''        recordFriendStage("before")
        Logger(subsystem: "com.kin.synthetic.marker", category: "control").notice("KIN_MARK target=friend stage=before ms=\\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
        controls.element.tap()
        Logger(subsystem: "com.kin.synthetic.marker", category: "control").notice("KIN_MARK target=friend stage=after ms=\\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
        recordFriendStage("after")'''
    friend_test = replace_once(friend_test, before, after)
    first = clear_test.index('    @MainActor func testClearEmptyCategoryRestoresPeopleWithoutChangingRecords()')
    last = clear_test.index('    @MainActor func testClearCombinedSearchAndCategoryRepeatedlyPreservesPeople()', first)
    block = clear_test[first:last]
    block = replace_once(block, '        clear.tap(); assertClearSearchRestored(app)', '''        Logger(subsystem: "com.kin.synthetic.marker", category: "control").notice("KIN_MARK target=clear stage=before ms=\\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
        clear.tap()
        Logger(subsystem: "com.kin.synthetic.marker", category: "control").notice("KIN_MARK target=clear stage=after ms=\\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
        assertClearSearchRestored(app)''')
    clear_test = clear_test[:first] + block + clear_test[last:]
    editor = replace_once(editor, 'import SwiftUI\n', 'import SwiftUI\nimport OSLog\n')
    old = '                    if selected { draft.connections.insert(connection) } else { draft.connections.remove(connection) }\n'
    new = '''                    if connection == .friend { Logger(subsystem: "com.kin.synthetic.control", category: "friend").notice("KIN_BIND stage=before selected=\\(selected, privacy: .public) present=\\(draft.connections.contains(connection), privacy: .public) ms=\\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)") }
                    if selected { draft.connections.insert(connection) } else { draft.connections.remove(connection) }
                    if connection == .friend { Logger(subsystem: "com.kin.synthetic.control", category: "friend").notice("KIN_BIND stage=after selected=\\(selected, privacy: .public) present=\\(draft.connections.contains(connection), privacy: .public) ms=\\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)") }
'''
    editor = replace_once(editor, old, new)
    old = '''                }))
            }
        } header: { Text("Your connection") }'''
    new = '''                }))
                .background {
                    if connection == .friend {
                        GeometryReader { proxy in
                            Color.clear.allowsHitTesting(false)
                                .onAppear { ControlEventProbe.friend = proxy.frame(in: .global); ControlEventProbe.geometry("friend") }
                                .onChange(of: proxy.frame(in: .global)) { _, frame in ControlEventProbe.friend = frame }
                        }
                    }
                }
            }
        } header: { Text("Your connection") }'''
    editor = replace_once(editor, old, new)
    content = replace_once(content, 'import SwiftUI\n', 'import SwiftUI\nimport OSLog\n')
    old = '            query = ""; category = nil; scope = .yours; searching = false'
    new = '''            Logger(subsystem: "com.kin.synthetic.control", category: "clear").notice("KIN_CLEAR stage=before queryEmpty=\\(query.isEmpty, privacy: .public) categoryNone=\\(category == nil, privacy: .public) yours=\\(scope == .yours, privacy: .public) searching=\\(searching, privacy: .public) ms=\\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
            query = ""; category = nil; scope = .yours; searching = false
            Logger(subsystem: "com.kin.synthetic.control", category: "clear").notice("KIN_CLEAR stage=after queryEmpty=\\(query.isEmpty, privacy: .public) categoryNone=\\(category == nil, privacy: .public) yours=\\(scope == .yours, privacy: .public) searching=\\(searching, privacy: .public) ms=\\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")'''
    content = replace_once(content, old, new)
    old = '        .buttonStyle(.borderedProminent).controlSize(.large)'
    new = '''        .background {
            GeometryReader { proxy in
                Color.clear.allowsHitTesting(false)
                    .onAppear { ControlEventProbe.clear = proxy.frame(in: .global); ControlEventProbe.geometry("clear") }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in ControlEventProbe.clear = frame }
            }
        }
        .buttonStyle(.borderedProminent).controlSize(.large)'''
    content = replace_once(content, old, new)
    app = replace_once(app, 'import SwiftUI\n', 'import SwiftUI\nimport OSLog\nimport ObjectiveC.runtime\n')
    app = replace_once(app, 'struct KinApp: App {\n', 'struct KinApp: App {\n    init() { ControlEventProbe.install() }\n')
    app += r'''
// Diagnostic build only. Fixed fields, no labels, text, names or coordinates.
@MainActor enum ControlEventProbe {
    static var friend = CGRect.null
    static var clear = CGRect.null
    static var heartbeat: Timer?
    static func geometry(_ target: String) {
        Logger(subsystem: "com.kin.synthetic.control", category: "probe").notice("KIN_GEOMETRY target=\(target, privacy: .public) ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
    }
    static func install() {
        guard let original = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
              let observer = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.kinDiagnosticSendEvent(_:))) else {
            Logger(subsystem: "com.kin.synthetic.control", category: "probe").notice("KIN_PROBE ready=false ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)"); return
        }
        method_exchangeImplementations(original, observer)
        Logger(subsystem: "com.kin.synthetic.control", category: "probe").notice("KIN_PROBE ready=true ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            Logger(subsystem: "com.kin.synthetic.control", category: "probe").notice("KIN_HEARTBEAT ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
        }
        RunLoop.main.add(timer, forMode: .common); heartbeat = timer
    }
}
extension UIApplication {
    @objc dynamic func kinDiagnosticSendEvent(_ event: UIEvent) {
        if event.type == .touches, let touch = event.allTouches?.first,
           touch.phase == .began, let window = touch.window {
            let location = touch.location(in: window)
            let inFriend = ControlEventProbe.friend.contains(location)
            let inClear = ControlEventProbe.clear.contains(location)
            var view = window.hitTest(location, with: event)
            var onSwitch = false; var onButton = false
            while let current = view {
                if current is UISwitch { onSwitch = true }
                if current is UIButton { onButton = true }
                view = current.superview
            }
            Logger(subsystem: "com.kin.synthetic.control", category: "probe").notice("KIN_TOUCH friend=\(inFriend, privacy: .public) clear=\(inClear, privacy: .public) switch=\(onSwitch, privacy: .public) button=\(onButton, privacy: .public) ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000), privacy: .public)")
        }
        kinDiagnosticSendEvent(event)
    }
}
'''
    return friend_test, clear_test, editor, content, app


PATTERNS = {
    'mark': re.compile(r'KIN_MARK target=(friend|clear) stage=(before|after) ms=([0-9]{1,16})'),
    'probe': re.compile(r'KIN_PROBE ready=(true|false) ms=([0-9]{1,16})'),
    'geometry': re.compile(r'KIN_GEOMETRY target=(friend|clear) ms=([0-9]{1,16})'),
    'heartbeat': re.compile(r'KIN_HEARTBEAT ms=([0-9]{1,16})'),
    'touch': re.compile(r'KIN_TOUCH friend=(true|false) clear=(true|false) switch=(true|false) button=(true|false) ms=([0-9]{1,16})'),
    'binding': re.compile(r'KIN_BIND stage=(before|after) selected=(true|false) present=(true|false) ms=([0-9]{1,16})'),
    'clear': re.compile(r'KIN_CLEAR stage=(before|after) queryEmpty=(true|false) categoryNone=(true|false) yours=(true|false) searching=(true|false) ms=([0-9]{1,16})'),
}


def sanitize_event(item):
    if not isinstance(item, dict) or not isinstance(item.get('eventMessage'), str): return None
    for kind, pattern in PATTERNS.items():
        match = pattern.fullmatch(item['eventMessage'])
        if match:
            # Exact matched tokens only; no log metadata, labels, paths or values.
            return {'kind': kind, 'fields': list(match.groups()[:-1]), 'uptime_ms': int(match.groups()[-1])}
    return None


def calibrate(events, target):
    if target not in CASES: raise ValueError('Unknown target')
    marks = [e for e in events if e['kind']=='mark' and e['fields'][0]==target]
    before = [e['uptime_ms'] for e in marks if e['fields'][1]=='before']
    after = [e['uptime_ms'] for e in marks if e['fields'][1]=='after']
    if len(before)!=1 or len(after)!=1 or before[0]>after[0]: return False
    ready = any(e['kind']=='probe' and e['fields']==['true'] and e['uptime_ms']<=before[0] for e in events)
    geometry = any(e['kind']=='geometry' and e['fields']==[target] and e['uptime_ms']<=before[0] for e in events)
    heartbeats = [e['uptime_ms'] for e in events if e['kind']=='heartbeat']
    # A gap during/around the action makes absence of events uninterpretable.
    pre = [t for t in heartbeats if before[0]-2500<=t<=before[0]]
    post = [t for t in heartbeats if after[0]<=t<=after[0]+2500]
    if not pre or not post: return False
    window = sorted([max(pre)] + [t for t in heartbeats if before[0]<t<after[0]] + [min(post)])
    return ready and geometry and all(b-a<=2500 for a,b in zip(window,window[1:]))


def failure_category(text):
    if not isinstance(text, str): return 'unknown'
    if 'Friend on and Save enabled' in text: return 'friend_readiness'
    if 'Timed out while evaluating UI query' in text: return 'ui_query_timeout'
    if 'XCTWaiterResult' in text: return 'readiness_wait'
    if 'execution time allowance' in text: return 'test_timeout'
    return 'other'


def test_identities(node):
    found = []
    def visit(item):
        if not isinstance(item, dict): raise ValueError('Malformed test tree')
        if item.get('nodeType') == 'Test Case':
            ident = item.get('nodeIdentifier')
            if not isinstance(ident, str) or not re.fullmatch(r'\w+/test\w+\(\)', ident): raise ValueError('Unknown test identifier')
            found.append('KinUITests/' + ident[:-2])
        children = item.get('children', [])
        if not isinstance(children, list): raise ValueError('Malformed children')
        for child in children: visit(child)
    if not isinstance(node, dict) or not isinstance(node.get('testNodes'), list): raise ValueError('Missing test tree')
    for child in node['testNodes']: visit(child)
    if len(found) != len(set(found)): raise ValueError('Duplicate test identities')
    return found


def finalized_counts(summary):
    keys=('totalTestCount','passedTests','failedTests','skippedTests','expectedFailures')
    if not isinstance(summary,dict) or any(type(summary.get(k)) is not int for k in keys):
        raise ValueError('Malformed result counts')
    counts={k:summary[k] for k in keys};counts['result']=summary.get('result')
    if counts['totalTestCount']!=1 or counts['result'] not in ('Passed','Failed'):
        raise ValueError('Unfinalized result')
    if any(counts[k]<0 for k in keys) or sum(counts[k] for k in ('passedTests','failedTests','skippedTests'))!=1:
        raise ValueError('Inconsistent result counts')
    if counts['failedTests'] and not summary.get('testFailures'):
        raise ValueError('Missing failure detail')
    return counts


def command(args, timeout=60, check=True):
    return subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True, timeout=timeout, check=check)


def run_diagnostic(mode):
    if mode not in CASES: raise ValueError('Unknown mode')
    out = Path(os.environ['RUNNER_TEMP']) / 'KinControlDiagnostic' / 'public'
    out.mkdir(parents=True, exist_ok=True)
    root = out.parent; result = root/'Control.xcresult'; device = None
    manifest = {'purpose':'nonshipping synthetic diagnostic; not release validation','case':mode,
                'expected_test':CASES[mode], 'status':'started','contacts_grant':False,
                'raw_result_retained':False,'raw_result_reason':'may contain unrelated host diagnostics',
                'collector':'unknown','cleanup':{}}
    def save(): (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    save()
    try:
        toolchain=command(['xcodebuild','-version'],timeout=30).stdout.strip()
        if toolchain != 'Xcode 27.0\nBuild version 27A266a' or platform.machine()!='arm64': raise ValueError('Toolchain mismatch')
        if command(['git','rev-parse','HEAD:Kin'],timeout=30).stdout.strip()!=APP_TREE: raise ValueError('App source mismatch')
        manifest['base_sha']=command(['git','rev-parse','HEAD'],timeout=30).stdout.strip()
        manifest['stage']='instrument';save()
        paths=[ROOT/'KinUITests/KinUITests.swift', ROOT/'KinUITests/IndexMembershipUITests.swift',
               ROOT/'Kin/Views/PersonEditor.swift', ROOT/'Kin/ContentView.swift', ROOT/'Kin/KinApp.swift']
        patched=instrument(*[p.read_text() for p in paths])
        for path,value in zip(paths,patched): path.write_text(value)
        manifest['stage']='simulator';save()
        device=command(['xcrun','simctl','create','Synthetic control diagnostic',
                        'com.apple.CoreSimulator.SimDeviceType.iPhone-17','com.apple.CoreSimulator.SimRuntime.iOS-27-0'],timeout=120).stdout.strip()
        if not re.fullmatch(r'[0-9A-Fa-f-]{36}',device): raise ValueError('Unexpected simulator identity')
        command(['xcrun','simctl','boot',device],timeout=120)
        command(['xcrun','simctl','bootstatus',device,'-b'],timeout=300)
        if mode=='friend':
            image=root/'synthetic.png'
            command(['python3','scripts/create-simulator-photo.py',str(image)],timeout=60)
            command(['xcrun','simctl','addmedia',device,str(image)],timeout=120)
            manifest['synthetic_media_seeded']=True
        manifest['stage']='test';manifest['test_start_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
        cmd=['xcodebuild','-project','Kin.xcodeproj','-scheme','Kin','-destination','platform=iOS Simulator,id='+device,
             '-derivedDataPath',str(root/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO',
             '-collect-test-diagnostics','never','-test-timeouts-enabled','YES','-default-test-execution-time-allowance','240',
             '-maximum-test-execution-time-allowance','600','-only-testing:'+CASES[mode],'clean','test','CODE_SIGNING_ALLOWED=NO']
        proc=subprocess.Popen(cmd,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True)
        try: raw,_=proc.communicate(timeout=1200)
        except subprocess.TimeoutExpired:
            import signal
            os.killpg(proc.pid,signal.SIGINT)
            try: raw,_=proc.communicate(timeout=20)
            except subprocess.TimeoutExpired: os.killpg(proc.pid,signal.SIGKILL);raw,_=proc.communicate()
            manifest['test_timeout']=True
        manifest['xcodebuild_exit']=proc.returncode
        # Raw XCTest output is deliberately not retained or printed.
        friend=[]
        for line in raw.splitlines():
            match=re.search(r'KIN_CI_FRIEND (before|after) keyboard=(true|false) wrapper=(on|off|unknown) control=(on|off|unknown) hittable=(true|false)',line)
            if match: friend.append({'stage':match[1],'keyboard':match[2]=='true','wrapper':match[3], 'control':match[4], 'hittable':match[5]=='true'})
        (out/'friend-state.json').write_text(json.dumps(friend,indent=2)+'\n')
        manifest['stage']='result';save()
        if result.is_dir():
            summary=json.loads(command(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],timeout=60).stdout)
            tree=json.loads(command(['xcrun','xcresulttool','get','test-results','tests','--path',str(result)],timeout=60).stdout)
            ids=test_identities(tree)
            if ids != [CASES[mode]]: raise ValueError('Result identity mismatch')
            counts=finalized_counts(summary)
            failures=[]
            import hashlib
            for failure in summary.get('testFailures',[]):
                text=failure.get('failureText','') if isinstance(failure,dict) else ''
                if not isinstance(text,str): text=''
                failures.append({'category':failure_category(text),'text_sha256':hashlib.sha256(text.encode()).hexdigest()})
            manifest['result']={'identities':ids,'counts':counts,'failures':failures}
            manifest['status']='finalized'
        manifest['stage']='collect';save()
        logs=command(['xcrun','simctl','spawn',device,'log','show','--last','60m','--style','ndjson','--predicate',
                      'subsystem == "com.kin.synthetic.control" OR subsystem == "com.kin.synthetic.marker"'],timeout=120)
        events=[]
        for line in logs.stdout.splitlines():
            try: event=sanitize_event(json.loads(line))
            except ValueError: continue
            if event: events.append(event)
        events.sort(key=lambda e:e['uptime_ms'])
        (out/'events.json').write_text(json.dumps(events,indent=2)+'\n')
        manifest['collector']='calibrated_window' if calibrate(events,mode) else 'incomplete_or_uncalibrated'
        manifest['interpretation_limit']='Absence of a record alone does not prove absence of delivery or state change.'
        save()
    finally:
        if device:
            for action in ('shutdown','delete'):
                try: manifest['cleanup'][action]='success' if command(['xcrun','simctl',action,device],timeout=60,check=False).returncode==0 else 'failed'
                except (OSError,subprocess.TimeoutExpired): manifest['cleanup'][action]='error'
            try:
                data=json.loads(command(['xcrun','simctl','list','devices','-j'],timeout=60).stdout)
                present=any(v.get('udid')==device for group in data.get('devices',{}).values() for v in group)
                manifest['cleanup']['inventory']='present' if present else 'absent'
            except (OSError,ValueError,subprocess.SubprocessError): manifest['cleanup']['inventory']='unknown'
        save()
    if manifest['status']!='finalized' or manifest['collector']!='calibrated_window': return 1
    if manifest['cleanup'].get('delete')!='success' or manifest['cleanup'].get('inventory')!='absent': return 1
    counts=manifest['result']['counts']
    return 0 if manifest['xcodebuild_exit']==0 and counts['passedTests']==1 and counts['failedTests']==0 and counts['skippedTests']==0 and counts['expectedFailures']==0 else 1


if __name__ == '__main__':
    try:
        if len(sys.argv)!=2: raise ValueError('Expected friend or clear')
        sys.exit(run_diagnostic(sys.argv[1]))
    except Exception as exc:
        # No raw output, names, paths or command arguments in public logs.
        print('Synthetic diagnostic incomplete:',type(exc).__name__,file=sys.stderr)
        sys.exit(1)
