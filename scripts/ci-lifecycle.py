#!/usr/bin/env python3
"""Bounded synthetic simulator launchd states; never retain inventory or PIDs."""
import collections
import json
import os
import re
import signal
import subprocess
import tempfile
import threading
import time
import uuid
from pathlib import Path

LABEL = re.compile(r'^(?:com\.apple\.)?UIKitApplication:com\.intriguingideas\.Kin(?:\[[^\]\r\n]+\])+$|^application<com\.intriguingideas\.Kin>$')


def state(output):
    candidates = []
    for line in output.splitlines():
        fields = line.split(None, 2)
        if len(fields) == 3 and LABEL.fullmatch(fields[2]):
            candidates.append(fields[0])
    if len(candidates) != 1:
        return 'unknown'
    pid = candidates[0]
    if pid == '-':
        return 'absent'
    if pid.isascii() and pid.isdigit() and int(pid) > 0:
        return 'present'
    return 'unknown'


class LifecycleSampler:
    def __init__(self, root, device, interval=15, limit=200, max_seconds=2700):
        if str(uuid.UUID(device)) != device.lower():
            raise ValueError('invalid simulator identifier')
        if not 0 < interval <= 60 or not 0 < limit <= 200 or not 0 < max_seconds <= 2700:
            raise ValueError('invalid observer bounds')
        self.path = Path(root) / 'KinTests-lifecycle.json'
        self.device = device
        self.interval = interval
        self.samples = collections.deque(maxlen=limit)
        self.stopped = threading.Event()
        self.started = time.monotonic()
        self.max_seconds = max_seconds
        self.deadline_reached = False
        self.lock = threading.Lock()
        self.child = None
        self.cleanup_ok = True
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _inventory(self):
        # A private temporary file avoids a pipe held open by another process.
        # Only our own new process group may be stopped on timeout or shutdown.
        with tempfile.TemporaryFile(mode='w+t') as output:
            with self.lock:
                if self.stopped.is_set():
                    return None
                child = subprocess.Popen(['xcrun', 'simctl', 'spawn', self.device, 'launchctl', 'list'],
                                         stdout=output, stderr=subprocess.DEVNULL, start_new_session=True)
                self.child = child
            try:
                if child.wait(timeout=3) != 0:
                    return None
                output.seek(0)
                text = output.read(1_000_001)
                return text if len(text) <= 1_000_000 else None
            except subprocess.TimeoutExpired:
                if not self._stop_child(child):
                    self.cleanup_ok = False
                return None
            finally:
                with self.lock:
                    self.child = None

    @staticmethod
    def _stop_child(child):
        try:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=1)
        except (OSError, subprocess.SubprocessError):
            return False
        return child.poll() is not None

    def _sample(self):
        sample = {'elapsed': round(time.monotonic() - self.started, 1), 'state': 'unknown'}
        try:
            output = self._inventory()
            if output is not None:
                sample['state'] = state(output)
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
        return sample

    def _run(self):
        while not self.stopped.is_set() and time.monotonic() - self.started < self.max_seconds:
            self.samples.append(self._sample())
            try:
                self._write_checkpoint(False)
            except OSError:
                pass
            self.stopped.wait(self.interval)
        self.deadline_reached = not self.stopped.is_set()

    def _write_checkpoint(self, complete):
        temporary = self.path.with_suffix('.tmp')
        try:
            temporary.write_text(json.dumps({'version': 1, 'interval_seconds': self.interval,
                'deadline_reached': self.deadline_reached, 'complete': complete,
                'samples': list(self.samples)}, separators=(',', ':')) + '\n')
            os.replace(temporary, self.path)
        finally:
            temporary.unlink(missing_ok=True)

    def start(self):
        self.path.unlink(missing_ok=True)
        self.thread.start()

    def finish(self, failed):
        self.stopped.set()
        self.thread.join(timeout=5)
        if self.thread.is_alive():
            with self.lock:
                child = self.child
            if child is not None and not self._stop_child(child):
                self.cleanup_ok = False
            self.thread.join(timeout=2)
        complete = not self.thread.is_alive() and self.cleanup_ok
        if failed and not self.thread.is_alive():
            self._write_checkpoint(complete)
        elif complete:
            self.path.unlink(missing_ok=True)
        return complete
