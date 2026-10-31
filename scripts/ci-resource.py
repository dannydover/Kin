#!/usr/bin/env python3
"""Bounded aggregate host samples; retained only when the suite fails."""
import collections
import json
import os
import re
import subprocess
import threading
import time
from pathlib import Path

class ResourceSampler:
    def __init__(self, root, interval=10, limit=180):
        self.path = Path(root) / 'KinTests-resource.json'
        self.interval = interval
        self.samples = collections.deque(maxlen=limit)
        self.stopped = threading.Event()
        self.started = time.monotonic()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _sample(self):
        sample = {'elapsed': round(time.monotonic() - self.started, 1)}
        try:
            sample['load_1m'] = round(os.getloadavg()[0], 2)
        except OSError:
            sample['load_1m'] = None
        # vm_stat returns only aggregate page counters; never retain raw output.
        try:
            output = subprocess.run(['vm_stat'], capture_output=True, text=True,
                                    timeout=2, check=True).stdout
            header = re.search(r'page size of (\d+) bytes', output)
            free = re.search(r'^Pages free:\s*(\d+)\.', output, re.MULTILINE)
            inactive = re.search(r'^Pages inactive:\s*(\d+)\.', output, re.MULTILINE)
            if not (header and free and inactive): raise ValueError('missing counters')
            page = int(header.group(1))
            sample['free_bytes'] = int(free.group(1)) * page
            sample['inactive_bytes'] = int(inactive.group(1)) * page
        except (OSError, ValueError, subprocess.SubprocessError):
            sample['free_bytes'] = None
            sample['inactive_bytes'] = None
        return sample

    def _run(self):
        while not self.stopped.is_set():
            self.samples.append(self._sample())
            self.stopped.wait(self.interval)

    def start(self):
        self.path.unlink(missing_ok=True)
        self.thread.start()

    def finish(self, failed):
        self.stopped.set()
        self.thread.join(timeout=4)
        # A still-running collector is reported, never silently considered complete.
        if failed:
            self.path.write_text(json.dumps({'version': 1, 'interval_seconds': self.interval,
                'complete': not self.thread.is_alive(), 'samples': list(self.samples)},
                separators=(',', ':')) + '\n')
