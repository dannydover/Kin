# Kin 1.3 UI reliability and gate trust — design draft

## Evidence and boundaries

The four-group candidate improves allocation, not the demonstrated UI failure
modes. In comparison run 41164684531, both Friend setup failures showed a unique,
hittable control remaining off after one synthesized tap; Save was enabled. In
retained synthetic recordings, the taps landed on the visible switch. This does
not establish whether delivery or state mutation failed. The eight-group wave
also timed out during a native Contacts import review; neither wave passed fully.
The later required run 41169827810 passed 184/184 without skips. One pass does
not establish a flake rate or fix the earlier failures.

The historical baby-label recording showed the expected labels visibly rendered
while XCTest timed out resolving one. The native Contacts recording showed the
synthetic contact visible while an accessibility lookup was interrupted. The
empty-category recording showed the Clear button tapped inside its visible frame
and the old category still displayed afterward. Those observations support
several distinct hypotheses; they do not prove a single common cause or exclude
an application defect. Avoid attributing all failures to the simulator or Apple.

## Shared-system audit

Each hosted job uses a fresh VM and simulator, but UI tests within a shard share
that simulator's Contacts, Photos, permissions, native services and process/UI
history. UUID notebook arguments isolate app storage, not system services. Runner authorization is verified from output emitted by the `KinUITests` class
setup, rather than a dedicated preflight; every current shard contains that
class, but a future shard without it would fail despite an authorized runner.
A shared same-runner authorization preflight can remove that composition
dependency without weakening the gate. Some Contacts fixture teardown uses
`try?`, so a cleanup failure can be hidden until
the whole simulator is deleted; no evidence yet shows this caused a failure.
The native picker relies on real service transitions and sample contacts, and
some tests issue many sequential accessibility queries or use compound readiness
predicates. Those are risks to investigate, not proof that the individual waits
or selectors are wrong. Current CI fails if XCTest reports skipped tests.

The UI shard guard must inventory nested files in Xcode's filesystem-synchronized
test group; the original top-level-only source scan could omit a future nested
UI test. Recursive discovery closes that specific gap and fails closed for an
unsupported nested test structure. It still uses source parsing, so a future
independent check against compiled XCTest discovery or a strict source contract
is needed. The unit job selects the entire KinTests target and rejects empty,
failed or skipped results, but has no independent mandatory-test identity
inventory; the observed 126 is not a permanent guaranteed count.

## Proposed staged work

1. Record the behavior/risk-to-test map before moving or combining coverage.
   Existing deterministic tests already exercise identity, relationships, age,
   photo eligibility, import review and persistence. Add deterministic coverage
   for missing state transitions where useful, but keep a real blocking UI path
   for button/toggle delivery, save/cancel, relaunch, accessibility and actual
   Contacts/Photos presentation. A constructed picker coordinator is not proof
   that the system picker works. No test, assertion or native coverage is silently
   removed, quarantined, skipped or made nonblocking.
2. Make shared fixtures and teardown verifiable: unique synthetic identities,
   observed fixture readiness, ownership-scoped cleanup and explicit cleanup
   failures that preserve the original failure. Audit notebook/process, keyboard,
   Contacts/Photos and service state separately. Do not seed real data, broaden
   permissions, add arbitrary sleeps or silently retap controls.
3. Trace the boundaries common to reported failures with fixed-field synthetic
   events: test action issued, app event/action entered, state transition and
   observed end state. Calibrate trace collection and preserve original failures;
   absent events are inconclusive unless the collector and app heartbeat are
   demonstrably continuous. Use one bounded targeted experiment per hypothesis,
   with a defined stop if it does not reproduce. Treat UIKit/SwiftUI, app binding,
   XCTest locator and runner contention as competing hypotheses until evidence
   distinguishes them.
4. Audit UI synchronization as shared infrastructure: bounded functional
   readiness and stable scoped locators, one action followed by an observed state,
   and diagnostic snapshots that do not conceal the original outcome. Do not
   replace meaningful end-state assertions with an easier readiness condition.
   Test any shared helper change against both passing and failing evidence.
5. Keep fast deterministic checks separate for early feedback while the existing
   required `validate` continues to require the full UI and native integrations.
   A smaller blocking suite, different release gate, evidence reuse or a changed
   coverage boundary requires a reviewed before/after map and a separate owner
   decision; this plan does not authorize those changes.

## Acceptance and measurement

After evidence-backed changes are reviewed locally, run a bounded initial set of
three complete, first-attempt hosted suites on the same exact reviewed head and
pinned toolchain, each using fresh synthetic simulators. Include a predefined
order variation that changes ordering only, not selected identities, assertions,
permissions or required gates, and verify the actual observed execution order
changed; reordering selector arguments alone is not proof. Establish an
independent baseline of mandatory unit identities before claiming all baseline
unit tests were accounted for, and include all newly added tests. Preserve all
runs and artifacts, including every
failure; do not replace one with a later passing attempt. A candidate meets this
initial criterion only if every required run finalizes with all baseline identities and any new tests accounted for and no failures,
skips, expected failures, or missing results. The current baseline is 184 tests,
but matching a count alone is not sufficient.
Investigate any failure before proposing further work. Three passes are a bounded
engineering criterion, not proof of a zero failure rate.

Report per-run identities, environment and toolchain, selected/order manifest,
first observed failure when available, failure class, elapsed and runner times,
setup/cleanup outcome and artifact integrity. Compare first-attempt results with
an explicitly identified baseline and continue observing over subsequent changes;
do not imply an improvement without a denominator and observation window.
Confirm local/hosted toolchain differences rather than assuming parity. Physical
QA and source-to-signed-archive provenance remain separate release requirements.
