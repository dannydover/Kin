# Kin 1.3 CI validation baseline

The 1.3 candidate retains the required `validate` aggregate and every existing
unit and UI test. It adds a fourth blocking UI group and assigns discovered UI
methods by deterministic longest-first balancing. Previously unseen tests use a
90-second scheduling estimate and remain blocking; the estimate does not change
test timeouts or assertions. Removed test timing entries do not add tests. The
result check requires a passing, finalized, zero-skip summary and the exact set
of selected UI test identities, with no duplicates. Unit coverage remains the
whole KinTests target. Existing synthetic simulator setup, bounded job timeouts,
progress reporting, result retention and cleanup remain in place.

The checked-in estimates are first-attempt synthetic test durations from passing
[PR #56 run 40996409684](https://github.com/dannydover/Kin/actions/runs/40996409684).
It had 126 unit/integration and 58 UI tests, with no skips. Its three hosted UI
jobs took 2364, 1783 and 1694 seconds end to end. The test-only sums were about
1815, 1410 and 1267 seconds. A four-group model assigns 14, 14, 15 and 15 UI
tests, with estimated test-time sums of approximately 1118, 1118, 1126 and
1129 seconds. This is not a hosted benchmark: setup, compilation, contention,
runner availability, actual test order and variance can change wall time.

A later [main run 41063164579](https://github.com/dannydover/Kin/actions/runs/41063164579)
failed four UI cases: query timeout, remote accessibility lookup interruption,
Friend/Save readiness and empty-category restoration. Their causes are not
established. This sharding change does not claim to fix them. Retain failures,
record first-attempt results and denominators, and investigate failures before
any retry. Do not treat a single passing run as a reliability estimate.

Before merging this candidate, run the unchanged full required workflow on the
exact proposed head, verify all result identities and artifacts, compare hosted
job and total elapsed times to the baseline, and review any failures. Keep the
native Contacts and Photos integration paths blocking in this candidate; no
coverage has been moved to a nonblocking suite. Any future change to selection,
evidence reuse, permissions, or required-check semantics needs its own explicit
review. Separate delivery-planning work remains plan-only; it is not part of this CI
comparison and cannot sign, upload, submit, or publish an app.

## Bounded four-versus-eight comparison

[Draft PR run 41164684531](https://github.com/dannydover/Kin/actions/runs/41164684531)
compared the same 58 UI methods under both configurations on Xcode 27.0.
Both sets of finalized result bundles and test identities were verified.
The four-group wave took 33m37s from job creation to its last UI job finishing,
using 110m20s of combined UI runner time; 56/58 UI tests passed, with zero skips.
The eight-group wave took 37m38s and used 149m32s of UI runner time; 57/58
passed, with zero skips. The four-group required aggregate failed. The 126 unit
and integration tests passed. These are two observations, not a failure-rate
measurement or proof that either grouping fixes the intermittent failures.

The first observed four-group failed-test event was about 17m27s after wave
creation; its job completed failed at 33m37s. The eight-group timeout did not
produce a failed-test event in the sanitized progress stream, so its first
failure time is unknown; its failed job completed about 24m33s after the wave
was created. Five eight-group jobs initially ran while three waited for runners;
its longest observed queue was about 22m10s. The waves ran sequentially, so
runner load and time-dependent conditions may have differed. Time spent on unit,
core and Release jobs is not included in the UI runner-time sums.

Four groups remain the default: this run completed sooner with less combined UI
runner time, without reducing coverage. Keep the eight-group failure and the
earlier failures visible; do not describe either configuration as reliably
passing. Live `CI_TEST` events contain only allowlisted test IDs and fixed status
and timing fields; they report a completed failed-test event, not necessarily
the instant an assertion first failed. An absent event is unknown, not zero.
