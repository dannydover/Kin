"""Sanitized, first-request-only metadata from an owned synthetic simulator.

Never reads process arguments/environments or copies crash dumps. Incident parsing
stops before thread/stack data and retains only allowlisted identity/numeric codes.
No sudo, task-port requests, permission grants or broad process-detail snapshots.
"""
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import queue
import re
import subprocess
import threading
import time

CONTACT_NAME = re.compile(r'(?:Contacts?[A-Za-z0-9_.-]*|contacts[A-Za-z0-9_.-]*|CNUI[A-Za-z0-9_.-]*)\Z')
SAFE_TOKEN = re.compile(r'[A-Za-z0-9_.-]{1,160}\Z')
SAFE_TIME = re.compile(r'[0-9T :.+Z-]{10,40}\Z')
MIN_ENV = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL': 'C', 'TZ': 'UTC'}


def allowed_image(image, device):
    path = str(image)
    name = Path(path).name
    if name == 'Kin':
        return 'Kin' if device in path and path.endswith('/Kin.app/Kin') else None
    if not CONTACT_NAME.fullmatch(name):
        return None
    if '/RuntimeRoot/System/Library/' in path or '/RuntimeRoot/Applications/' in path:
        return 'AppleContacts'
    if path.startswith('/System/Library/') or path.startswith('/Applications/'):
        return 'AppleContacts'
    return None


def incident_prefix(path):
    """Read bounded metadata only, never the threads/stacks portion of an .ips."""
    with path.open() as source:
        header_line = source.readline(8193)
        if len(header_line) > 8192:
            return None
        header = json.loads(header_line)
        prefix = []
        size = 0
        while True:
            line = source.readline(65537 - size)
            if not line:
                return None
            if re.match(r'^\s*"threads"\s*:', line):
                text = ''.join(prefix).rstrip().rstrip(',') + '\n}'
                return header, json.loads(text)
            size += len(line)
            if size > 65536:
                return None
            prefix.append(line)
        return None


def incident_fields(header, data, identity):
    """No raw reasons, paths, frames, arguments, user fields or account IDs."""
    result = {'kind': 'incident', 'pid': identity['pid'], 'component': identity['component']}
    stamp = str(data.get('captureTime', header.get('timestamp', '')))
    if SAFE_TIME.fullmatch(stamp):
        result['capture_time'] = stamp
    for section, names in [('exception', ('type', 'signal')), ('termination', ('namespace',))]:
        value = data.get(section, {})
        if not isinstance(value, dict):
            continue
        for name in names:
            token = value.get(name)
            if isinstance(token, str) and re.fullmatch(r'[A-Z0-9_]{1,40}', token):
                result[section + '_' + name] = token
    termination = data.get('termination', {})
    if isinstance(termination, dict) and type(termination.get('code')) is int:
        result['termination_code'] = termination['code']
    bug = str(header.get('bug_type', ''))
    if re.fullmatch(r'[0-9]{1,5}', bug):
        result['bug_type'] = int(bug)
    incident = str(data.get('incident', header.get('incident_id', '')))
    if re.fullmatch(r'[A-Fa-f0-9-]{36}', incident):
        result['incident_ref'] = hashlib.sha256(incident.encode()).hexdigest()[:16]
    return result


class Observer:
    def __init__(self, device, public):
        self.device = device
        self.public = public
        self.start = None
        self.completion = None
        self.manager = None
        self.runtime = None
        self.identities = {}
        self.alive = {}
        self.starts = {}
        self.names = {'contactsd', 'contactsdonationagent', 'Kin'}
        self.bundle_ids = {}
        self.seen_incidents = set()
        self.candidates = queue.Queue(maxsize=128)
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.status = {'manager': 'unavailable', 'process_access': 'not_started',
                       'incident_access': 'not_started', 'unverified_candidates': 0,
                       'missing_pid_fields': 0, 'rows': 0, 'incident_rows': 0,
                       'coverage': 'allowlisted names/log PIDs only; silent or fast-lived processes may be missed'}
        self.output = (public / 'process-metadata.jsonl').open('w')
        try:
            r = self.command(['xcrun', 'simctl', 'spawn', device, 'launchctl', 'managerpid'])
            if r is not None and r.returncode == 0 and r.stdout.strip().isdigit():
                candidate = int(r.stdout.strip())
                if candidate > 1:
                    self.manager = candidate
                    self.status['manager'] = 'owned_simulator_namespace_verified'
                else:
                    self.status['manager'] = 'unavailable_host_namespace_rejected'
            runtimes = self.command(['xcrun', 'simctl', 'list', 'runtimes', '-j'])
            if runtimes is not None and runtimes.returncode == 0:
                items = json.loads(runtimes.stdout)['runtimes']
                item = next(x for x in items if x['identifier'] == 'com.apple.CoreSimulator.SimRuntime.iOS-27-0')
                self.runtime = Path(item['bundlePath']) / 'Contents/Resources/RuntimeRoot'
                roots = [self.runtime / 'Applications', self.runtime / 'System/Library/Frameworks/ContactsUI.framework/PlugIns',
                         self.runtime / 'System/Library/Frameworks/ContactsUI.framework/XPCServices']
                for root in roots:
                    for suffix in ('*.app', '*.appex', '*.xpc'):
                        for bundle in root.glob(suffix):
                            if not CONTACT_NAME.fullmatch(bundle.stem):
                                continue
                            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
                            name, identifier = info.get('CFBundleExecutable', ''), info.get('CFBundleIdentifier', '')
                            if CONTACT_NAME.fullmatch(name) and identifier.startswith('com.apple.') and SAFE_TOKEN.fullmatch(identifier):
                                self.names.add(name)
                                self.bundle_ids[name] = identifier
        except PermissionError:
            self.status['inventory'] = 'blocked_access_denied_no_retry_or_escalation'
        except (OSError, ValueError, KeyError, StopIteration):
            self.status['inventory'] = 'partial_or_unavailable'
        self.thread = threading.Thread(target=self.safe_loop, daemon=True)
        self.thread.start()

    def command(self, args, section='process_access'):
        if self.status[section].startswith('blocked'):
            return None
        try:
            r = subprocess.run(args, capture_output=True, text=True, timeout=3,
                               env=MIN_ENV if args[0] in ('/bin/ps', '/usr/bin/pgrep', '/usr/bin/vm_stat', '/usr/sbin/sysctl') else None)
            if any(word in r.stderr.lower() for word in ('not permitted', 'permission denied', 'not allowed')):
                self.status[section] = 'blocked_access_denied_no_retry_or_escalation'
                return None
            return r
        except (OSError, subprocess.TimeoutExpired):
            self.status[section] = 'unavailable_no_escalation'
            return None

    def emit(self, row):
        with self.lock:
            self.output.write(json.dumps(row) + '\n')
            self.output.flush()
            self.status['rows'] += 1

    def owned(self, pid):
        if self.manager is None:
            return False
        for _ in range(12):
            if pid == self.manager:
                return True
            r = self.command(['/bin/ps', '-p', str(pid), '-o', 'ppid='])
            if r is None or r.returncode or not r.stdout.strip().isdigit():
                return False
            pid = int(r.stdout.strip())
            if pid <= 1:
                return False
        return False

    def identify(self, pid):
        if pid in self.identities:
            return self.identities[pid]
        if not self.owned(pid):
            self.status['unverified_candidates'] += 1
            return None
        r = self.command(['/bin/ps', '-p', str(pid), '-o', 'comm='])
        if r is None or r.returncode or not allowed_image(r.stdout.strip(), self.device):
            return None
        name = Path(r.stdout.strip()).name
        if name not in self.names:
            return None
        row = {'kind': 'identity', 'wall': time.time(), 'pid': pid, 'component': name,
               'scope': 'owned_simulator_launchd_descendant'}
        if name in self.bundle_ids:
            row['bundle_id'] = self.bundle_ids[name]
        self.identities[pid] = row
        self.alive[pid] = True
        self.emit(row)
        return row

    def on_event(self, record, safe):
        payload = safe.get('direct') if safe else None
        if payload and payload['event'] == 'container.beforePresent' and self.start is None:
            self.start = payload['wall']
        if payload and payload['event'] == 'container.presentCompletion' and self.completion is None:
            self.completion = payload['wall']
        if not self.active():
            return
        pid = record.get('processID')
        if type(pid) is not int:
            self.status['missing_pid_fields'] += 1
            return
        if not allowed_image(record.get('processImagePath', ''), self.device):
            return
        try:
            self.candidates.put_nowait(pid)
        except queue.Full:
            self.status['candidate_queue_full'] = True
        identity = self.identities.get(pid)
        if safe is not None and identity:
            safe['process_ref'] = {'pid': pid, 'component': identity['component']}

    def active(self):
        if self.start is None:
            return False
        end = min(self.start + 45, self.completion + 10 if self.completion else self.start + 45)
        return self.start - 1 <= time.time() <= end

    def sample(self, pid):
        r = self.command(['/bin/ps', '-p', str(pid), '-o', 'pid=,ppid=,%cpu=,rss=,state=,lstart='])
        if r is None:
            return
        if r.returncode or not r.stdout.strip():
            if self.alive.get(pid):
                self.emit({'kind': 'not_observed_alive', 'wall': time.time(), 'pid': pid,
                           'meaning': 'exit_or_sampling_gap; no exit code available'})
                self.alive[pid] = False
            return
        try:
            fields = r.stdout.strip().split(maxsplit=5)
            start = datetime.datetime.strptime(fields[5], '%a %b %d %H:%M:%S %Y').replace(tzinfo=datetime.timezone.utc).timestamp()
            cpu = float(fields[2]); rss = int(fields[3]); parent = int(fields[1])
            if not math.isfinite(cpu) or not 0 <= cpu <= 10000 or not 0 <= rss < 2**50:
                return
            if pid in self.starts and self.starts[pid] != start:
                self.emit({'kind': 'pid_reuse_detected', 'wall': time.time(), 'pid': pid})
                self.identities.pop(pid, None)
                self.alive.pop(pid, None)
                self.starts.pop(pid, None)
                return
            self.starts[pid] = start
            self.emit({'kind': 'resource', 'wall': time.time(), 'pid': pid, 'parent_pid': parent,
                       'start_epoch_1s_resolution': start, 'cpu_percent': cpu, 'rss_kib': rss,
                       'state': fields[4][0] if fields[4][0] in 'RSITZUE' else 'other'})
            self.alive[pid] = True
        except (ValueError, IndexError):
            self.status['resource_parse'] = 'unavailable'

    def aggregate(self):
        r = self.command(['/usr/sbin/sysctl', '-n', 'vm.loadavg'])
        if r is not None and r.returncode == 0:
            values = re.findall(r'[0-9]+\.[0-9]+', r.stdout)
            if len(values) == 3:
                self.emit({'kind': 'vm_load', 'wall': time.time(), 'averages': [float(x) for x in values]})

    def incidents(self):
        if self.start is None or self.status['incident_access'].startswith('blocked'):
            return
        roots = [Path.home() / 'Library/Logs/DiagnosticReports',
                 Path.home() / ('Library/Logs/CoreSimulator/' + self.device),
                 Path.home() / ('Library/Developer/CoreSimulator/Devices/' + self.device + '/data/Library/Logs/CrashReporter')]
        try:
            for root in roots:
                for name in {x['component'] for x in self.identities.values()}:
                    for path in root.glob(name + '*.ips'):
                        if path in self.seen_incidents or path.stat().st_mtime < self.start - 2:
                            continue
                        self.seen_incidents.add(path)
                        parsed = incident_prefix(path)
                        if parsed is None:
                            continue
                        header, data = parsed
                        pid = data.get('pid'); identity = self.identities.get(pid)
                        if not identity or data.get('procName') != identity['component']:
                            continue
                        parent = data.get('parentPid')
                        if self.device not in str(data.get('procPath', '')) and not (type(parent) is int and self.owned(parent)):
                            continue
                        stamp = str(data.get('captureTime', header.get('timestamp', '')))
                        try:
                            captured = datetime.datetime.fromisoformat(stamp.replace('Z', '+00:00')).timestamp()
                        except ValueError:
                            continue
                        if not self.start - 2 <= captured <= self.start + 48:
                            continue
                        self.emit(incident_fields(header, data, identity))
                        self.status['incident_rows'] += 1
            self.status['incident_access'] = 'bounded_metadata_scan_completed'
        except PermissionError:
            self.status['incident_access'] = 'blocked_access_denied_no_retry_or_escalation'
        except (OSError, ValueError):
            self.status['incident_parse'] = 'partial_or_unavailable'

    def safe_loop(self):
        try:
            self.loop()
        except Exception as error:
            self.status['worker_error_type'] = type(error).__name__

    def loop(self):
        tick = 0
        while not self.stop.wait(1):
            if not self.active() or self.manager is None or self.status['process_access'].startswith('blocked'):
                continue
            if tick % 2 == 0:
                for name in sorted(self.names):
                    if not self.active() or self.stop.is_set():
                        break
                    r = self.command(['/usr/bin/pgrep', '-x', name])
                    if r is not None:
                        for value in r.stdout.split():
                            if value.isdigit():
                                self.identify(int(value))
            while not self.candidates.empty():
                self.identify(self.candidates.get_nowait())
            for pid in list(self.identities):
                if not self.active() or self.stop.is_set():
                    break
                self.sample(pid)
            if not self.status['process_access'].startswith('blocked'):
                self.aggregate()
            if tick % 2 == 0:
                self.incidents()
            self.status['process_access'] = 'scoped_sampling_completed' if not self.status['process_access'].startswith('blocked') else self.status['process_access']
            tick += 1

    def finish(self):
        self.stop.set()
        self.thread.join(timeout=30)
        if not self.thread.is_alive():
            self.incidents()
            self.output.close()
        self.status.update({'worker_stopped': not self.thread.is_alive(), 'window_start': self.start,
                            'presentation_completion': self.completion, 'verified_identities': len(self.identities),
                            'sample_window_max_seconds': 45,
                            'allowlisted_component_names': sorted(self.names),
                            'scope_manager_pid': self.manager, 'post_completion_seconds': 10})
        return self.status
