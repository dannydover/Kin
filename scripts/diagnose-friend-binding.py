#!/usr/bin/env python3
"""Synthetic isolated diagnostic; allowlisted progress, never release validation."""
import datetime, hashlib, importlib.util, json, os, platform, re, select, signal, subprocess, sys, time, zipfile
from pathlib import Path
ROOT=Path(os.environ['RUNNER_TEMP'])/'KinFriendEvent'; OUT=ROOT/'public'; OUT.mkdir(parents=True,exist_ok=True)
ENV={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','HOME':os.environ['HOME'],'TMPDIR':str(ROOT),'DEVELOPER_DIR':'/Applications/Xcode_27.app/Contents/Developer','LANG':'en_US.UTF-8','LC_ALL':'en_US.UTF-8','NSUnbufferedIO':'YES'}
APP='b9bd5e8ae1b14556d19a1f992a746fc0a529c684'
spec=importlib.util.spec_from_file_location('shards','scripts/ci-test-shards.py'); shards=importlib.util.module_from_spec(spec);spec.loader.exec_module(shards)

def parse(line, allowed):
    m=re.search(r"Test Case '-\[(\w+)\.(\w+) (test\w+)\]' (started|passed|failed)",line)
    if m:
        ident=f'{m[1]}/{m[2]}/{m[3]}'
        return {'kind':'test','id':ident,'event':m[4]} if ident in allowed else None
    m=re.search(r'KIN_(?:FRIEND_DIAG|CI_FRIEND) (before|after) keyboard=(true|false) wrapper=(on|off|unknown) control=(on|off|unknown) hittable=(true|false)',line)
    if m:return {'kind':'friend','stage':m[1],'keyboard':m[2]=='true','wrapper':m[3],'control':m[4],'hittable':m[5]=='true'}
    m=re.search(r'KIN_PHOTOS_DIAG ready15=(true|false) ready45=(true|false)',line)
    if m:return {'kind':'photos','ready15':m[1]=='true','ready45':m[2]=='true'}
    if re.search(r'\bt =\s*[0-9.]+s',line):
        for pattern,label in [(r'\bTap ', 'tap'),(r'\bDouble tap ', 'double_tap'),(r'\bWaiting ', 'wait'),(r'\bSwipe ', 'swipe'),(r'\bType ', 'type'),(r'\bLaunch ', 'launch'),(r'\bTerminate ', 'terminate'),(r'\bChecking existence', 'exists'),(r'\bSynthesize event', 'synthesize'),(r'\bWait for .* idle', 'idle')]:
            if re.search(pattern,line):return {'kind':'action','stage':label}
    return None

def save_record(f, data):
    f.write(json.dumps(data,separators=(',',':'))+'\n');f.flush();os.fsync(f.fileno())

def retain(result, target):
    if not (result/'Info.plist').is_file():return None
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,allowZip64=True) as z:
        for p in sorted(result.rglob('*')):
            if p.is_symlink():raise RuntimeError('symlink')
            if p.is_file():z.write(p,Path(result.name)/p.relative_to(result))
    with zipfile.ZipFile(target) as z:
        if z.testzip() or result.name+'/Info.plist' not in z.namelist():raise RuntimeError('invalid_zip')
    return hashlib.sha256(target.read_bytes()).hexdigest()

def main():
    mode=sys.argv[1];assert mode in ('ui2','friend','preflight')
    ids=shards.selections('ui-1') if mode=='ui2' else ['KinUITests/KinUITests/testBlankNameEditsCancelAndLaterNamingPreserveEntry']
    allowed=set(ids);manifest={'purpose':'one full ordered UI-1 touch and binding diagnostic, not required CI','mode':mode,'expected_tests':len(ids),'status':'preflight','runner_contacts_grant':False,'retention':'pending','authorization':'unknown','cleanup':{}}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    device=None; proc=None; result=ROOT/(mode+'.xcresult')
    def stage(name):
        manifest['stage']=name
        (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    try:
        stage('verify_toolchain')
        assert subprocess.check_output(['xcodebuild','-version'],text=True).strip()=='Xcode 27.0\nBuild version 27A266a'
        assert platform.machine()=='arm64' and subprocess.check_output(['git','rev-parse','HEAD:Kin'],text=True).strip()==APP
        stage('verify_runtime')
        runtimes=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','-j'],text=True))['runtimes'];assert any(x['identifier']=='com.apple.CoreSimulator.SimRuntime.iOS-27-0' and x['buildversion']=='24A434' and x['isAvailable'] for x in runtimes)
        if mode=='friend':
            p=Path('KinUITests/KinUITests.swift');s=p.read_text();needle='        controls.element.tap()\n        let save = editor.buttons.matching(identifier: "Save")';assert s.count(needle)==1
            block='''        func diagnosticState(_ stage: String) {
            let wrapper = friends.element.value as? String
            let control = controls.element.value as? String
            func state(_ v: String?) -> String { v == "0" ? "off" : v == "1" ? "on" : "unknown" }
            print("KIN_FRIEND_DIAG \\(stage) keyboard=\\(app.keyboards.firstMatch.exists) wrapper=\\(state(wrapper)) control=\\(state(control)) hittable=\\(controls.element.isHittable)")
        }
        diagnosticState("before")
        controls.element.tap()
        diagnosticState("after")
        let save = editor.buttons.matching(identifier: "Save")'''
            p.write_text(s.replace(needle,block))
        if mode in ('ui2','preflight'):
            p=Path('KinUITests/NativeContactsTests.swift'); content=p.read_text()
            marker='    override func setUpWithError() throws { continueAfterFailure = false }'
            observer="""    func testSyntheticRunnerAuthorizationObservation() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        let value: String
        switch status {
        case .notDetermined: value = "notDetermined"
        case .restricted: value = "restricted"
        case .denied: value = "denied"
        case .authorized: value = "authorized"
        case .limited: value = "limited"
        @unknown default: value = "unknown"
        }
        print("KIN_AUTH_OBSERVATION \(value)")
    }
"""
            assert content.count(marker)==1
            p.write_text(content.replace(marker,marker+'\n'+observer))
        if mode=='ui2':
            # Inject only fixed, synthetic boolean state into the nonshipping build.
            p=Path('Kin/Views/PersonEditor.swift'); source=p.read_text()
            source=source.replace('import SwiftUI\n','import SwiftUI\nimport OSLog\n',1)
            before='''                    if selected { draft.connections.insert(connection) } else { draft.connections.remove(connection) }
'''
            after='''                    if connection == .friend { Logger(subsystem: "com.kin.synthetic.binding", category: "friend").notice("KIN_BINDING before selected=\(selected, privacy: .public) present=\(draft.connections.contains(connection), privacy: .public)") }
                    if selected { draft.connections.insert(connection) } else { draft.connections.remove(connection) }
                    if connection == .friend { Logger(subsystem: "com.kin.synthetic.binding", category: "friend").notice("KIN_BINDING after selected=\(selected, privacy: .public) present=\(draft.connections.contains(connection), privacy: .public)") }
'''
            assert source.count(before)==1
            source=source.replace(before,after)
            row='''                Toggle(connection.rawValue.capitalized, isOn: Binding(get: { draft.connections.contains(connection) }, set: { selected in
'''
            # Observe the unmodified row bounds, never storing coordinates.
            row_end='''                }))
            }
        } header: { Text("Your connection") }'''
            decorated='''                }))
                .background {
                    if connection == .friend {
                        GeometryReader { proxy in
                            Color.clear.allowsHitTesting(false)
                                .onAppear { FriendEventProbe.row = proxy.frame(in: .global) }
                                .onChange(of: proxy.frame(in: .global)) { _, frame in FriendEventProbe.row = frame }
                        }
                    }
                }
            }
        } header: { Text("Your connection") }'''
            assert source.count(row)==1 and source.count(row_end)==1
            p.write_text(source.replace(row_end,decorated))
            p=Path('Kin/KinApp.swift'); app=p.read_text()
            app=app.replace('import SwiftUI\n','import SwiftUI\nimport OSLog\nimport ObjectiveC.runtime\n',1)
            marker='struct KinApp: App {\n'
            assert app.count(marker)==1
            app=app.replace(marker,marker+'    init() { FriendEventProbe.install() }\n',1)
            app += r'''

// Diagnostic-only hook: logs fixed booleans for touches inside the synthetic
// Friend row. No coordinates, labels, text or unrelated touch events are logged.
@MainActor enum FriendEventProbe {
    static var row = CGRect.null
    static func install() {
        guard let original = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
              let observer = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.kinDiagnosticSendEvent(_:))) else { return }
        method_exchangeImplementations(original, observer)
    }
}
extension UIApplication {
    @objc dynamic func kinDiagnosticSendEvent(_ event: UIEvent) {
        if event.type == .touches, let touch = event.allTouches?.first,
           touch.phase == .began, let window = touch.window,
           FriendEventProbe.row.contains(touch.location(in: window)) {
            var view = window.hitTest(touch.location(in: window), with: event)
            var onSwitch = false
            while let current = view {
                if current is UISwitch { onSwitch = true }
                view = current.superview
            }
            Logger(subsystem: "com.kin.synthetic.event", category: "friend").notice("KIN_TOUCH inrow=true switch=\(onSwitch, privacy: .public)")
        }
        kinDiagnosticSendEvent(event)
    }
}
'''
            p.write_text(app)
        stage('create_simulator')
        device=subprocess.check_output(['xcrun','simctl','create','Synthetic progress diagnostic','com.apple.CoreSimulator.SimDeviceType.iPhone-17','com.apple.CoreSimulator.SimRuntime.iOS-27-0'],text=True).strip()
        stage('boot_simulator')
        subprocess.run(['xcrun','simctl','boot',device],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=120)
        stage('wait_for_boot')
        subprocess.run(['xcrun','simctl','bootstatus',device,'-b'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=300)
        if mode in ('ui2','preflight'):
            # Match CI's ephemeral test-runner-only grant on this owned synthetic simulator.
            stage('grant_runner_contacts')
            # Match CI: issue one grant with no extra command-specific deadline.
            # The enclosing diagnostic step and job remain bounded.
            grant_start=time.monotonic()
            grant=subprocess.run(['xcrun','simctl','privacy',device,'grant','contacts','com.intriguingideas.KinUITests.xctrunner'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            manifest['grant_exit']=grant.returncode
            manifest['grant_seconds']=round(time.monotonic()-grant_start,1)
            stage('observe_runner_authorization')
            observer_result=ROOT/'authorization.xcresult';observer_log=ROOT/'authorization.log'
            observer_cmd=['xcodebuild','-project','Kin.xcodeproj','-scheme','Kin','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath',str(ROOT/'ObserverDerived'),'-resultBundlePath',str(observer_result),'-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-only-testing:KinUITests/NativeContactsTests/testSyntheticRunnerAuthorizationObservation','test','CODE_SIGNING_ALLOWED=NO']
            with observer_log.open('w') as log:
                observed=subprocess.run(observer_cmd,stdout=log,stderr=log,env=ENV,timeout=600)
            matches=re.findall(r'KIN_AUTH_OBSERVATION (notDetermined|restricted|denied|authorized|limited|unknown)\b',observer_log.read_text(errors='replace'))
            observer_hash=retain(observer_result,OUT/'authorization-xcresult.zip')
            manifest['observer_result_sha256']=observer_hash
            if observed.returncode==0 and observer_hash and len(matches)==1:
                summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(observer_result)],text=True,env=ENV,timeout=60))
                if summary.get('totalTestCount')==1 and summary.get('passedTests')==1 and summary.get('skippedTests')==0:
                    manifest['authorization']=matches[0]
            if manifest['authorization']!='authorized':
                manifest['status']='authorization_not_verified';return 1
            manifest['runner_contacts_grant']=True
            stage('create_synthetic_photo')
            subprocess.run(['python3','scripts/create-simulator-photo.py',str(ROOT/'synthetic.png')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            stage('seed_synthetic_photo')
            subprocess.run(['xcrun','simctl','addmedia',device,str(ROOT/'synthetic.png')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        if mode=='preflight':
            manifest['status']='preflight_complete';manifest['retention']='not_applicable'
            return 0
        cmd=['xcodebuild','-project','Kin.xcodeproj','-scheme','Kin','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath',str(ROOT/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-test-timeouts-enabled','YES','-default-test-execution-time-allowance','240','-maximum-test-execution-time-allowance','600']+['-only-testing:'+i for i in ids]+['clean','test','CODE_SIGNING_ALLOWED=NO']
        stage('run_tests')
        manifest['test_start_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        started=time.monotonic();current=None
        with (OUT/'progress.jsonl').open('w') as out:
            proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=ENV,start_new_session=True,bufsize=0)
            buf=b'';last=0
            while True:
                now=time.monotonic(); elapsed=round(now-started,1)
                if elapsed>=2700:
                    save_record(out,{'kind':'limit','elapsed':elapsed,'test':current});os.killpg(proc.pid,signal.SIGINT)
                    try:proc.wait(timeout=20)
                    except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
                    manifest['timed_out']=True;break
                ready,_,_=select.select([proc.stdout],[],[],1)
                if ready:
                    chunk=os.read(proc.stdout.fileno(),65536)
                    if chunk:
                        buf+=chunk
                        while b'\n' in buf:
                            line,buf=buf.split(b'\n',1); record=parse(line.decode('utf-8','replace'),allowed)
                            if record:
                                if record['kind']=='test':current=record['id'] if record['event']=='started' else None
                                record['elapsed']=elapsed
                                if current and record['kind']!='test':record['test']=current
                                save_record(out,record)
                        if len(buf)>65536:buf=b''
                    elif proc.poll() is not None:break
                if elapsed-last>=15:save_record(out,{'kind':'heartbeat','elapsed':elapsed,'test':current});last=elapsed
                if proc.poll() is not None and not ready:break
        # Collect only allowlisted messages; never retain raw unified logs.
        stage('collect_binding_events')
        events=[]
        try:
            log = subprocess.run(['xcrun','simctl','spawn',device,'log','show','--last','90m','--style','ndjson','--predicate','subsystem == "com.kin.synthetic.binding" OR subsystem == "com.kin.synthetic.event"'],capture_output=True,text=True,timeout=120)
            manifest['binding_log_exit']=log.returncode
            if log.returncode==0:
                for line in log.stdout.splitlines():
                    try: item=json.loads(line)
                    except ValueError: continue
                    match=re.fullmatch(r'KIN_BINDING (before|after) selected=(true|false) present=(true|false)',item.get('eventMessage',''))
                    if match: events.append({'kind':'binding', 'timestamp':item.get('timestamp'), 'stage':match[1], 'selected':match[2]=='true', 'present':match[3]=='true'})
                    touch=re.fullmatch(r'KIN_TOUCH inrow=true switch=(true|false)',item.get('eventMessage',''))
                    if touch: events.append({'kind':'touch', 'timestamp':item.get('timestamp'), 'inrow':True, 'switch':touch[1]=='true'})
        except (subprocess.TimeoutExpired, OSError) as e:
            manifest['binding_log_error']=type(e).__name__
        (OUT/'binding-events.json').write_text(json.dumps(events,indent=2)+'\n')
        manifest['binding_event_count']=len(events)
        manifest['binding_trace_verified']=any(e['kind']=='binding' for e in events)
        manifest['touch_trace_verified']=any(e['kind']=='touch' for e in events)
        manifest['exit']=proc.returncode;manifest['result_sha256']=retain(result,OUT/(mode+'-xcresult.zip'));manifest['retention']='complete' if manifest['result_sha256'] else 'incomplete'
        if manifest['result_sha256']:
            s=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],text=True,env=ENV,timeout=60));manifest['summary']={k:s.get(k) for k in ('totalTestCount','passedTests','failedTests','skippedTests','result')};manifest['status']='finalized'
        else:manifest['status']='incomplete'
    except Exception as e:
        manifest['status']='diagnostic_error';manifest['error_type']=type(e).__name__
        if isinstance(e,subprocess.TimeoutExpired):manifest['timeout_seconds']=e.timeout
    finally:
        if proc and proc.poll() is None:
            os.killpg(proc.pid,signal.SIGKILL);proc.wait()
        if device:
            for action in ('shutdown','delete'):
                try:
                    cleanup=subprocess.run(['xcrun','simctl',action,device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=60)
                    manifest['cleanup'][action]='success' if cleanup.returncode==0 else 'failed'
                except subprocess.TimeoutExpired:manifest['cleanup'][action]='timeout'
            try:
                inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','-j'],text=True,timeout=60))
                found=any(x.get('udid')==device for group in inventory.get('devices',{}).values() for x in group)
                manifest['cleanup']['inventory']='present' if found else 'absent'
            except (subprocess.SubprocessError,ValueError,OSError):manifest['cleanup']['inventory']='unknown'
        (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return 0 if manifest['status'] in ('finalized','preflight_complete') else 1
if __name__=='__main__':sys.exit(main())
