#!/usr/bin/env python3
"""Run the fixed source's CI observer against immutable built-for-testing products."""
import importlib.util
import os
import signal
import subprocess
import threading
import sys
from pathlib import Path

source = Path.cwd()
spec = importlib.util.spec_from_file_location('kin_ci_observe', source / 'scripts/ci-observe.py')
observe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observe)
original_popen = subprocess.Popen


def rewrite(command, xctestrun):
    """Reject unexpected commands instead of silently changing test semantics."""
    if not isinstance(command, list) or not command or command[0] != 'xcodebuild':
        return command
    required = ['-project', 'Kin.xcodeproj', '-scheme', 'Kin', '-parallel-testing-enabled', 'NO',
                '-collect-test-diagnostics', 'never', '-test-timeouts-enabled', 'YES',
                '-default-test-execution-time-allowance', '240',
                '-maximum-test-execution-time-allowance', '600']
    if command[1:5] != required[:4] or command[-3:] != ['clean', 'test', 'CODE_SIGNING_ALLOWED=NO']:
        raise ValueError('Unexpected fixed-source CI command')
    def value(flag):
        if command.count(flag) != 1: raise ValueError('Unexpected CI flag')
        return command[command.index(flag)+1]
    if (value('-parallel-testing-enabled') != 'NO' or value('-collect-test-diagnostics') != 'never'
        or value('-test-timeouts-enabled') != 'YES'
        or value('-default-test-execution-time-allowance') != '240'
        or value('-maximum-test-execution-time-allowance') != '600'):
        raise ValueError('CI timeout or execution settings changed')
    selections = [x for x in command if x.startswith('-only-testing:')]
    if not selections or len(selections) != len(set(selections)): raise ValueError('Invalid selection')
    canonical = ['xcodebuild','-project','Kin.xcodeproj','-scheme','Kin',
                 '-destination',value('-destination'),'-derivedDataPath','DerivedData',
                 '-resultBundlePath',value('-resultBundlePath'),'-parallel-testing-enabled','NO',
                 '-collect-test-diagnostics','never','-test-timeouts-enabled','YES',
                 '-default-test-execution-time-allowance','240',
                 '-maximum-test-execution-time-allowance','600'] + selections + ['clean','test','CODE_SIGNING_ALLOWED=NO']
    if command != canonical: raise ValueError('Unexpected CI arguments')
    return ['xcodebuild', 'test-without-building', '-xctestrun', str(xctestrun),
            '-destination', value('-destination'), '-resultBundlePath', value('-resultBundlePath'),
            '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
            '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '240',
            '-maximum-test-execution-time-allowance', '600'] + selections


def main():
    xctestrun = Path(os.environ['KIN_AB_XCTESTRUN']).resolve(strict=True)
    def launch(command, *args, **kwargs):
        return original_popen(rewrite(command, xctestrun), *args, **kwargs)
    subprocess.Popen = launch
    resource_spec = importlib.util.spec_from_file_location('kin_ci_resource', source / 'scripts/ci-resource.py')
    resource = importlib.util.module_from_spec(resource_spec)
    resource_spec.loader.exec_module(resource)
    sampler = resource.ResourceSampler(os.environ['RUNNER_TEMP'])
    sampler.start()
    # Match the normal job's 45-minute test-step bound while leaving the
    # enclosing 50-minute job time for retention and simulator cleanup.
    deadline = threading.Timer(45 * 60, lambda: os.kill(os.getpid(), signal.SIGTERM))
    deadline.daemon = True
    deadline.start()
    failed = True
    try:
        result = observe.main()
        failed = result != 0
    finally:
        deadline.cancel()
        sampler.finish(failed)
    return result

if __name__ == '__main__':
    sys.exit(main())
