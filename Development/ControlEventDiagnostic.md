# Synthetic control-event diagnostic (nonshipping)

This isolated diagnostic runs the original `testPhotoRemovalAlertHasVisibleCancelAndPreservesSavedPhoto`
and `testClearEmptyCategoryRestoresPeopleWithoutChangingRecords` separately, once each on a new
synthetic simulator. It keeps the original single taps, assertions, test timeouts and saved-state
checks. The Friend case seeds only a generated synthetic Photos image; neither test grants Contacts
or Photos permissions or accesses a personal library. A failed test remains failed.

At build time only, the diagnostic injects fixed-field probes into a disposable checkout. It records
monotonic timestamps and booleans for the test's before/after tap markers, app touch dispatch/hit
classes, Friend binding before/after, Clear closure and before/after state. A one-second app heartbeat,
probe-install marker and target geometry marker bracket the action. No text values, names,
coordinates, screenshots, raw logs or unrelated telemetry are retained in public artifacts. Missing
markers, geometry or a heartbeat gap make the trace uncalibrated. Even a calibrated window cannot
prove that OS logging delivered every record: an absent touch or closure record is **not proof** that
it never occurred. Instrumentation and heartbeat can also affect timing.

Each sanitized result records the exact test identity, pass/fail/skip counts, failure categories and
SHA-256 digests of original failure messages, collector calibration and cleanup outcomes. Raw XCTest
bundles remain ephemeral because failure diagnostics can contain unrelated host process information;
the sanitized result is not a replacement for a full bundle. Missing or incomplete result/trace is
reported as failure or unknown. This diagnostic is not release validation, does not establish a
product/framework root cause by itself, and must not be merged into production. Compare an observed
failure with a passing case only when both have calibrated windows and matching context. If neither
failure reproduces, stop this diagnostic rather than rerun for a desired result.
