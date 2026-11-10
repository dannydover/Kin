> Historical record: GitHub validation has since moved to the local release process in [LocalRelease.md](LocalRelease.md). Earlier results remain historical evidence.

# Kin 1.3 UI reliability and gate trust

The audit below records historical findings; the approved current strategy and
acceptance evidence are in the final sections of this document.

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

On the cleanup candidate, run 41206523843 completed 183 of 185 tests
successfully, with two failures and no skips. The extra test exercises the new
cleanup helper. A Contacts failure selected an unfocused historical Search
field while a different field had keyboard focus; the Clear restoration wait
also failed. The first proposed picker fix incorrectly assumed the native
keyboard was exposed in `app.keyboards` and failed in targeted run 41209201761.
In run 41210574048, typing through the application reached and selected four
synthetic search results and the second targeted test passed, but the first
test later failed synthesizing a scroll. This supports the narrow locator
change without establishing that the complete flow or other failures are fixed.
Full run 41212418281 passed 184 of 185 tests with no skips; its remaining
failure was an immediate off value after a tap inside the visible import-review
Friend switch. The isolated calibrated diagnostic 41214870560 passed without
reproducing that failure, so it does not establish the cause. A test-only
failure observer records the original immediate value and a bounded later
value without changing the original assertion or tapping again.

## Shared-system audit

Each hosted job uses a fresh VM and simulator, but UI tests within a shard share
that simulator's Contacts, Photos, permissions, native services and process/UI
history. UUID notebook arguments isolate app storage, not system services. Runner authorization is verified from output emitted by the `KinUITests` class
setup, rather than a dedicated preflight; every current shard contains that
class, but a future shard without it would fail despite an authorized runner.
A shared same-runner authorization preflight can remove that composition
dependency without weakening the gate. Contacts fixture teardown now verifies
removal of test-owned identifiers and reports missing, failed or uncertain
cleanup without suppressing the original failure. No evidence yet shows that
the formerly ignored cleanup errors caused a failure.
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

## Approved layered plan and acceptance

The owner approved a smaller blocking suite after the same-head comparison in
[run 42068723543](https://github.com/dannydover/Kin/actions/runs/42068723543).
The earlier audit above is historical evidence, not a requirement to keep all
native UI journeys in the automatic gate. The accepted gate requires core,
the entire iOS `KinTests` unit/integration target, four exact UI smoke tests,
and Release validation. Finalized identities, no-skip checks, retained results,
and applicable cleanup remain fail-closed. The smoke covers app launch,
create/save/relaunch, relationship edit/relaunch, and empty People screenshots
at normal and largest text. It does not use real Contacts or Photos.

The full broad UI suite, including real system picker journeys, is run only by
explicitly dispatching `Manual broad UI diagnostics` with an exact source SHA.
It reports failures and retains its own evidence; a passing required gate never
relabels a failed broad run. The workflow must exist on the default branch before
GitHub can dispatch it. Removing broad UI from automatic PR checks and the
required gate reduces automated end-to-end assurance. See the
[layered coverage map and release checklist](Kin13LayeredValidation.md) for
specific losses and conditional physical-device Contacts/Photos review when
those features, permissions or affected platform behavior change. Normal and
largest-text layout, scrolling, clipping, hit targets, VoiceOver, backgrounding,
and relaunch remain manual release-candidate obligations. Physical QA has not
been completed for this candidate.

## Repeatability evidence and limits

On exact code head `6c275de70775159be51be955917c47df2e6222e1`, the
[standard run 42112107825](https://github.com/dannydover/Kin/actions/runs/42112107825)
and [random-plan run 42113699517](https://github.com/dannydover/Kin/actions/runs/42113699517)
both passed the required gate: 164 iOS tests and four smoke tests each, zero
skips, with matching result hashes, matching iOS identity sets, exact smoke
identities and verified simulator deletion. In the standard run, shutdown timed
out before deletion succeeded and inventory confirmed absence. The four smoke
test starts were observed in a different order. All 164 iOS test starts in the
retained test-host output were observed in the same sequence, despite the random
plan; those two runs did not establish a changed iOS order. Core and Release
execution were unchanged. These two samples do not establish a failure rate.

**The later iOS order diagnostic used two separate test-host invocations on one
fresh simulator. It does not establish order independence within a single
continuous test-host process.** On unchanged PR source
`627d3d57df5ff3094d5872cd8a1beebf355ae0c7`, the
[explicit-batch run 42121042016](https://github.com/dannydover/Kin/actions/runs/42121042016)
passed 94 and 70 tests, zero skips. All 164 baseline identities and observed
starts appeared exactly once in a different order. Both finalized result-bundle
hashes and simulator shutdown, deletion and absence were independently verified.
The wrapper was separate from the tested source and did not change the PR gate.

The [first diagnostic attempt 42119226838](https://github.com/dannydover/Kin/actions/runs/42119226838)
remains failed: its verifier reported the 94/70 outcome, but packaging failed
and neither result bundle was retained, so those bundles cannot be independently
verified. Its simulator shutdown, deletion and absence were verified. The later
successful diagnostic does not retroactively make that attempt pass.

The earlier [trial 42105476611](https://github.com/dannydover/Kin/actions/runs/42105476611)
remains failed: its iOS simulator shutdown and deletion timed out and inventory
still showed the device present. Its broad UI result independently recorded 72
passes and one Photos/Contacts query-timeout failure. Retained passing tests do
not erase either failure. Preserve all failures and artifacts, investigate any
new failure, and avoid retrying unchanged tests merely to obtain green.

This document update is documentation-only and follows the tested code head;
it does not imply a new code-order experiment. Normal CI still runs on the
resulting PR head. The captured largest-text screenshot shows content extending
behind the search bar in its initial viewport; the automated broad test reached
and opened the main button after scrolling, but full paragraph readability and
VoiceOver must be checked on the release device.
