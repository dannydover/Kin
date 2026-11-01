# Synthetic Contacts cleanup: local migration candidate

This candidate is local only. The existing UI cleanup test, both real Contacts
journeys, cleanup markers, exact UI identity coverage and CI failure gate remain
required. No runner permission, app behavior or release setting changes.

## Shared test-only primitive and tests

`KinTests/Shared/SyntheticContactsCleanup.swift` contains the generic algorithm
previously in `KinUITests/SyntheticContactsCleanupTests.swift`: empty/uncertain
state, owned-ID validation, deletion, query of exactly the supplied IDs, failure
if any remain, and fail-closed uncertain creation. The Contacts adapter still
constructs a delete request only from the test-owned contacts, queries only
those identifiers, emits the same fixed scope/status marker and converts errors
to the same teardown failure. The UI test remains unchanged apart from the moved
declaration; no native coverage is retired.

Xcode includes the source through the synchronized **KinTests** tree and
explicitly in **KinUITests**; the app Sources phase and production configuration remain
at the frozen baseline. SwiftPM builds it as a separate support target used by
KinTests, not as a dependency of the Kin product. The production-isolation test
allows exactly the reviewed UI-test build-file reference and continues to
compare the app target and its build phases to baseline. The support code has no
Contacts import, address-book query, credential, or runtime permission logic.

`SyntheticContactsCleanupCoreTests` checks successful empty/partial cleanup,
exactly owned IDs in both operations, empty/duplicate identifiers failing before
mutation, uncertain empty/partial creation, deletion and query errors, and
remaining owned fixtures. The existing UI cleanup test continues to exercise the
same source. A new CI-harness test checks that the real adult/minor and
missing-birthday picker tests remain selected with distinct mandatory cleanup
scopes. Existing harness tests continue to reject missing, duplicate, empty and
failed cleanup markers on otherwise successful runs, and preserve actual test
failures.

Local evidence: SwiftPM core suite passed 92 tests, script suite passed 72 tests,
project plist and discovery checks passed, and direct simulator-SDK typechecking
of both the UI cleanup adapter and the new core tests with the shared source
passed using the locally selected Xcode. The complete unsigned Xcode `build-for-testing` is **not
verified**: local CoreSimulator reported its installed version older than the
selected Xcode, and the build also emitted Swift compile-command failures. The
hosted Xcode 27.0 test targets, release-exclusion build, actual cleanup and
marker parity still require normal exact-head CI. This candidate does not
justify retiring the UI test until that evidence is obtained and reviewed.

## Dismissal waiter: retained failure and bounded proposal

In repeat run 41355166017, the compound deletion test tapped confirmation
Cancel and sheet Cancel. The first `Delete all people` existence lookup began at
1793571439.309; XCTest's lookup retries appeared at 1793571443.612 and
1793571443.615, about 4.3 seconds later. The waiter timed out. A subsequent
failure-only observation completed at 1793571449.596 with `sourceExists=false`,
`destinationExists=true`, and `destinationHittable=true`. This shows synchronous
accessibility lookups consumed most of the five-second budget and that the
expected state was observed afterward. It does **not** timestamp when the screen
actually disappeared or prove a missed tap, an application bug, or a framework
bug. The repeat remains failed.

A possible targeted follow-up, not implemented here: after the one existing
Cancel tap, wait up to the existing five seconds for the unique source screen to
disappear using one `waitForNonExistence` predicate. Only if that succeeds,
assert that the unique destination control is hittable; keep the original
record/cardinality assertions. A missing destination fails rather than retapping
or checking the wrong screen. Compared with polling source existence,
destination existence and destination hittability together, this has one remote
query in the waiting predicate and one subsequent destination check. It can be
stricter if the destination is briefly not hittable after source disappearance;
that would be an honest failure, not a delayed success. XCTest calls can still
exceed their nominal timeout, so this cannot promise a five-second wall-clock
bound or establish a root cause. Failure-only fixed-field diagnostics may record
late state but must never change the original assertion outcome.

Before adopting that change, exercise synthetic UI examples for a completed
dismissal, a deliberately still-present source and a missing/blocked destination,
then validate in the required full suite with retained first-attempt results. Do
not extend timeouts, add extra retries or start an unchanged full suite simply
to seek a pass. The previously failed UI and CI outcomes remain recorded.
