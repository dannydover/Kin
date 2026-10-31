# Kin 1.3 test coverage migration map

Baseline: 59 UI test methods and the existing KinTests suite; one synthetic replacement candidate is added alongside them. All rows remain required while replacements are validated. The assignments below describe the lowest layer that can verify the named behavior; a lower-level test does not prove presentation, focus, accessibility, gestures, or platform behavior. “Candidate” means not yet approved as equivalent coverage.

## Proposed first migration: reviewed imports from every entry point

| Existing assertion or behavior | Replacement or retained layer | Status |
|---|---|---|
| Reviewed name and stable identity; direct, parent, child, partner relationship; duplicate-save protection; listed vs unlisted; persistence after reopening | Integration: `NewPersonImportTests.entryPoints` plus new `entryPointsAfterReopen` | Candidate; new parameterized test needs hosted validation. It does not drive the four UI routes. |
| Add person / parent / child / partner navigation, review, editing, Step parent UI, Save, and reopened values | Candidate app UI: `KinUITests.testSyntheticImportSavesReviewedNamesForEveryEntryPoint` uses a DEBUG-only fixed synthetic picker adapter; existing native route test remains unchanged | Candidate requires hosted validation; the synthetic adapter does not test system picker presentation or selection. |
| Picker delivers a real synthetic Contacts selection; edited review saves to profile and survives relaunch | Native end-to-end: `NativeContactsTests.testNativeFullBirthdayAndPhotoImportForAdultAndMinor` and `KinUITests.testNewImportSavesReviewedNamesForEveryEntryPoint` | Retained; no native journey retired. |

## UI baseline inventory

Layer key: **native** = real platform integration; **app UI** = navigation, interaction, visual or accessibility contract; **integration** = persistence, importer or callback behavior; **unit** = pure model/policy behavior. Mixed tests remain UI tests until every unique UI assertion has a validated replacement.

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
| `IndexMembershipUITests.testClearEmptyCategoryRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testClearCombinedSearchAndCategoryRepeatedlyPreservesPeople` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testClearAllPeopleSearchRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testClearSearchAndFiltersOnEmptyNotebookAtLargestText` | app UI, integration, unit | Retain; assertion-level review pending. |
| `KinUITests.testNormalColdLaunchOpensNotebookAndPreservesSavedPerson` | app UI, integration | Retain; assertion-level review pending. |
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
| `KinUITests.testSyntheticImportSavesReviewedNamesForEveryEntryPoint` | app UI, integration | Candidate replacement; run and review before retiring any native repetition. |
| `KinUITests.testNewImportSavesReviewedNamesForEveryEntryPoint` | native, app UI, integration | Retain; assertion-level review pending. |
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

- Keep existing full UI selection and `validate` required until replacement tests and the assertion-level map have been reviewed and validated. No skip, retry-to-green, or passing status for a failed native journey.
- A smaller required UI set must still include real Contacts and Photos, core navigation and data persistence, destructive-action safety, and representative accessibility sizes. Exact membership and cadence require a coverage review; none has been removed by this map.
- Validate lower-level replacements first, then any UI change on the exact commit. Exercise bounded repeated full suites and relevant order variation; report every failure and retain artifacts. A single green run is not a reliability guarantee.
- Historical native focus, picker readiness, Friend switch, Clear restoration and accessibility query stalls remain unresolved. Resource free/inactive counters are not a direct memory-pressure measurement.
