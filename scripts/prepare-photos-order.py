#!/usr/bin/env python3
"""Add fixed-field timing around one existing assertion in a disposable checkout."""
from pathlib import Path

path = Path('KinUITests/KinUITests.swift')
text = path.read_text()
start = text.index('    @MainActor func testPhotoRemovalAlertHasVisibleCancelAndPreservesSavedPhoto()')
end = text.index('    @MainActor func testContactMissingBirthdayPromptCancellationAndEstimatedImport()', start)
block = text[start:end]
before = '        XCTAssertTrue(app.navigationBars["Photos"].waitForExistence(timeout: 15))'
after = '''        print("KIN_CI_PHOTOS begin ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000))")
        let photosReady = app.navigationBars["Photos"].waitForExistence(timeout: 15)
        print("KIN_CI_PHOTOS \(photosReady ? "ready" : "not_ready") ms=\(Int64(ProcessInfo.processInfo.systemUptime * 1000))")
        XCTAssertTrue(photosReady)'''
if block.count(before) != 1:
    raise ValueError('Photo assertion shape changed')
path.write_text(text[:start] + block.replace(before, after, 1) + text[end:])
