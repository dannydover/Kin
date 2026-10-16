#!/usr/bin/env python3
"""Require finalized, passing, non-skipped Xcode test results; logs alone are insufficient."""
import json
from pathlib import Path
import sys


def validate_summary(summary):
    if not isinstance(summary, dict):
        return False
    counts = ('totalTestCount', 'passedTests', 'failedTests', 'skippedTests', 'expectedFailures')
    if not all(type(summary.get(key)) is int for key in counts):
        return False
    return (summary.get('result') == 'Passed' and summary['totalTestCount'] > 0
            and summary['passedTests'] == summary['totalTestCount']
            and all(summary[key] == 0 for key in ('failedTests', 'skippedTests', 'expectedFailures')))


if __name__ == '__main__':
    try:
        summary = json.loads(Path(sys.argv[1]).read_text())
    except (OSError, ValueError, IndexError):
        sys.exit('Test results are unavailable or unfinished; validation failed.')
    if not validate_summary(summary):
        sys.exit('Test results must be finalized and passing, with no skipped or expected-failure tests.')
    print(f"Finalized results verified: {summary['passedTests']} tests passed; no skips or failures.")
