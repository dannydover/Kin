# Kin 1.3 layered validation comparison

## Same-head comparison and required gate

[Run 42068723543](https://github.com/dannydover/Kin/actions/runs/42068723543) compared both approaches at commit `171e38038dd427f897b6798f6e2fd95cbb6f6508` on Xcode 27.0/iOS 27.0. The proposed components passed: Core, Release, all 163 iOS unit/integration tests and both exact smoke identities. The smoke job took 9 minutes 2 seconds after starting, plus queue time; its test step took 5 minutes 4 seconds. The current full gate failed: 233 passed and one failed, zero skipped. The failure reported that Kin did not have a process ID during `testAllPeopleOpensProfilesAndReturnsToSameIndex`. All UI identities, result hashes, six simulator cleanup records and five owned synthetic Contacts cleanup markers were verified. The broad failure remains a failure; its cause is unresolved.

The `validate` gate requires Core and repository checks, the **entire** iOS `KinTests` target including integration and rendered-layout tests, both exact smoke identities, and Release validation. Missing, skipped, failed, repeated, interrupted or incomplete selected tests and unverified required cleanup fail their jobs. The broader UI matrix runs independently and reports its own result and artifacts, including failures. It is not a dependency of `validate`; this reduces automated end-to-end release assurance and requires the manual review below. Branch protections are unchanged. The full workflow may still show failure when broad UI fails, even if `validate` passes.

This is a single comparison, not a measured failure rate or proof of stable future runs. Collect repeatability and changed-order evidence independently and preserve each result.

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
