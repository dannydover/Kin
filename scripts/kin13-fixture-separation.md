# Kin 1.3: isolate unrelated Friend setup (local candidate)

This local batch is not a claim that Friend or launch flakiness is fixed. The
published cleanup head `d438d9ad70dcc0880c7e1f7e04a1592f02d013df` failed hosted
run 41359545314: 199/201 passed, zero skips. That first attempt and all earlier
failure records remain relevant. No test is retired in this candidate.

## Exact setup and coverage change

The shared `addPerson` helper creates a direct listed person and toggles Friend
on. In `testBlankNameEditsCancelAndLaterNamingPreserveEntry`, Friend-on was a
setup condition; the assertions are cancel/blank-name/save/relaunch/rename. In
`testCompactUnknownAgeWithLongNamesAtStandardAndAccessibilitySizes`, Friend-on
was setup for a listed parent; the assertions are the long-name child/unknown-age
layout at two text sizes and visibility after relaunch. Both now begin with an
isolated persisted DEBUG-only fixture having the **same name, Friend-on, listed,
unknown-age and reference-one state** as their previous setup. Their subsequent
UI actions and existing assertions are unchanged. Compact-age still creates its
child through the UI and exercises the same relationship and layout. These two
methods no longer exercise initial direct creation, Friend toggle and Save in
their own setup; this is the explicit tradeoff, not identical end-to-end setup.

`testDirectFriendTogglePersistsAcrossSaveAndRelaunch` retains the actual direct
editor path: the existing helper requires a unique Friend control initially off,
taps once, requires wrapper/control on and Save enabled/hittable, saves, checks
the named row, then relaunches and checks Friend remains on in the editor. Other
existing picker and relationship tests still exercise real Friend interactions.
The new test has not been run on hosted CI and does not establish the cause or
frequency of Friend failure. It adds a UI method rather than removing coverage.

## Fixture isolation and exclusion

`SyntheticNotebookFixture.selection` requires exactly one `--kin-ui-fixture`
flag, one valid `--kin-test-notebook` UUID, and no preview mode. Invalid arguments
fail before normal notebook opening. `KinApp` seeds only inside the existing
DEBUG isolated-test-notebook branch. Only two fixed fixture names are accepted;
seeding fails for an unrelated nonempty notebook, does not overwrite a record
with the fixture identity on relaunch, and uses no personal data or permissions.
The DEBUG-only core seeder and argument marker are covered by the Release binary
guard. Local core tests check both fixture names, identity, Friend, listing,
age, reference, default fields, persistence, preservation of edits and linked
records, invalid arguments and nonempty-notebook failure. A release-mode object
compiled without DEBUG contains no fixture symbols or fixture-name strings;
this is not a substitute for hosted Release validation.

## Friend and launch evidence

On the failed blank-name attempt in run 41359545314, the retained fixed-field
trace showed the keyboard present and both wrapper and nested Friend control off
before and after one tap, while the control was hittable. A prior Friend failure
also occurred after the keyboard was dismissed. `PersonEditor` binds the toggle
to insertion/removal in `draft.connections`; these observations do not establish
whether a specific touch reached that binding, a state update was lost, or XCTest
reported stale state. The remaining real Friend test must retain a single tap
and the same assertions; do not double-tap, retry until on, or infer an app fix.

The largest-text deletion test in that run exceeded four minutes inside XCTest's
app-launch operation before its deletion assertions. Its retained spindump
samples XCUIAutomation collecting diagnostics after a launch error; that is not
proof of why launching failed or whether the app itself is defective. No safe
app-lifecycle correction is established from this evidence. Do not extend the
timeout, silently retry launch or change the test's assertion.

## Validation and next step

The local core suite and harness tests validate the fixture and Release-marker
logic. Direct source syntax and the release-mode object check are supporting
checks; only a normal hosted Xcode 27.0 Release build can validate the full app
binary and actual UI behavior. Before publication, review the test-data and
creation-route tradeoff and the exact isolated diff, preserve unrelated local
commits, and run the normal exact-head CI once. If it fails, retain and diagnose
the first attempt; no blind repeats. A passing run is not evidence that all UI
flakiness or app-launch behavior has been resolved.

## Shared `addPerson` call-site audit

The helper checks direct Friend off-to-on, Save and return to the exact row in
every caller. This table identifies its role before any wider fixture migration;
only the two marked candidates change in this batch.

| Caller | Friend's role and disposition |
|---|---|
| Normal cold launch | Real startup and Save are part of the behavior; retain the UI setup. |
| Synthetic unnamed-draft four-route review | Existing listed source for parent/child/partner routes; retain pending route-specific fixture validation. |
| Relationship role labels, and long-role labels | Listed source people for relationship creation and rendered labels; retain pending identity/order and accessibility-fixture review. |
| `prepareYoungPersonAndExistingParent` | Two listed people, later relationship and age setup; shared by multiple parent tests; retain pending branch-by-branch fixture validation. |
| Synthetic Add parent import | Listed child is a source for review, Save, relationship and relaunch assertions; retain pending route-specific validation. |
| Existing partner/unlink/delete; new partner status; shared child/rename | Listed people and relationships are created and later persisted; retain pending fixture identity and relaunch equivalence. |
| All people profile navigation | Listed source and unlisted linked child are contrasted; retain setup until both membership states and navigation are mapped to a replacement. |
| Illustrated empty state/search recovery | Friend is later toggled off before list membership is turned off; retain this real toggle path and setup. |
| Blank-name cancellation/rename | Friend is setup only; **candidate:** same Friend-on persisted fixture, with creation/toggle/Save retained in the dedicated test. |
| Form surfaces/destructive controls | Source person for real editor/delete-alert interactions; retain pending fixture and alert-flow review. |
| Young-profile sections | Source person for age and profile behavior; retain pending age/relationship fixture review. |
| `addEstimatedAdult` | Source for real Photos/Contacts and age-selection journeys; retain native/system setup until its assertions and fixture state are separately reviewed. |
| Reviewed-import route helper | Listed source for real native smoke and synthetic multi-route matrix; retain pending route and system-coverage review. |
| Compact unknown-age long names | Friend-on parent is setup only; **candidate:** same persisted parent fixture; child creation and both layout assertions remain UI-driven. |

The shared toggle is still exercised by many existing call sites as well as the
new explicit Friend persistence test. This audit does not assert that other
callers need the Friend category for their business outcome; it leaves them
unchanged until each replacement has independently validated setup and
assertion ownership. No native system journey or UI method is removed.
