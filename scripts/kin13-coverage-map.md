# Kin 1.3 test coverage migration map

Baseline: 59 UI test methods and the existing KinTests suite. The import-route migration and two additional synthetic candidates are tracked below. Original rows remain required unless an assertion-level replacement is recorded and validated below. The assignments below describe the lowest layer that can verify the named behavior; a lower-level test does not prove presentation, focus, accessibility, gestures, or platform behavior. “Candidate” means not yet approved as equivalent coverage.

## Proposed first migration: reviewed imports from every entry point

| Existing assertion or behavior | Replacement or retained layer | Status |
|---|---|---|
| Reviewed name and stable identity; direct, parent, child, partner relationship; duplicate-save protection; listed vs unlisted; persistence after reopening | Integration: `NewPersonImportTests.entryPoints` plus new `entryPointsAfterReopen` | Passed in the unit-only retry of run 41230972213 (127 tests, zero skips). It does not drive the four UI routes. |
| Add person / parent / child / partner navigation, review, editing, Step parent UI, Save, and reopened values | App UI: `KinUITests.testSyntheticImportSavesReviewedNamesForEveryEntryPoint` uses a DEBUG-only fixed synthetic picker adapter and the same shared assertions | Passed once in run 41230972213. The synthetic adapter does not test system picker presentation or selection. |
| Picker delivers a real synthetic Contacts selection; edited review saves to profile and survives relaunch | Native end-to-end: `NativeContactsTests.testNativeFullBirthdayAndPhotoImportForAdultAndMinor` and `KinUITests.testNativeImportSavesReviewedName` | Retained; the latter runs the direct-entry path once instead of invoking the same system picker four times. All four app routes retain their review, save, relaunch, relationship and list assertions in the synthetic test. |


## Next candidate: unnamed draft review and cancellation

| Existing assertion or behavior | Candidate or retained layer | Status |
|---|---|---|
| Every creation route opens review without a current-draft label or temporary Person/Parent/Child/Partner identity; the selected synthetic name is shown | App UI: `testSyntheticUnnamedDraftReviewOmitsTemporaryIdentityInEveryCreationFlow` | Candidate shares the original assertions and needs hosted validation. |
| Cancelling review leaves the draft blank, does not create a person, and does not consume the next reference | The same synthetic app-UI candidate, plus the existing store cancellation and reference-identity integration tests | Candidate needs hosted validation. |
| Native picker actually selects a Contacts card and hands it to the review flow | Existing native `testUnnamedDraftContactsReviewOmitsTemporaryIdentityInEveryCreationFlow` and other native Contacts tests | Retained unchanged until the synthetic replacement is validated and any reduction is reviewed. |


## Reviewed deletion and filtering coverage (no UI retirement)

| Behavior or assertion | Lowest layer and evidence | Retained UI contract |
|---|---|---|
| Delete all removes listed and hidden people, notes, links and managed media atomically and remains deleted after reopen | Integration: `DeleteAllPeopleTests` all-people deletion | Confirmation, cancel, interruption and final screen in `DeleteAllPeopleUITests.testConfirmationCancelDismissInterruptionAndDeletionIncludeHiddenPeople` |
| Empty deletion is idempotent and does not save | Unit/integration: `DeleteAllPeopleTests` empty deletion | Disabled destructive action and accessible cancel at largest text remain in `testEmptyDeletionAtLargestTextHasSafeDisabledActionAndCancel` |
| Failed deletion preserves a consistent notebook before and after commit; protected-data interruption blocks deletion | Integration: `DeleteAllPeopleTests` failure and protected-data cases | UI error and absence of success confirmation remain in `testFailedDeletionRetainsPeopleAndNeverShowsSuccess` |
| Categories, uncategorized and hidden identities, search normalization, and combined filters return the expected people without mutating records | Unit: `CategoryFilterTests` in `NextVersionPolicyTests.swift`, and `IndexMembershipTests` | Menus, no-results explanations, keyboard dismissal, repeated Clear, category state, and actual record editing remain in the `IndexMembershipUITests` filtering/clear tests |
| Explicit list membership is independent of relationship and category, persists across reopen, and linked creation remains unlisted | Unit/integration: `IndexMembershipTests` defaults, legacy notebook and save failure; `PersonTests` membership | Direct Save navigation, edit/cancel, link creation and relaunch remain in the two direct-save UI tests |

These lower-level tests do not exercise the UI control wiring. They are not grounds to retire the listed UI assertions until a deterministic UI replacement is mapped and validated.


## Reviewed relationship, photo and picker boundaries

| Behavior or assertion | Lowest layer and existing evidence | Retained UI contract |
|---|---|---|
| Parent/child/partner identity, role direction, duplicate and cycle rejection, unlink semantics, relationship details and persistence | Integration: `PersonTests` relationship, cycle, unlink, attribute and relaunch cases | Relationship navigation, role labels, editable detail controls, cancellation, largest text and accessibility audits remain in `KinUITests`, `RelationshipActionTests`, and `RelationshipChooserTests` |
| Choice search, empty search, unlisted people, duplicate names and stable identity ordering | Unit: `ExistingPersonChoicesTests` | Search field, Back and Cancel, repeated selections and rendered chooser details remain in `RelationshipChooserTests` |
| Exact and estimated age, month boundaries, sixteen/eighteen thresholds, time zones and malformed input | Unit: `PersonAgeRegressionTests`, `NextReleaseTests`, and `PersonTests` age cases | Real wheel, cancel, largest-text rendering, age labels and profile visibility remain in the corresponding `KinUITests` age and baby-label tests |
| Photo eligibility, delayed reads, opt-in, cache isolation, save failure and cancellation | Integration: `ContactPhotoReviewTests`, `PersonContactImportTests`, `StoreSafetyTests` and `PersonTests` photo cases | Real Photos selection, removal alert, visible Cancel and saved photo after relaunch remain in `testPhotoRemovalAlertHasVisibleCancelAndPreservesSavedPhoto`; real Contacts photo review remains in `NativeContactsTests` |
| Picker configuration, once-only selection/cancel callbacks, stale callback invalidation and draft-before-save | Integration: `ContactPickerTests` | Native Contacts presentation, actual picker selection and review navigation remain in the native Contacts UI tests |
| Existing birthday precision, unknown/missing/yearless source handling, edited gender and identity after failed save or relaunch | Integration: `ExistingContactBirthPreservationTests` and `ContactBirthInformationTests` | Actual native selection, review controls, cancellation, visible values, photo choice and edit/save navigation remain in `ExistingContactPreservationUITests` |

These rows identify supported lower-level coverage and the UI assertions it does not replace. No test in these domains is retired by this map.


## Next candidate: deterministic filter fixture

`DevelopmentPreview.filterNotebook` seeds the same three listed synthetic people and categories used by the existing Clear tests. `DevelopmentPreviewTests.filterNotebook` checks the fixture identities, listed state, categories, and empty relationship graph. The candidate `testPreviewClearEmptyCategoryRestoresPeopleWithoutChangingRecords` retains the original empty-category, Clear restoration, keyboard, category-preservation and edit/cancel assertions. The original create-through-UI test remains required until both the fixture and the candidate pass hosted checks. Person creation, save, and reopen remain covered independently by the existing direct-save UI and storage tests. No production Release fixture is enabled; the existing Release guard rejects preview code.


## Accessibility, copy and visible layout

| Behavior or assertion | Lowest layer and evidence | Required UI contract |
|---|---|---|
| Offline name associations, default gender and sticky explicit choices | Unit: `NameAssociationsTests` and `DraftGenderDefault` cases in `NextVersionPolicyTests` | Search/filter and gender controls, explicit Unspecified, saved edits and largest-text audit remain in `NextVersionUITests` |
| Feature names appear as one accessible sentence and retain their visual emphasis | App UI: `testFeatureReferencesReadAsOneSentenceAtStandardText` and `...LargestText` | Both remain required; plain model tests cannot prove accessibility grouping or rendered text |
| Edit connection follows photo, and the Cancel background contains its label | App UI: standard- and largest-text `verifyEditorOrder` and `verifyCancelBackground` cases | Both sizes remain required; snapshots and bounds are not replaced by unit assertions |
| Relationship actions have usable layout and pass contrast, hit-region and clipping audits | App UI: `RelationshipActionTests` standard and largest sizes; integration contrast calculation in `NewPersonImportTests` supports color values | Real rendered controls and accessibility audits remain required; a color calculation is not a rendered audit |
| Empty-state illustration, recovery copy, navigation and search; privacy text; long names and infant labels | App UI: the corresponding `KinUITests` cases, with civil date calculations covered in `NextReleaseTests` | UI rendering, navigation and accessibility remain required; deterministic date arithmetic does not replace them |

No accessibility, visible-copy, or layout test is retired by this map.

## UI baseline inventory

Layer key: **native** = real platform integration; **app UI** = navigation, interaction, visual or accessibility contract; **integration** = persistence, importer or callback behavior; **unit** = pure model/policy behavior. Mixed tests remain UI tests until every unique UI assertion has a validated replacement. For every row marked Retain, the old-to-new mapping is the same named test and its existing helper calls: all assertions remain required at the UI layer. The lower layers listed are review candidates, not claims that their assertions are interchangeable. The import-route migration is the only exception and is itemized above; its native coverage tradeoff is explicit.

| Existing UI test | Candidate lowest layers to review | Decision |
|---|---|---|
| `DeleteAllPeopleUITests.testConfirmationCancelDismissInterruptionAndDeletionIncludeHiddenPeople` | app UI, integration | Retain; assertion-level review pending. |
| `DeleteAllPeopleUITests.testEmptyDeletionAtLargestTextHasSafeDisabledActionAndCancel` | app UI, integration | Retain; assertion-level review pending. |
| `DeleteAllPeopleUITests.testFailedDeletionRetainsPeopleAndNeverShowsSuccess` | app UI, integration | Retain; assertion-level review pending. |
| `ExistingContactPreservationUITests.testExistingBirthInformationSurvivesMissingAndYearlessContactsReview` | native, app UI, integration | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testDirectSaveWithoutCategoryOpensProfileAndMembershipSurvivesCategoryEditsCancelAndRelaunch` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testDirectFailedSaveAndCancelDoNotCreatePeopleAndLinkedCreationStaysUnlisted` | app UI, integration | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testCategoryFilterCombinesSearchKeepsUncategorizedAndPreservesSelectionAfterCancel` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testClearSearchRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testPreviewClearEmptyCategoryRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Candidate for the empty-category clear path using a verified synthetic fixture; the original creation-through-UI test remains required until validation. |
| `IndexMembershipUITests.testClearEmptyCategoryRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testClearCombinedSearchAndCategoryRepeatedlyPreservesPeople` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testClearAllPeopleSearchRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testClearSearchAndFiltersOnEmptyNotebookAtLargestText` | app UI, integration, unit | Retain; assertion-level review pending. |
| `KinUITests.testNormalColdLaunchOpensNotebookAndPreservesSavedPerson` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testSyntheticUnnamedDraftReviewOmitsTemporaryIdentityInEveryCreationFlow` | app UI, integration | Candidate; all existing unnamed-draft assertions run through a synthetic adapter. Native version retained pending hosted validation. |
| `KinUITests.testUnnamedDraftContactsReviewOmitsTemporaryIdentityInEveryCreationFlow` | native, app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testRelationshipRoleLabelsFromBothDirectionsAndForPartners` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testRelationshipRoleLabelsWrapLongNamesAtLargestDynamicType` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testAddParentsReuseAndCancel` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testAddParentsDuplicateRejectionPreservesBothPeople` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testAddParentsReverseCycleRejectionAndDraftCancellation` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testAddParentsCreatePersistNavigateAndUnlink` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testAddParentUsesSharedContactsReviewAndKeepsNewParentUnlisted` | native, app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testSharedEditorUnlistedRecoveryCancelAndRelaunch` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testReuseExistingPartnerUnlinkAndDeletePreservesOtherPerson` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testNewPartnerDefaultsCurrentAndSelectionRemainsUnsaved` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testSharedChildReuseAndRenameAcrossBothParents` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testAllPeopleOpensProfilesAndReturnsToSameIndex` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testPrivacyPolicyIsFinalAboutSectionAtNormalAndLargestText` | app UI | Retain; assertion-level review pending. |
| `KinUITests.testIllustratedEmptyStateMenuAndSearchRecovery` | app UI, unit | Retain; assertion-level review pending. |
| `KinUITests.testBlankNameEditsCancelAndLaterNamingPreserveEntry` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testEmptyStateAtLargestDynamicType` | app UI | Retain; assertion-level review pending. |
| `KinUITests.testFormSurfacesAndDestructiveControls` | app UI | Retain; assertion-level review pending. |
| `KinUITests.testYoungProfileHidesPartnerAndChildSectionsButUnknownAgeDoesNot` | app UI, integration, unit | Retain; assertion-level review pending. |
| `KinUITests.testEstimatedAgeWheelBoundariesAndCancel` | app UI, integration, unit | Retain; assertion-level review pending. |
| `KinUITests.testEstimatedAgeWheelAtLargestDynamicType` | app UI, unit | Retain; assertion-level review pending. |
| `KinUITests.testPhotoRemovalAlertHasVisibleCancelAndPreservesSavedPhoto` | native, app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testContactMissingBirthdayPromptCancellationAndEstimatedImport` | native, app UI, integration, unit | Retain; assertion-level review pending. |
| `KinUITests.testSyntheticImportSavesReviewedNamesForEveryEntryPoint` | app UI, integration | Passed once in run 41230972213; retains all four route assertions. |
| `KinUITests.testNewImportSavesReviewedNamesForEveryEntryPoint` | app UI, integration, native | Replaced by the synthetic four-route test and one native direct-route smoke above; verify the new exact head before accepting this migration. |
| `KinUITests.testNativeImportSavesReviewedName` | native, app UI | New one-route native smoke; required. |
| `KinUITests.testChildSurnameIsEditableClearableAndNeverReapplied` | app UI, integration, unit | Retain; assertion-level review pending. |
| `KinUITests.testImportReviewRetainsFailedEditsAndAccessibilityHelpersWrap` | native, app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testCompactUnknownAgeWithLongNamesAtStandardAndAccessibilitySizes` | app UI, unit | Retain; assertion-level review pending. |
| `KinUITests.testBabyMonthLabelsFitIndexAndDetail` | app UI, unit | Retain; assertion-level review pending. |
| `NativeContactsTests.testNativeFullBirthdayAndPhotoImportForAdultAndMinor` | native, app UI, integration, unit | Retain; assertion-level review pending. |
| `NextVersionUITests.testOfflineAutomaticGenderManualUnspecifiedAndSavedEditPreservation` | app UI, integration, unit | Retain; assertion-level review pending. |
| `NextVersionUITests.testPeopleFilterAndGenderControlsAtLargestTextWithUnfilteredAudit` | app UI, integration, unit | Retain; assertion-level review pending. |
| `NextVersionUITests.testEditConnectionFollowsPhotoAtStandardText` | native, app UI, integration | Retain; assertion-level review pending. |
| `NextVersionUITests.testEditConnectionFollowsPhotoAtLargestText` | native, app UI, integration | Retain; assertion-level review pending. |
| `NextVersionUITests.testEditorCancelBackgroundContainsLabelAtStandardText` | app UI, integration | Retain; assertion-level review pending. |
| `NextVersionUITests.testEditorCancelBackgroundContainsLabelAtLargestText` | app UI, integration | Retain; assertion-level review pending. |
| `NextVersionUITests.testFeatureReferencesReadAsOneSentenceAtStandardText` | app UI | Retain; assertion-level review pending. |
| `NextVersionUITests.testFeatureReferencesReadAsOneSentenceAtLargestText` | app UI | Retain; assertion-level review pending. |
| `RelationshipActionTests.testRelationshipActionsAtStandardSize` | app UI, integration | Retain; assertion-level review pending. |
| `RelationshipActionTests.testRelationshipActionsAtLargestSize` | app UI, integration | Retain; assertion-level review pending. |
| `RelationshipActionTests.testSharedActionAuditAtStandardSize` | app UI | Retain; assertion-level review pending. |
| `RelationshipActionTests.testSharedActionAuditAtLargestSize` | app UI | Retain; assertion-level review pending. |
| `RelationshipChooserTests.testParentChildPartnerShowDetailsLastAndVisiblePeopleNeedNoSearch` | app UI, integration, unit | Retain; assertion-level review pending. |
| `RelationshipChooserTests.testSearchDuplicatesBackCancelAndRepeatedSelectionPreserveIdentityAndDetails` | app UI, integration, unit | Retain; assertion-level review pending. |
| `RelationshipChooserTests.testEmptyChooserAndPartnerDetailsSurviveBackAndCancel` | app UI, integration | Retain; assertion-level review pending. |
| `RelationshipChooserTests.testSyntheticRelationshipReviewScreenshots` | app UI, integration | Retain; assertion-level review pending. |
| `SyntheticContactsCleanupTests.testOwnedFixtureCleanupHandlesEmptyPartialAndFailures` | integration | Retain; assertion-level review pending. |

## Release gate and acceptance

- Keep every current UI test and `validate` required; migrate an old assertion only after its replacement is recorded and validated. No skip, retry-to-green, or passing status for a failed native journey.
- A smaller required UI set must still include real Contacts and Photos, core navigation and data persistence, destructive-action safety, and representative accessibility sizes. The migration above removes three repeated native picker invocations; all other membership and cadence still require assertion-level review.
- Validate lower-level replacements first, then any UI change on the exact commit. Exercise bounded repeated full suites and relevant order variation; report every failure and retain artifacts. A single green run is not a reliability guarantee.
- Historical native focus, picker readiness, Friend switch, Clear restoration and accessibility query stalls remain unresolved. Resource free/inactive counters are not a direct memory-pressure measurement.
