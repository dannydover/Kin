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

On the `feature/kin-1.3-ci-comparison` pull request from this repository only,
the ordinary four-group required run is followed by eight separate UI groups.
Both waves use the same pull-request checkout, Xcode 27.0, synthetic fixtures,
assertions, readiness limits and artifact retention; each UI method is assigned
exactly once per wave. The second wave starts even if the first wave fails,
unless the run is cancelled. It is an additional visible experiment and does
not change `validate`'s existing dependencies. Unit/integration tests remain in
the required first wave. Both waves finish rather than cancelling other groups
on a test failure. The comparison is not triggered by pushes to main or other
pull requests; remove the experiment before merging.

Sequential waves reduce competition between configurations but add a second-wave
delay and may still see different runner load or environment drift. For each
wave, record job creation/start/completion and per-step times from GitHub, and
compute queue time, simulator/setup time, clean-build-to-first-test time, test
span, first observed failed test and first failed job, full completion and total
runner minutes. `CI_TEST` live log lines contain only allowlisted synthetic test
IDs, fixed status tokens and elapsed seconds; the full raw XCTest output is not
printed. A job can have no failure; an incomplete or missing first-failure
observation is unknown, not zero. Record actual failures, skips, timeouts and
missing or partial results, and retain both waves' artifacts. One comparison is
not a failure-rate estimate or evidence that flaky failures are solved.
