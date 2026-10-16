#!/usr/bin/env python3
"""Bound one owned build/probe; stream only validated synthetic progress."""
import importlib.util
import json
import os
import selectors
import signal
import subprocess
import sys
import time
from pathlib import Path

spec = importlib.util.spec_from_file_location('edit_safety', Path(__file__).with_name('prepare-edit-diagnostic-artifact.py'))
safety = importlib.util.module_from_spec(spec)
spec.loader.exec_module(safety)
METHODS = {'baseline': 'testBaselineBroadEditQuery', 'strict': 'testStrictChildIdentityCandidate',
           'observe': 'testObserveInheritedParentAction'}

def emit(event, **fields):
    print('KIN_EDIT_RUN ' + json.dumps({'event': event, **fields}, sort_keys=True), flush=True)

def group_exists(identifier):
    try:
        os.killpg(identifier, 0)
        return True
    except ProcessLookupError:
        return False

def cleanup_owned_group(identifier, grace=1):
    sent_term = sent_kill = False
    if group_exists(identifier):
        try:
            os.killpg(identifier, signal.SIGTERM)
            sent_term = True
        except ProcessLookupError:
            pass
        until = time.monotonic() + grace
        while group_exists(identifier) and time.monotonic() < until:
            time.sleep(0.05)
        if group_exists(identifier):
            try:
                os.killpg(identifier, signal.SIGKILL)
                sent_kill = True
            except ProcessLookupError:
                pass
    return {'termSent': sent_term, 'killSent': sent_kill}

def supervise(command, raw_log, events_log, phase, deadline, grace=20):
    started = time.monotonic()
    environment = dict(os.environ, NSUnbufferedIO='YES')
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               start_new_session=True, env=environment)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    pending = b''
    timed_out, rejected, next_heartbeat, kill_at, term_at = False, 0, started, None, None
    owner_exited_at, drain_truncated = None, False
    body_started, body_completed, last_stage = False, False, None
    def signal_owned(kind):
        try:
            os.killpg(process.pid, kind)
        except ProcessLookupError:
            pass
    emit('started', phase=phase, deadlineSeconds=deadline)
    with raw_log.open('wb') as raw, events_log.open('w') as events:
        def line_received(data):
            nonlocal rejected, body_started, body_completed, last_stage
            line = data.decode('utf-8', errors='replace')
            for marker, validator in [('KIN_EDIT_DIAGNOSTIC ', safety.validate_observation),
                                       ('KIN_EDIT_PROGRESS ', safety.validate_progress)]:
                if marker in line:
                    try:
                        record = validator(json.loads(line.split(marker, 1)[1]))
                        if marker == 'KIN_EDIT_PROGRESS ':
                            body_started = body_started or record['stage'] == 'started'
                            body_completed = body_completed or record['stage'] == 'completed'
                            last_stage = record['stage']
                        safe = marker + json.dumps(record, sort_keys=True)
                        print(safe, flush=True); events.write(safe + '\n'); events.flush()
                    except (AssertionError, ValueError, TypeError, SyntaxError, KeyError):
                        rejected += 1; emit('rejected-structured-event', phase=phase)
                    return
            if 'Test Case ' in line and 'EditIdentityDiagnosticTests ' in line:
                outcome = 'started' if " started." in line else 'passed' if ' passed (' in line else 'failed' if ' failed (' in line else None
                if outcome:
                    emit('test-' + outcome, phase=phase)
            elif '** TEST BUILD SUCCEEDED **' in line:
                emit('build-completed', phase=phase)
            elif 'error:' in line:
                emit('tool-error-detected', phase=phase)
        while process.poll() is None or selector.get_map():
            now = time.monotonic()
            if now >= next_heartbeat:
                emit('heartbeat', phase=phase, elapsedSeconds=int(now - started))
                next_heartbeat = now + 15
            if not timed_out and now - started >= deadline and process.poll() is None:
                timed_out = True; kill_at = now + grace
                emit('deadline-reached', phase=phase)
                signal_owned(signal.SIGINT)
            if kill_at is not None and now >= kill_at and process.poll() is None:
                emit('terminate-owned-group', phase=phase)
                signal_owned(signal.SIGTERM); kill_at = None; term_at = now + 5
            if term_at is not None and now >= term_at and process.poll() is None:
                emit('kill-owned-group', phase=phase)
                signal_owned(signal.SIGKILL); term_at = None
            for key, _ in selector.select(timeout=0.25):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj); continue
                raw.write(chunk); raw.flush(); pending += chunk
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1); line_received(line)
            # A descendant retaining stdout must not defeat owner completion.
            if process.poll() is not None:
                if owner_exited_at is None:
                    owner_exited_at = time.monotonic()
                elif selector.get_map() and time.monotonic() - owner_exited_at >= 2:
                    drain_truncated = True
                    signal_owned(signal.SIGTERM)
                    break
            if timed_out and process.poll() is not None:
                break
        if pending:
            line_received(pending)
    selector.close()
    code = process.wait()
    group_cleanup = cleanup_owned_group(process.pid)
    process.stdout.close()
    status = {'phase': phase, 'exitCode': code, 'timedOut': timed_out,
              'elapsedSeconds': round(time.monotonic() - started, 2), 'rejectedEvents': rejected,
              'testBodyStarted': body_started, 'testBodyCompleted': body_completed,
              'lastProgressStage': last_stage, 'stdoutDrainTruncated': drain_truncated,
              'ownedGroupCleanup': group_cleanup}
    emit('finished', **status)
    return status

def export_evidence(result, exported):
    if not result.is_dir():
        return {'exitCode': None, 'category': 'result-bundle-missing'}
    try:
        help_result = subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--help'], capture_output=True, text=True, timeout=10)
        if '--output-path' not in help_result.stdout or '--path' not in help_result.stdout:
            return {'exitCode': help_result.returncode, 'category': 'export-command-unsupported'}
        exported_result = subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(exported)], capture_output=True, text=True, timeout=20)
        error = exported_result.stderr + exported_result.stdout
        category = 'exported' if exported_result.returncode == 0 else 'unfinished-result-bundle' if not (result / 'Info.plist').is_file() else 'export-failed'
        return {'exitCode': exported_result.returncode, 'category': category}
    except subprocess.TimeoutExpired:
        return {'exitCode': None, 'category': 'export-deadline'}

def live_directory(simulator):
    if not simulator:
        return None
    try:
        found = subprocess.run(['xcrun', 'simctl', 'get_app_container', simulator, 'com.intriguingideas.KinUITests.xctrunner', 'data'], capture_output=True, text=True, timeout=10)
        if found.returncode == 0:
            container = Path(found.stdout.strip())
            candidate = container / 'tmp' / 'KinEditDiagnostic'
            if container.is_absolute() and candidate.resolve().is_relative_to(container.resolve()) and not candidate.is_symlink():
                return candidate
    except subprocess.TimeoutExpired:
        pass
    return None

def retain(root, phase, simulator, status):
    status['export'] = export_evidence(root / 'result.xcresult', root / 'export')
    emit('export-status', phase=phase, **status['export'])
    reviewed = root / 'reviewed'
    try:
        status['filter'] = safety.prepare(root / 'safe-events.log', root / 'export', reviewed,
                                          live=live_directory(simulator) if phase != 'build' else None, phase=phase)
    except (AssertionError, ValueError, TypeError, SyntaxError, KeyError, OSError):
        # Only individually validated files can have been copied before a failure.
        reviewed.mkdir(parents=True, exist_ok=True)
        status['filter'] = {'category': 'filter-failed'}
        emit('filter-failed', phase=phase)
    (reviewed / 'run-status.json').write_text(json.dumps(status, indent=2) + '\n')
    return status

def collect(simulator, directory):
    directory.mkdir(parents=True, exist_ok=True)
    statuses = []
    for phase in ['build', *METHODS]:
        root = directory / phase
        if not root.is_dir():
            statuses.append({'phase': phase, 'category': 'phase-not-started'})
            continue
        saved = root / 'reviewed' / 'run-status.json'
        if not saved.exists():
            retain(root, phase, simulator, {'phase': phase, 'exitCode': None, 'timedOut': True,
                                            'category': 'step-ended-before-finalization'})
        statuses.append(json.loads(saved.read_text()))
    (directory / 'summary.json').write_text(json.dumps(statuses, indent=2) + '\n')
    emit('partial-evidence-collected', phases=len(statuses))

def main():
    phase, simulator, directory = sys.argv[1:4]
    if phase == 'collect':
        collect(simulator, Path(directory))
        return 0
    assert phase in {'build', *METHODS}
    import uuid
    uuid.UUID(simulator)
    root = Path(directory); root.mkdir(parents=True, exist_ok=False)
    raw, event_log, result = root / 'raw.log', root / 'safe-events.log', root / 'result.xcresult'
    command = ['xcodebuild', '-project', 'Kin.xcodeproj', '-scheme', 'Kin', '-destination', 'platform=iOS Simulator,id=' + simulator,
               '-derivedDataPath', 'DerivedData', '-parallel-testing-enabled', 'NO']
    if phase == 'build':
        command += ['build-for-testing', 'CODE_SIGNING_ALLOWED=NO']
    else:
        command += ['-resultBundlePath', str(result), '-only-testing:KinUITests/EditIdentityDiagnosticTests/' + METHODS[phase],
                    '-collect-test-diagnostics', 'never', '-test-timeouts-enabled', 'YES',
                    '-default-test-execution-time-allowance', '240', '-maximum-test-execution-time-allowance', '600',
                    'test-without-building', 'CODE_SIGNING_ALLOWED=NO']
    status = supervise(command, raw, event_log, phase, 240 if phase == 'build' else 150, grace=15)
    retain(root, phase, simulator, status)
    # Only the owned simulator's runner/app are terminated after evidence harvesting.
    if phase != 'build':
        for bundle in ['com.intriguingideas.KinUITests.xctrunner', 'com.intriguingideas.Kin']:
            try:
                subprocess.run(['xcrun', 'simctl', 'terminate', simulator, bundle], capture_output=True, timeout=5)
            except subprocess.TimeoutExpired:
                pass
    if status['timedOut']:
        return 124
    if status['exitCode']:
        return status['exitCode']
    if phase != 'build' and not (status['testBodyStarted'] and status['testBodyCompleted']):
        return 3
    if status['rejectedEvents'] or status['filter'].get('rejectedItems') or status['filter'].get('category') == 'filter-failed':
        return 2
    return 0

if __name__ == '__main__':
    sys.exit(main())
