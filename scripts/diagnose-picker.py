#!/usr/bin/env python3
"""One bounded UI-2 prefix diagnostic; never a substitute for required validation.

Raw build/device logs stay on the ephemeral runner. Public evidence contains only
fixed event codes, timestamps, numeric error codes and finalized test counts.
Owner-approved nonshipping app logging only; permissions, assertions and timeouts stay unchanged.
"""
import json
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import threading

SOURCE = '208cb6a1500ccc8f5d0bd4f6be254b36ab9e5f92'
BASELINE_APP_TREE = 'b9bd5e8ae1b14556d19a1f992a746fc0a529c684'
APP_TREE = '4c37021098b5f9549656e6ec2f3b7bff299a4021'
TEST_BLOB = '1f975554f13466a0fd2cb53a8f7c93fe14f723ab'
TEST = 'KinUITests/KinUITests/testNewImportSavesReviewedNamesForEveryEntryPoint'
EVENTS = {
    'viewDidLoad': 'did_load', 'viewWillAppear': 'will_appear',
    'viewDidAppear': 'did_appear', 'viewWillDisappear': 'will_disappear',
    'viewDidDisappear': 'did_disappear', 'delayed appearance timed out': 'appearance_timeout',
    'already presenting': 'presentation_overlap', 'unbalanced': 'unbalanced_transition',
    'present': 'presentation', 'dismiss': 'dismissal', 'invalidat': 'invalidation',
    'connection': 'connection', 'crash': 'crash', 'error': 'error',
}


DIRECT_EVENTS = {'picker.created', 'picker.didSelect', 'picker.didCancel',
    'container.didLoad', 'container.willAppear', 'container.didAppear',
    'container.willDisappear', 'container.didDisappear', 'container.beforePresent',
    'container.afterPresent', 'container.presentCompletion', 'container.snapshot', 'container.dismantle'}
DIRECT_EVENTS.update('picker.' + callback + '.' + edge
    for callback in ('willAppear', 'didAppear', 'willDisappear', 'didDisappear') for edge in ('enter', 'exit'))


def direct_payload(message):
    marker = 'KIN_PICKER_LIFECYCLE '
    if marker not in message:
        return None
    try:
        payload = json.loads(message.split(marker, 1)[1].strip())
    except (TypeError, ValueError):
        return None
    if not isinstance(payload, dict) or set(payload) != {'event', 'wall', 'uptime', 'controller', 'peer'}:
        return None
    if payload['event'] not in DIRECT_EVENTS:
        return None
    if any(type(payload[key]) not in (int, float) for key in ('wall', 'uptime')):
        return None
    for key in ('controller', 'peer'):
        state = payload[key]
        if not isinstance(state, dict) or not set(state) <= {'role', 'id', 'loaded', 'window',
                'beingPresented', 'beingDismissed', 'presentedRole', 'presenterRole', 'transition'}:
            return None
        if state.get('role') not in ('none', 'container', 'picker', 'other'):
            return None
        for name, value in state.items():
            if name in ('role', 'presentedRole', 'presenterRole') and value not in ('none', 'container', 'picker', 'other'):
                return None
            if name == 'id' and (type(value) is not int or not 0 < value < 10000):
                return None
            if name not in ('role', 'presentedRole', 'presenterRole', 'id') and type(value) is not bool:
                return None
    return payload


def sanitized_event(record):
    message = record.get('eventMessage', '')
    if not isinstance(message, str):
        return None
    direct = direct_payload(message)
    codes = sorted({code for token, code in EVENTS.items() if token.lower() in message.lower()})
    if not codes and direct is None:
        return None
    stamp = str(record.get('timestamp', ''))
    if not re.fullmatch(r'[0-9T :.+Z-]{10,40}', stamp):
        stamp = 'unavailable'
    image = str(record.get('processImagePath', ''))
    process = 'Kin' if Path(image).name == 'Kin' else 'Contacts_service_or_framework'
    result = {'timestamp': stamp, 'process': process, 'events': codes}
    if direct is not None:
        result['direct'] = direct
    controllers = [name for name in ('CNContactPickerViewController',
                   '_UIViewServiceRootViewController', 'ContactPicker.Container') if name in message]
    if controllers:
        result['controllers'] = controllers
    error = re.search(r'Error Domain=([A-Za-z0-9._-]+) Code=(-?\d+)', message)
    if error:
        domain, code = error.groups()
        result['error_code'] = int(code)
        if domain in ('NSCocoaErrorDomain', 'NSPOSIXErrorDomain', 'NSOSStatusErrorDomain',
                      'NSMachErrorDomain', 'CNErrorDomain') or domain in ('com.apple.ViewServices', 'com.apple.dt.XCTest.XCTFuture',
                                     'com.apple.dt.xctest.automation-support.error'):
            result['error_domain'] = domain
    return result


def instrument_test():
    path = Path('KinUITests/KinUITests.swift')
    assert subprocess.check_output(['git', 'hash-object', str(path)], text=True).strip() == TEST_BLOB
    text = path.read_text()
    start = text.index('    @MainActor func testNewImportSavesReviewedNamesForEveryEntryPoint()')
    end = text.index('    @MainActor func testChildSurname', start)
    method = text[start:end]
    original = '''            app.buttons["Import from Contacts"].tap()
            XCTAssertTrue(app.navigationBars["Contacts"].waitForExistence(timeout: 10))'''
    replacement = '''            print("KIN_PICKER_DIAGNOSTIC route=\\(index) stage=beforeTap uptime=\\(ProcessInfo.processInfo.systemUptime) wall=\\(Date().timeIntervalSince1970)")
            app.buttons["Import from Contacts"].tap()
            print("KIN_PICKER_DIAGNOSTIC route=\\(index) stage=afterTap uptime=\\(ProcessInfo.processInfo.systemUptime) wall=\\(Date().timeIntervalSince1970)")
            let pickerReady = app.navigationBars["Contacts"].waitForExistence(timeout: 10)
            print("KIN_PICKER_DIAGNOSTIC route=\\(index) stage=afterReadiness uptime=\\(ProcessInfo.processInfo.systemUptime) wall=\\(Date().timeIntervalSince1970) ready=\\(pickerReady)")
            XCTAssertTrue(pickerReady)'''
    assert method.count(original) == 1
    path.write_text(text[:start] + method.replace(original, replacement) + text[end:])


def main():
    root = Path(os.environ['RUNNER_TEMP']) / 'KinPickerDiagnostic'
    public = root / 'public'
    public.mkdir(parents=True)
    manifest = {'purpose': 'diagnostic only; not release validation', 'baseline_source': SOURCE,
                'application_tree': APP_TREE, 'baseline_application_tree': BASELINE_APP_TREE,
                'nonshipping_direct_lifecycle_logging': True, 'test': TEST, 'permission_grants': [],
                'raw_logs_uploaded': False, 'status': 'preflight'}
    spec = importlib.util.spec_from_file_location('shards', 'scripts/ci-test-shards.py')
    shards = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(shards)
    ordered = shards.selections('ui-2')
    selected = ordered[:ordered.index(TEST) + 1]
    assert len(selected) == 10 and selected[-1] == TEST
    manifest['selected_tests_in_original_order'] = selected
    manifest['context'] = 'Original UI2 prefix through import failure; same synthetic Photos preload; no permission grants, no other groups or concurrent full workflow.'
    device = None
    stream = None
    collector = None
    build_code = 1
    def write_manifest():
        (public / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    def run(args, **kwargs):
        return subprocess.run(args, check=True, **kwargs)
    write_manifest()
    try:
        version = subprocess.check_output(['xcodebuild', '-version'], text=True).strip()
        assert version == 'Xcode 27.0\nBuild version 27A266a'
        assert subprocess.check_output(['git', 'rev-parse', 'HEAD:Kin'], text=True).strip() == APP_TREE
        manifest['diagnostic_commit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
        manifest['toolchain'] = version
        instrument_test()
        device = subprocess.check_output(['xcrun', 'simctl', 'create', 'Kin isolated picker diagnostic',
            'com.apple.CoreSimulator.SimDeviceType.iPhone-17',
            'com.apple.CoreSimulator.SimRuntime.iOS-27-0'], text=True).strip()
        with (root / 'boot.log').open('w') as boot:
            run(['xcrun', 'simctl', 'boot', device], stdout=boot, stderr=boot)
            run(['xcrun', 'simctl', 'bootstatus', device, '-b'], stdout=boot, stderr=boot)
            photo = root / 'SyntheticPhoto.png'
            run(['python3', 'scripts/create-simulator-photo.py', str(photo)], stdout=boot, stderr=boot)
            run(['xcrun', 'simctl', 'addmedia', device, str(photo)], stdout=boot, stderr=boot)
        # A newly created simulator contains only its standard fictional cards.
        # Do not warm the store, add cards, grant Contacts access, or open a UI app.
        predicate = 'process == "Kin" OR process CONTAINS[c] "Contacts" OR subsystem BEGINSWITH "com.apple.Contacts"'
        stream_error = (root / 'stream-error.log').open('w')
        stream = subprocess.Popen(['xcrun', 'simctl', 'spawn', device, 'log', 'stream',
            '--style', 'ndjson', '--level', 'debug', '--predicate', predicate],
            stdout=subprocess.PIPE, stderr=stream_error, text=True)
        def collect():
            with (public / 'native-events.jsonl').open('w') as target:
                for line in stream.stdout:
                    try:
                        event = sanitized_event(json.loads(line))
                    except (ValueError, TypeError):
                        continue
                    if event:
                        target.write(json.dumps(event) + '\n')
                        target.flush()
        collector = threading.Thread(target=collect, daemon=True)
        collector.start()
        manifest['status'] = 'running'
        write_manifest()
        command = ['xcodebuild', '-project', 'Kin.xcodeproj', '-scheme', 'Kin', '-configuration', 'Debug',
            '-destination', 'platform=iOS Simulator,id=' + device,
            '-derivedDataPath', str(root / 'DerivedData'), '-resultBundlePath', str(root / 'result.xcresult'),
            '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
            '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '240',
            '-maximum-test-execution-time-allowance', '600']
        command += ['-only-testing:' + name for name in selected]
        command += ['test', 'CODE_SIGNING_ALLOWED=NO',
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG KIN_PICKER_LIFECYCLE_DIAGNOSTIC']
        with (root / 'test.log').open('w') as log:
            build_code = subprocess.run(command, stdout=log, stderr=log).returncode
        markers = []
        pattern = r'KIN_PICKER_DIAGNOSTIC route=[0-3] stage=(?:beforeTap|afterTap|afterReadiness) uptime=[0-9.]+ wall=[0-9.]+(?: ready=(?:true|false))?'
        for line in (root / 'test.log').read_text(errors='replace').splitlines():
            match = re.search(pattern, line)
            if match:
                markers.append(match.group())
        (public / 'test-events.txt').write_text('\n'.join(markers) + '\n')
        manifest['failure_source_locations'] = sorted(set(re.findall(
            r'KinUITests/[A-Za-z0-9_]+\.swift:[0-9]+',
            (root / 'test.log').read_text(errors='replace'))))
        summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get',
            'test-results', 'summary', '--path', str(root / 'result.xcresult')], text=True))
        manifest['summary'] = {key: summary.get(key) for key in
            ('totalTestCount', 'passedTests', 'failedTests', 'skippedTests', 'result')}
        manifest['xcodebuild_exit'] = build_code
        manifest['status'] = 'completed'
        allowed_failures = {name.removeprefix('KinUITests/') for name in selected}
        manifest['failed_tests'] = [failure['testIdentifierString']
            for failure in summary.get('testFailures', [])
            if failure.get('testIdentifierString', '').removesuffix('()') in allowed_failures]
        configs = summary.get('devicesAndConfigurations', [])
        if configs:
            device_summary = configs[0].get('device', {})
            manifest['runtime'] = {key: device_summary.get(key) for key in ('osVersion', 'osBuildNumber', 'modelName')}
        assert summary.get('totalTestCount') == len(selected)
    except Exception as error:
        manifest['status'] = 'diagnostic_error'
        manifest['error_type'] = type(error).__name__
    finally:
        if stream is not None:
            manifest['log_stream_ended_before_test'] = stream.poll() is not None
            stream.terminate()
            try:
                stream.wait(timeout=10)
            except subprocess.TimeoutExpired:
                stream.kill()
                stream.wait()
            collector.join(timeout=10)
            manifest['log_stream_exit'] = stream.returncode
            events = (public / 'native-events.jsonl').read_text().splitlines()
            manifest['native_event_count'] = len(events)
            manifest['controller_event_count'] = sum('controllers' in json.loads(row) for row in events)
            manifest['direct_event_count'] = sum('direct' in json.loads(row) for row in events)
            manifest['probe_observed'] = manifest['direct_event_count'] > 0
        if device is not None:
            subprocess.run(['xcrun', 'simctl', 'shutdown', device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            cleanup = subprocess.run(['xcrun', 'simctl', 'delete', device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            manifest['owned_simulator_removed'] = cleanup.returncode == 0
        write_manifest()
        print(json.dumps(manifest))
    return 0 if manifest['status'] == 'completed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
