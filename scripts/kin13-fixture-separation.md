> Historical coverage or experiment record: current release validation runs on Mac Studio; see [LocalRelease.md](../Development/LocalRelease.md). Prior results and limitations remain recorded below.

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
DEBUG isolated-test-notebook branch. Only four fixed fixture names are accepted;
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
only the marked candidates change in this batch.

| Caller | Friend's role and disposition |
|---|---|
| Normal cold launch | Real startup and Save are part of the behavior; retain the UI setup. |
| Synthetic unnamed-draft four-route review | Existing listed source for parent/child/partner routes; retain pending route-specific fixture validation. |
| Relationship role labels, and long-role labels | Listed source people for relationship creation and rendered labels; retain pending identity/order and accessibility-fixture review. |
| `prepareYoungPersonAndExistingParent` | **Candidate:** two persisted Friend-on listed people with original names and references; all four parent scenarios retain their UI age edit, duplicate/cycle/cancel/relationship and relaunch assertions. Initial direct creation and Friend toggling are exercised separately. |
| Synthetic Add parent import | Listed child is a source for review, Save, relationship and relaunch assertions; retain pending route-specific validation. |
| Existing partner/unlink/delete; shared child/rename | Listed people and relationships are created and later persisted; retain pending fixture identity and relaunch equivalence. |
| New partner status | **Candidate:** two persisted Friend-on listed people with original names/references; all partner-status, Cancel, Save and relaunch assertions remain. Direct creation and Friend/Save are covered by the separate retained journey rather than repeated here. |
| All people profile navigation | Listed source and unlisted linked child are contrasted; retain setup until both membership states and navigation are mapped to a replacement. |
| Illustrated empty state/search recovery | Friend is later toggled off before list membership is turned off; retain this real toggle path and setup. |
| Blank-name cancellation/rename | Friend is setup only; **candidate:** same Friend-on persisted fixture, with creation/toggle/Save retained in the dedicated test. |
| Form surfaces/destructive controls | Source person for real editor/delete-alert interactions; retain pending fixture and alert-flow review. |
| Young-profile sections | Source person for age and profile behavior; retain pending age/relationship fixture review. |
| `addEstimatedAdult` | **Migrated setup:** four isolated persisted estimated-80 Friend records replace repeated creation, Friend toggling and initial age entry. The photo, missing-birthday and two age-wheel journeys retain their downstream UI actions and assertions; direct Friend/Save/relaunch remains required separately. |
| Reviewed-import route helper | Listed source for real native smoke and synthetic multi-route matrix; retain pending route and system-coverage review. |
| Compact unknown-age long names | Friend-on parent is setup only; **candidate:** same persisted parent fixture; child creation and both layout assertions remain UI-driven. |

The shared toggle is still exercised by many existing call sites as well as the
new explicit Friend persistence test. This audit does not assert that other
callers need the Friend category for their business outcome; it leaves them
unchanged until each replacement has independently validated setup and
assertion ownership. No native system journey or UI method is removed.


## Follow-up after hosted run 41385195567

This additional local candidate changes the partner-status test's two-person
setup to `partner-friends`: two distinct deterministic IDs, original synthetic
names, references 1 and 2, Friend on, listed, and unknown age. Its status
selection, cancellation, save, relationship and relaunch assertions are
unchanged. As in the earlier two fixtures, those two initial direct-creation
journeys move out of this particular test; the dedicated real Friend/Save/
relaunch UI test remains required and passed in run 41385195567. No UI test or
native picker journey is removed. Core tests verify exact fields and references,
reopen and link preservation, and fail closed when only one owned fixture
exists after a partial setup. The test-only seeder is not atomic across its two
initial saves; a partial first save causes a later seed attempt to fail closed,
not silently complete or overwrite a notebook. Release marker checks include
all four fixture case strings. Hosted validation is still required.

The partner failure's retained recording shows the Add person screen and Friend
off, with the keyboard present; fixed-field before/after records both show the
uniquely located control hittable and off. Other failures have occurred with a
dismissed keyboard. The editor's binding inserts/removes Friend synchronously,
but the recording cannot prove event delivery or rule out app/state issues.

The relationship-chooser recording shows the selected Blair profile partway
through its navigation transition when the immediate exact edit-ID existence
assertion failed. A sibling test already waits five seconds for the same exact
identity. A targeted readiness wait could preserve that identity check, but
would add a new wait to a previously immediate assertion; it is not implemented
under the existing no-timeout-increase constraint. Review the timing semantics
explicitly before making such a change. It does not explain the Friend failure.

For the Photos failure, the recording shows the native picker remaining on its
loading screen through the failing wait and displaying the grid later. The app
accessibility-hierarchy attachment did not contain Photos anchors, so it cannot
establish whether the final selector was exposed at the relevant instant. The
existing 15-second navigation-bar assertion, asset selection and image-save
assertions remain unchanged; no timeout increase or alternate picker is used.
This evidence supports slow readiness as an observation, not a proven app,
framework or runner root cause.


## Shared parent setup follow-up after run 41388703644

The partner fixture, dedicated Friend journey and prior fixture-backed tests
passed in that run, but the overall run failed 206/207: the duplicate-parent
test hit the same Friend-on setup failure in `prepareYoungPersonAndExistingParent`.
The preserved before/after records show the uniquely hittable Friend control off
with the keyboard present. The shared helper serves four parent tests; their
Friend selection is setup, while their actual contracts include the age edit,
biological/step relationships, duplicate and cycle rejection, cancellation,
relaunch and unlink. The local `young-parent-friends` fixture starts with the
same Friend-on listed names and references 1 and 2, and leaves the age edit and
all four tests' downstream assertions unchanged. Those methods no longer each
perform the initial direct-creation/toggle/Save sequence; the dedicated real
Friend/Save/relaunch UI test remains required. No UI or native journey is
removed.

The two-person fixture uses the same distinct ID derivation and fail-closed
partial-setup rule as `partner-friends`. Parameterized core tests check exact
fields, reference ordering, linked-record preservation on reopen, and failure
without mutation if only one fixture exists. Local Xcode/SwiftPM tests do not
replace normal hosted Release, UI and cleanup checks. This candidate has not
yet been validated on hosted CI. A pass would not prove that Friend interaction,
Photos readiness or other UI failures are resolved.

## Estimated-adult setup batch after run 41514316354

Four callers of `addEstimatedAdult` used the same preliminary direct creation,
Friend-on toggle, Save, profile reopen, Estimated age selection, empty-age Save
check and age-80 entry. The fixtures use the same name, isolated notebook ID,
listed/Friend state, unknown gender, empty photo and age 80 as of the current
civil day. The four journeys still open the named profile and assert the age-80
label before their original test-specific steps:

| Journey | Retained UI contract |
|---|---|
| Estimated age boundaries | Real wheel 120/0, cancellation, Save and relaunch persistence. |
| Estimated age at largest text | Real largest-text wheel geometry, controls and cancellation. |
| Photo removal | Real Photos selection, removal warning, Cancel, saved photo and age after relaunch. |
| Missing-birthday import | Real Photos and Contacts, review/cancel/draft preservation, empty estimated-age Save disabled, age entry, Save and relaunch. |

The setup-specific initial create/Friend/Save/age-80 route is no longer repeated
in each of these four journeys. Direct creation and Friend/Save/relaunch remain
required in `testDirectFriendTogglePersistsAcrossSaveAndRelaunch`; the
missing-birthday journey still checks Save is disabled when estimated age is
selected without a value. Wheel interactions and their original assertions
remain in the age journeys. This is an explicit reduction in repeated setup,
not proof that Friend, Photos, Contacts or XCTest lifecycle failures are fixed.

The other audited `addPerson` call sites in the table above remain unchanged:
some exercise creation or toggling themselves, and other fixture substitutions
still need identity, ordering, relationship or navigation equivalence before
removing setup. No native picker, relationship or deletion journey is retired.
