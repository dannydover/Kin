# Kin 1.3 layered validation comparison

## Same-head comparison and required gate

[Run 42068723543](https://github.com/dannydover/Kin/actions/runs/42068723543) compared both approaches at commit `171e38038dd427f897b6798f6e2fd95cbb6f6508` on Xcode 27.0/iOS 27.0. The proposed components passed: Core, Release, all 163 iOS unit/integration tests and both exact smoke identities. The smoke job took 9 minutes 2 seconds after starting, plus queue time; its test step took 5 minutes 4 seconds. The current full gate failed: 233 passed and one failed, zero skipped. The failure reported that Kin did not have a process ID during `testAllPeopleOpensProfilesAndReturnsToSameIndex`. All UI identities, result hashes, six simulator cleanup records and five owned synthetic Contacts cleanup markers were verified. The broad failure remains a failure; its cause is unresolved.

The `validate` gate requires Core and repository checks, the **entire** iOS `KinTests` target including integration and rendered-layout tests, four exact smoke identities, and Release validation. Missing, skipped, failed, repeated, interrupted or incomplete selected tests and unverified required cleanup fail their jobs. The broader UI matrix runs only when explicitly dispatched through the manual diagnostic workflow, with its own failure status and artifacts. It is not part of automatic PR checks or a dependency of `validate`; this reduces automated end-to-end release assurance and requires the manual review below. Branch protections are unchanged.

This is a single comparison, not a measured failure rate or proof of stable future runs. Collect repeatability and changed-order evidence independently and preserve each result.

An additional standard trial on `eefc115` in [run 42105476611](https://github.com/dannydover/Kin/actions/runs/42105476611) recorded 164/164 iOS tests and 4/4 smoke tests passing with matching result hashes, but its required gate failed: iOS simulator shutdown and deletion timed out and inventory still reported the device present. The smoke starts matched the earlier order, so this is not changed-order evidence. No cleanup success is inferred from the hosted runner lifecycle.

The named random diagnostic branch uses a disposable random-order Xcode test plan for the same full iOS target and exact smoke selection; normal PRs continue using the standard scheme. Compare all four smoke start identities using `scripts/ci-compare-order.py BASELINE RANDOM --smoke`. For the iOS target, the retained progress record includes only three fixed, non-parameterized synthetic test-start categories; `--unit` compares those markers without collecting argument values. An unchanged, missing, or duplicated observed sequence is inconclusive, not a successful order test. This proves only the observed ordering of those selected markers, not the order of every iOS case. Core and Release checks are unchanged.

To run the broad suite for investigation or before release, dispatch `Manual broad UI diagnostics` with the exact full lowercase source commit SHA and the desired standard or random test order. The workflow verifies its checkout against that SHA, retains the SHA and order with each result, and fails for failed, missing, incomplete or skipped tests or unverified cleanup. Random order is only a configuration: compare retained test-start sequences before claiming the order changed. GitHub's manual-dispatch workflow must exist on the repository's default branch before it can be dispatched; a draft PR alone does not activate it.

## Coverage and limitations

| Behavior | Proposed blocking evidence | Still requires broader UI or manual review |
|---|---|---|
| Normal app launch, create, save and cold relaunch | `KinUITests.testNormalColdLaunchCreatesAndPersistsUncategorizedPerson` | The real Friend-on switch and its persistence, plus other onboarding, error and editing paths |
| Link, edit and reopen a relationship | `SmokeUITests.testRelationshipEditPersistsAfterRelaunch`; `PersonTests` and `SequentialImportRestartTests` | Other relationship roles, reversal, cancellation and accessibility permutations |
| Filters, birthdays, identity, cancellation, saving and reopening | Complete Core and iOS `KinTests` target, including `PeopleFilterStateTests`, `FilterStoreSequenceTests`, `ExistingContactBirthPreservationTests`, and store/relationship tests | The full range of rendered navigation, gestures and accessibility behavior |
| Contact and photo rules and persistence | `ContactPickerTests`, `ExistingContactBirthPreservationTests`, `ContactPhotoReviewTests`, `NewPersonImportTests`, `SequentialImportRestartTests`, and `PhotoProcessorTests` | Real system-picker presentation, selection, permission transitions and native payload delivery |
| Basic rendered People-screen layout | `RenderedLayoutTests` renders a person row at standard and largest text sizes. Two `SmokeUITests` verify the empty People screen's navigation and heading and retain real-app screenshots at those sizes. | Screenshots are evidence, not automated OCR, clipping, hit-target or VoiceOver proof; broad UI and device review remain necessary. Populated-screen layout is not covered by the screenshot pair. |

`ContactPhotoReviewTests.reviewedPhotoPersistsAcrossReopen` adds a lower-layer check that the exact reviewed adult-photo bytes and birthday survive a disk reopen without another Contacts read. It does not exercise the real picker or replace the manual system-picker review.

An attempted direct `ImageRenderer` test of the whole navigation screen crashed the hosted test process in [run 42082028247](https://github.com/dannydover/Kin/actions/runs/42082028247). That failed run remains visible; the real-app screenshot tests replace that unsuitable rendering method rather than claiming it passed.

The small smoke intentionally excludes real Contacts and Photos pickers. Repeated native picker failures and delays are documented in [run 42060127588](https://github.com/dannydover/Kin/actions/runs/42060127588) (ambiguous Contacts card), [run 42044257144](https://github.com/dannydover/Kin/actions/runs/42044257144) (Contacts card lookup), and [run 41942996537](https://github.com/dannydover/Kin/actions/runs/41942996537) (Photos loading). Other non-picker UI and simulator failures also occurred. These examples support reducing picker dependence in smoke; they do not establish a failure rate or an Apple root cause.

The full UI suite is a manual, separate, visible result. Its failed, skipped, interrupted or missing evidence must be reported as such; it is never reclassified as passing because the smaller gate passed. Removing it from automatic PR validation and from a release-blocking condition reduces automated end-to-end assurance and can miss regressions until someone runs it. Real native picker changes require the manual checks below on the actual release candidate.

## Short manual release checklist

Record the tested release-candidate build and device/OS, result, tester and any issue. Use synthetic or explicitly authorized data.

1. On the actual release candidate, launch, create and edit a person, link a relationship, background and reopen the app, and confirm saved data.
2. Check the changed screens at normal and largest text, and use VoiceOver for labels, order, controls and dismissal. Review visual clipping and hit targets on the device.
3. **When Contacts-related code, permissions, import review, mapping or affected platform behavior changes:** exercise real Contacts selection, cancel, review, save and relaunch; confirm the permission state and that unrelated contacts are not accessed.
4. **When Photos-related code, permissions, image processing, photo review or affected platform behavior changes:** select a real synthetic test image, cancel and save as applicable, relaunch and check the result and permission behavior.
5. Resolve failures or explicitly record an owner decision before release. Do not treat missing manual evidence, broad UI failures, or unavailable artifacts as passing validation.
