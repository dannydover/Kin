# Kin 1.3 layered validation comparison

## Comparison first

The existing `validate` check remains unchanged for this comparison: Core, the complete iOS `KinTests` target, all four broad UI shards, and Release validation still have to succeed. The independent `candidate-smoke` job runs on the same commit, Xcode 27.0 and iOS 27.0 runtime. Its result is visible but does not replace `validate`. Compare the actual job outcomes, first-attempt failures, durations and retained cleanup on the same head before changing the release-blocking gate. A passing candidate cannot erase a failed broad test or establish a failure rate.

The proposed future minimum gate is Core and repository checks; the **entire** iOS `KinTests` target, including integration and rendered-layout tests; the two exact smoke identities; and Release validation. It must fail on a failed, missing, skipped, repeated, interrupted or incomplete selected test, or unverified required cleanup. The present workflow's unit and broad UI shards share a matrix, so implementing a smaller gate later requires a separately reviewable job separation; a matrix aggregate must not be mistaken for the unit job's status. Branch protections remain unchanged.

## Coverage and limitations

| Behavior | Proposed blocking evidence | Still requires broader UI or manual review |
|---|---|---|
| Normal app launch, create, save and cold relaunch | `KinUITests.testNormalColdLaunchOpensNotebookAndPreservesSavedPerson` | Other onboarding, error and editing paths |
| Link, edit and reopen a relationship | `SmokeUITests.testRelationshipEditPersistsAfterRelaunch`; `PersonTests` and `SequentialImportRestartTests` | Other relationship roles, reversal, cancellation and accessibility permutations |
| Filters, birthdays, identity, cancellation, saving and reopening | Complete Core and iOS `KinTests` target, including `PeopleFilterStateTests`, `FilterStoreSequenceTests`, `ExistingContactBirthPreservationTests`, and store/relationship tests | The full range of rendered navigation, gestures and accessibility behavior |
| Contact and photo rules and persistence | `ContactPickerTests`, `ExistingContactBirthPreservationTests`, `ContactPhotoReviewTests`, `NewPersonImportTests`, `SequentialImportRestartTests`, and `PhotoProcessorTests` | Real system-picker presentation, selection, permission transitions and native payload delivery |
| Basic rendered person-row layout | `RenderedLayoutTests` renders the actual row at standard and largest text sizes and checks nonempty, appropriately sized output | This is not an OCR, clipping, hit-target, VoiceOver or full-screen proof; broad UI and device review remain necessary |

The small smoke intentionally excludes real Contacts and Photos pickers. Repeated native picker failures and delays are documented in [run 42060127588](https://github.com/dannydover/Kin/actions/runs/42060127588) (ambiguous Contacts card), [run 42044257144](https://github.com/dannydover/Kin/actions/runs/42044257144) (Contacts card lookup), and [run 41942996537](https://github.com/dannydover/Kin/actions/runs/41942996537) (Photos loading). Other non-picker UI and simulator failures also occurred. These examples support reducing picker dependence in smoke; they do not establish a failure rate or an Apple root cause.

The full UI suite remains available as a separate, visible result after any future gate change. Its failed, skipped, interrupted or missing evidence must be reported as such; it is never reclassified as passing because the smaller gate passed. Removing it from a release-blocking condition is a reduction in automated end-to-end assurance, not an equivalent replacement. Real native picker changes require the manual checks below on the actual release candidate.

## Short manual release checklist

Record the tested release-candidate build and device/OS, result, tester and any issue. Use synthetic or explicitly authorized data.

1. On the actual release candidate, launch, create and edit a person, link a relationship, background and reopen the app, and confirm saved data.
2. Check the changed screens at normal and largest text, and use VoiceOver for labels, order, controls and dismissal. Review visual clipping and hit targets on the device.
3. **When Contacts-related code, permissions, import review, mapping or affected platform behavior changes:** exercise real Contacts selection, cancel, review, save and relaunch; confirm the permission state and that unrelated contacts are not accessed.
4. **When Photos-related code, permissions, image processing, photo review or affected platform behavior changes:** select a real synthetic test image, cancel and save as applicable, relaunch and check the result and permission behavior.
5. Resolve failures or explicitly record an owner decision before release. Do not treat missing manual evidence, broad UI failures, or unavailable artifacts as passing validation.
