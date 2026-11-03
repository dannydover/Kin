#!/usr/bin/env python3
"""Bounded aggregate CPU-counter preflight; no process data is collected."""
import ctypes
import json
import os
import subprocess
import sys
import time

INTERVAL_SECONDS = 5


def busy_ratio(before, after, elapsed, cpus, ticks_per_second):
    if (len(before) != 4 or len(after) != 4 or elapsed <= 0 or
            not isinstance(cpus, int) or cpus < 1 or ticks_per_second <= 0):
        return None
    delta = [(end - start) & 0xffffffff for start, end in zip(before, after)]
    total = sum(delta)
    expected = elapsed * cpus * ticks_per_second
    if total <= 0 or not 0.7 <= total / expected <= 1.3:
        return None
    return round((total - delta[2]) * 100 / total, 1)


def read_ticks():
    lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    lib.mach_host_self.restype = ctypes.c_uint
    lib.host_statistics.argtypes = [ctypes.c_uint, ctypes.c_int,
                                    ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint)]
    host = lib.mach_host_self()
    values = (ctypes.c_uint * 4)()
    count = ctypes.c_uint(4)
    if lib.host_statistics(host, 3, values, ctypes.byref(count)) or count.value != 4:
        raise RuntimeError('counter unavailable')
    return list(values)


def measure():
    before = read_ticks()
    started = time.monotonic()
    time.sleep(INTERVAL_SECONDS)
    after = read_ticks()
    duration = time.monotonic() - started
    return busy_ratio(before, after, duration, os.cpu_count(), os.sysconf('SC_CLK_TCK'))


def main():
    child = None
    try:
        baseline = measure()
        # A single short-lived, owned worker creates a known synthetic load.
        child = subprocess.Popen([sys.executable, '-c',
            'import time\nend=time.monotonic()+7\nwhile time.monotonic()<end: pass'])
        loaded = measure()
        if baseline is None or loaded is None:
            result = {'status': 'unavailable', 'reason': 'counter_scope_or_values'}
        else:
            result = {'status': 'ok', 'logical_cpu_count': os.cpu_count(),
                      'interval_seconds': INTERVAL_SECONDS,
                      'baseline_busy_percent': baseline, 'loaded_busy_percent': loaded}
    except (OSError, ValueError, RuntimeError):
        result = {'status': 'unavailable', 'reason': 'measurement_error'}
    finally:
        if child is not None:
            if child.poll() is None:
                child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    print(json.dumps(result, separators=(',', ':')))
    return 0 if result['status'] == 'ok' else 1


if __name__ == '__main__':
    sys.exit(main())
