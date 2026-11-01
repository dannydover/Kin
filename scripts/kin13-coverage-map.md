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
| Every creation route opens review without a current-draft label or temporary Person/Parent/Child/Partner identity; the selected synthetic name is shown | App UI: `testSyntheticUnnamedDraftReviewOmitsTemporaryIdentityInEveryCreationFlow` | Passed once in run 41240567374 with the original assertions; exact migrated head still needs full validation. |
| Cancelling review leaves the draft blank, does not create a person, and does not consume the next reference | The same synthetic app-UI candidate, plus the existing store cancellation and reference-identity integration tests | Candidate passed once in run 41240567374; exact migrated head still needs validation. |
| Native picker actually selects a Contacts card and hands it to the review flow | `testNativeUnnamedDraftReviewOmitsTemporaryIdentity` and other native Contacts tests | One native direct-entry review remains; the synthetic test retains all four route assertions. Three repeated native invocations are removed. |


## Reviewed deletion and filtering coverage (no UI retirement)

| Behavior or assertion | Lowest layer and evidence | Retained UI contract |
|---|---|---|
| Delete all removes listed and hidden people, notes, links and managed media atomically and remains deleted after reopen | Integration: `DeleteAllPeopleTests` all-people deletion | Confirmation, cancel, interruption and final screen in `DeleteAllPeopleUITests.testConfirmationCancelDismissInterruptionAndDeletionIncludeHiddenPeople` |
| Empty deletion is idempotent and does not save | Unit/integration: `DeleteAllPeopleTests` empty deletion | Disabled destructive action and accessible cancel at largest text remain in `testEmptyDeletionAtLargestTextHasSafeDisabledActionAndCancel` |
| Failed deletion preserves a consistent notebook before and after commit; protected-data interruption blocks deletion | Integration: `DeleteAllPeopleTests` failure and protected-data cases | UI error and absence of success confirmation remain in `testFailedDeletionRetainsPeopleAndNeverShowsSuccess` |
| Categories, uncategorized and hidden identities, search normalization, and combined filters return the expected people without mutating records | Unit: `CategoryFilterTests` in `NextVersionPolicyTests.swift`, and `IndexMembershipTests` | Menus, no-results explanations, keyboard dismissal, repeated Clear, category state, and actual record editing remain in the `IndexMembershipUITests` filtering/clear tests |
| Explicit list membership is independent of relationship and category, persists across reopen, and linked creation remains unlisted | Unit/integration: `IndexMembershipTests` defaults, legacy notebook and save failure; `PersonTests` membership | Direct Save navigation, edit/cancel, link creation and relaunch remain in the two direct-save UI tests |

These lower-level tests do not exercise the UI control wiring. They are not grounds to retire the listed UI assertions until a deterministic UI replacement is mapped and validated.

### Deletion UI assertion inventory

The three original deletion UI tests remain required while the candidates are validated. This inventory makes their distinct contracts explicit.

Two local split-test candidates use separate persisted synthetic notebooks: one exercises confirmation Cancel, sheet dismissal and interruption; the other confirms deletion and verifies listed and hidden people remain absent after relaunch. Their assertions and synthetic scope/confirmation screenshots map to the compound original below. They have not yet been run; the original remains required. The split is intended to isolate independent user journeys within the existing per-test allowance, not to establish the cause of the four-minute timeout in run 41275059980 or to replace lower-level deletion and failure tests.

| Existing assertion | Required owner | Supporting lower-level coverage |
|---|---|---|
| Menu action is visible and hittable, including at the largest text size, and opens the deletion screen | All three deletion UI tests through `open` | None: rendered menu bounds and navigation need UI. |
| A listed person and hidden linked child produce one People row and a two-person deletion count | `testConfirmationCancelDismissInterruptionAndDeletionIncludeHiddenPeople` | `DeleteAllPeopleTests.allPeopleAndMedia` verifies deletion of listed and hidden records. |
| Confirmation names backup implications and offers a hittable Cancel; cancelling either confirmation or sheet preserves the listed person | Same UI test through `review` and cancel paths | Store deletion tests do not establish the confirmation copy or control behavior. |
| Interactive sheet dismissal and terminating while confirmation is open preserve records, including the hidden child after relaunch | Same UI test | `DeleteAllPeopleTests.protectedAndInterrupted` checks unconfirmed interruption at the storage boundary, not the actual sheet or app relaunch. |
| Confirming deletion produces an empty People screen and no listed or hidden records after relaunch | Same UI test | `DeleteAllPeopleTests.allPeopleAndMedia` additionally verifies notes, links and managed media after reopening. |
| Empty notebook shows its count, disables the destructive action, offers usable Cancel at largest text, and does not show a confirmation | `testEmptyDeletionAtLargestTextHasSafeDisabledActionAndCancel` | `DeleteAllPeopleTests.empty` checks empty deletion is idempotent and does not save. |
| A failed deletion reports its error on both attempts, leaves the deletion sheet open with the five-person count, and retains all people | `testFailedDeletionRetainsPeopleAndNeverShowsSuccess` | `DeleteAllPeopleTests.failure` verifies consistent reopened state for failures before and after commit; it does not cover the UI error or sheet. Success dismisses the sheet; there is no separate success message in the current view. |


## Reviewed relationship, photo and picker boundaries

| Behavior or assertion | Lowest layer and existing evidence | Retained UI contract |
|---|---|---|
| Parent/child/partner identity, role direction, duplicate and cycle rejection, unlink semantics, relationship details and persistence | Integration: `PersonTests` relationship, cycle, unlink, attribute and relaunch cases | Relationship navigation, role labels, editable detail controls, cancellation, largest text and accessibility audits remain in `KinUITests`, `RelationshipActionTests`, and `RelationshipChooserTests` |
| Choice search, empty search, unlisted people, duplicate names and stable identity ordering | Unit: `ExistingPersonChoicesTests` | Search field, Back and Cancel, repeated selections and rendered chooser details remain in `RelationshipChooserTests` |
| Exact and estimated age, month boundaries, sixteen/eighteen thresholds, time zones and malformed input | Unit: `PersonAgeRegressionTests`, `NextReleaseTests`, and `PersonTests` age cases | Real wheel, cancel, largest-text rendering, age labels and profile visibility remain in the corresponding `KinUITests` age and baby-label tests |
| Photo eligibility, delayed reads, opt-in, cache isolation, save failure and cancellation | Integration: `ContactPhotoReviewTests`, `PersonContactImportTests`, `StoreSafetyTests` and `PersonTests` photo cases | Real Photos selection, removal alert, visible Cancel and saved photo after relaunch remain in `testPhotoRemovalAlertHasVisibleCancelAndPreservesSavedPhoto`; real Contacts photo review remains in `NativeContactsTests` |
| Picker configuration, once-only selection/cancel callbacks, stale callback invalidation and draft-before-save | Integration: `ContactPickerTests` | Native Contacts presentation, actual picker selection and review navigation remain in the native Contacts UI tests |
| Existing birthday precision, unknown/missing/yearless source handling, edited gender and identity after failed save or relaunch | Integration: `ExistingContactBirthPreservationTests` and `ContactBirthInformationTests` | Actual native selection, review controls, cancellation, visible values, photo choice and edit/save navigation remain in `ExistingContactPreservationUITests` |

These rows identify supported lower-level coverage and the UI assertions it does not replace. The preservation migration below is the only retirement in these domains.

### Existing-contact preservation candidate

`testSyntheticExistingBirthInformationSurvivesMissingAndYearlessContactsReview` runs the same review, cancel, save, identity and birthday assertions as the former native preservation test using four fixed DEBUG-only snapshots. It does not access the simulator address book. Both paths passed in runs 41271020900 and 41273073951, and the coordinator payload conversion test passed in 41273073951. The five repeated native selections in this business-rule matrix are now removed; the retained native smoke, missing-birthday journey, and adult/minor birthday/photo journey still exercise real picker presentation, selection and payload conversion. The synthetic test cannot establish that the system picker returns a yearless birthday: that variant is checked through an in-memory Contacts payload and the coordinator, a documented reduction in native-system coverage. On the migrated head, the synthetic test passed in run 41275059980, but the full run failed three other UI tests (192/195 passed, zero skips). Full validation and repeatability remain unresolved.

| Existing assertion | Required owner and lower-level boundary |
|---|---|
| Three existing records begin with exact, estimated or unknown birth information; missing and yearless selected cards show the preservation explanation and the matching current kind | Required synthetic UI matrix; `ExistingContactBirthPreservationTests.unusable` and `reviewDefaults` exercise the rules independently. |
| No-photo confirmation is initially off for the first two applicable reviews; cancelling the first review restores its unsaved name before selecting again | Required synthetic UI matrix; integration review and cancellation checks do not prove the displayed control or dismissal behavior. |
| Saving each imported name preserves its original birth kind and original identity in the editor and detail view | Required synthetic UI matrix; integration `persistence` checks stored identity, age and links after reopening. |
| Selecting a full 1995 birthday omits the preservation explanation, replaces the prior age, preserves the original identity, and leaves three people in the index | Required synthetic UI matrix; `ContactBirthInformationTests` and `ExistingContactBirthPreservationTests.explicitChanges` cover conversion and replacement separately. |
| Native selection delivers the selected card's real birthday fields and returns from the platform picker | Retained native missing-birthday and full-birthday/photo journeys; yearless conversion is covered by the coordinator payload test, not a real native selection. Direct `ContactSnapshot` construction cannot prove the adapter contract. |

`PersonContactImportTests.preservationPickerPayloads` checks conversion of real in-memory `CNMutableContact` payloads with missing, yearless, and exact birthdays through the picker coordinator; it passed in run 41273073951. It cannot replace real platform-picker presentation or selection.

The separate `NativeContactsTests.testNativeFullBirthdayAndPhotoImportForAdultAndMinor` remains required: it selects adult and minor synthetic Contacts cards, checks the native birthday/photo review, edited gender, the Friend control, age-appropriate photo behavior, and saved birthday after relaunch. Its two selections exercise distinct eligibility outcomes but also repeat picker setup; lower-level photo eligibility tests alone do not establish the native payload, preview, rendered control, or saved UI journey.

The retained `KinUITests.testContactMissingBirthdayPromptCancellationAndEstimatedImport` checks a separate real-system journey: a saved estimated-age adult receives a Photos image; a missing-birthday Contacts review shows the current draft and both exact/unknown choices; Cancel restores the draft; explicitly choosing Unknown followed by an unsaved estimated-age edit and Cancel preserves the earlier saved age; a subsequent import with a confirmed estimate saves and survives relaunch. Its real Photos picker, native Contacts selection, visible age controls and cancel/save navigation are not covered by the synthetic preservation candidate. The `ExistingContactBirthPreservationTests` and `ContactPhotoReviewTests` cases support the underlying age, opt-in and cancellation rules, but do not replace these UI assertions. This journey remains required.

The shared native-search helper's failure-only diagnostic records the last observed total search fields, in-bounds fields, and hittable in-bounds fields. It records no names or coordinates and performs no new accessibility query after failure. This can distinguish some failed uniqueness, bounds and hit-testing preconditions; it does not establish why a native search field was inaccessible or repair the failure. The existing five-second assertion and exact-result checks remain unchanged.

### Relationship chooser UI assertion inventory

All four chooser tests remain required. The existing `ExistingPersonChoicesTests` can validate choice data and identity independently; it does not validate any of the following rendered or navigation behavior.

| Existing assertion | Required UI owner |
|---|---|
| Parent, child and partner routes place relationship details after the link action, start without a hittable search field or keyboard, show a selectable person, and navigate to one saved relationship and the same person's edit control | `testParentChildPartnerShowDetailsLastAndVisiblePeopleNeedNoSearch` |
| Duplicate names display distinct notebook references; empty search has no choices and clearing it restores them; Back and Cancel retain Step detail without saving; saving the selected identity leads to one matching relationship and edit control, with five people in All people | `testSearchDuplicatesBackCancelAndRepeatedSelectionPreserveIdentityAndDetails` |
| Empty chooser has no selectable people, Back preserves Former partner status, and Cancel creates no relationship | `testEmptyChooserAndPartnerDetailsSurviveBackAndCancel` |
| Synthetic screenshots capture options, selectable person, empty search and the accessibility-size chooser; the test also checks the synthetic fixture and key controls | `testSyntheticRelationshipReviewScreenshots` |

### Relationship action UI assertion inventory

`testRelationshipActionsAtStandardSize` and `testRelationshipActionsAtLargestSize` both remain required. For partner, child and parent they check the action's visible hit target and bounds, the corresponding Add target, navigation to the correct editor, rendered relationship roles and parent/child directions, and Cancel preserving the action. They also open and cancel the Add route and verify the deletion screen still reports five people and the expected scope wording. The largest-text case additionally checks expanded height; the standard case checks both actions are simultaneously hittable for one fixture. Store and relationship tests support identity and persistence rules but cannot establish these rendered or navigation assertions.

`testSharedActionAuditAtStandardSize` and `testSharedActionAuditAtLargestSize` remain required. Each checks the fixed synthetic control is present, hittable and at least 44 points high, then runs the unfiltered contrast, hit-region, clipping and trait audit and retains a screenshot. These are accessibility/rendered contracts; model color calculations do not replace them.


## Next candidate: deterministic filter fixture

`DevelopmentPreview.filterNotebook` seeds the same three listed synthetic people and categories used by the existing Clear tests. `DevelopmentPreviewTests.filterNotebook` checks the fixture identities, listed state, categories, and empty relationship graph. The candidate `testPreviewClearEmptyCategoryRestoresPeopleWithoutChangingRecords` retains the original empty-category, Clear restoration, keyboard, category-preservation and edit/cancel assertions. Both the fixture integration test and candidate passed in run 41240567374. The original empty-category test now uses that fixture and retains every Clear, keyboard, category and edit/cancel assertion; its three repeated setup-only person creations are removed. Person creation, save, and reopen remain covered independently by the existing direct-save UI and storage tests. This in-memory fixture does not itself prove disk persistence. The migrated head still needs validation. No production Release fixture is enabled; the existing Release guard rejects preview code.


## Accessibility, copy and visible layout

| Behavior or assertion | Lowest layer and evidence | Required UI contract |
|---|---|---|
| Offline name associations, default gender and sticky explicit choices | Unit: `NameAssociationsTests` and `DraftGenderDefault` cases in `NextVersionPolicyTests` | Search/filter and gender controls, explicit Unspecified, saved edits and largest-text audit remain in `NextVersionUITests` |
| Feature names appear as one accessible sentence and retain their visual emphasis | App UI: `testFeatureReferencesReadAsOneSentenceAtStandardText` and `...LargestText` | Both remain required; plain model tests cannot prove accessibility grouping or rendered text |
| Edit connection follows photo, and the Cancel background contains its label | App UI: standard- and largest-text `verifyEditorOrder` and `verifyCancelBackground` cases | Both sizes remain required; snapshots and bounds are not replaced by unit assertions |
| Relationship actions have usable layout and pass contrast, hit-region and clipping audits | App UI: `RelationshipActionTests` standard and largest sizes; integration contrast calculation in `NewPersonImportTests` supports color values | Real rendered controls and accessibility audits remain required; a color calculation is not a rendered audit |
| Empty-state illustration, recovery copy, navigation and search; privacy text; long names and infant labels | App UI: the corresponding `KinUITests` cases, with civil date calculations covered in `NextReleaseTests` | UI rendering, navigation and accessibility remain required; deterministic date arithmetic does not replace them |

No accessibility, visible-copy, or layout test is retired by this map.

### Next-version UI assertion inventory

| Retained UI test or shared helper | Assertions that remain at the UI layer | Lower-level support and limit |
|---|---|---|
| `testOfflineAutomaticGenderManualUnspecifiedAndSavedEditPreservation` | Automatic gender follows recognized and unrecognized names; explicit Unspecified and Other remain sticky through later name edits; Save displays Other and Cancel preserves the saved person. | `NameAssociationsTests` and `DraftGenderDefault` cover mappings and sticky state, not control binding or Save/Cancel navigation. |
| `testPeopleFilterAndGenderControlsAtLargestTextWithUnfilteredAudit` | Filter and gender controls are hittable and at least 44 points; full rows are revealed; unfiltered contrast, hit-region, clipping and trait audits pass; Cancel returns to People. | No lower-level test proves rendered accessibility or layout. |
| `verifyEditorOrder`, standard and largest text | Scrolling encounters Photo before Your connection in visual and accessibility reading order; Cancel returns to the same profile. | Store/photo rules do not prove visual ordering. |
| `verifyCancelBackground`, standard and largest text | Settled toolbar geometry contains one rendered Cancel label with horizontal inset, a minimum 44-point hit target, no Save overlap, and both controls hittable; Cancel returns to the profile. | Model tests cannot prove native toolbar layout or rendered glyph bounds. |
| `verifyFeatureReferences`, standard and largest text | Guidance appears and remains hittable in bounds as one exact accessibility sentence without raw styling markers; navigation returns to the profile. | No model test proves accessibility grouping and rendered layout. |




## Clear-flow assertion mapping

| Original assertion | Current or proposed owner | Migration status |
|---|---|---|
| Search-only shows the exact no-matches explanation and a hittable Clear action | `testClearSearchRestoresPeopleWithoutChangingRecords` app UI | Retained with synthetic setup after its matching candidate passed; validate the current head. |
| Empty category shows its explanation before Clear | `testClearEmptyCategoryRestoresPeopleWithoutChangingRecords` app UI | Retained with synthetic setup after its matching candidate passed; validate the current head. |
| Combined category/search shows no matches and can Clear twice | Original `testClearCombinedSearchAndCategoryRepeatedlyPreservesPeople` app UI | Retained with original setup. Its preview candidate failed the restoration wait and is not an approved replacement. |
| All people scope is entered before clearing search | `testClearAllPeopleSearchRestoresPeopleWithoutChangingRecords` app UI | Retained with synthetic setup after its matching candidate passed; validate the current head. |
| Clear returns to People, category All, three rows, visible Alex and no Clear action; keyboard closes | Shared `assertClearSearchRestored` app-UI assertions remain on every scenario | Retained. The local `PeopleFilterStateTests.clear` separately checks the reset rules for 36 combinations but cannot prove these rendered results or keyboard dismissal. |
| Jamie's Friend category survives Clear and edit/cancel | Shared `assertClearSearchPreservedCategory` app UI | Retained for every scenario. Existing store/category tests cover record semantics separately. |
| Three people can be created, saved and navigated to from the editor | Existing direct-save and membership UI and integration tests | No longer repeated solely as setup in the migrated search-only, empty-category, and All people cases; combined-filter original still performs its original setup. The fixture integrity test checks the synthetic setup itself. |

The in-memory fixture does not prove disk persistence. No failed wait is converted into a passing result.

### Membership and filtering UI assertion inventory

| Retained UI test | UI assertions and lower-level boundary |
|---|---|
| `testDirectSaveWithoutCategoryOpensProfileAndMembershipSurvivesCategoryEditsCancelAndRelaunch` | Direct Save without a category opens the listed profile; membership survives category edit, Cancel and relaunch; removing membership hides the person from People while preserving All people. `IndexMembershipTests` supports membership persistence but not this navigation and rendered state. |
| `testDirectFailedSaveAndCancelDoNotCreatePeopleAndLinkedCreationStaysUnlisted` | Failed long-name Save retains the edit and Cancel creates no person; a linked child defaults unlisted, remains accessible from its relationship and All people, and the main list remains unchanged after relaunch. Store failure and inclusion tests do not prove these screen transitions. |
| `testCategoryFilterCombinesSearchKeepsUncategorizedAndPreservesSelectionAfterCancel` | Friend filtering, search with no matches, empty category, restoring All and an uncategorized person, and preserving the selected category after edit/Cancel remain visible. `CategoryFilterTests` covers result selection without proving control wiring. |
| `testClearSearchAndFiltersOnEmptyNotebookAtLargestText` | The Clear action is hittable and at least 44 points, both ends of the recovery explanation can be revealed, and clearing from empty search or category restores an empty People screen and All category. No model test proves text readability or interaction at this size. |

The remaining Clear scenarios and their record-preservation assertions are mapped immediately above. No membership or filtering UI assertion is retired by these rows.

## Filter-state extraction candidate

`PeopleFilterState` holds the exact display scope, query, category, and search-presentation state previously owned individually by `ContentView`. `PeopleFilterStateTests` checks Clear across 36 input combinations, idempotence, listed/hidden results and unchanged people, scope switching while preserving search presentation, Search all behavior, and whitespace handling. The view still wires the real Clear button, menu, search field and keyboard; the existing UI tests remain required until the refactor and mapped replacements pass hosted validation. The extracted state does not test SwiftUI animation, accessibility snapshots, or native controls.

## Further filter fixture candidates

The search-only, combined search/category, and All people Clear tests each had a separate preview-fixture candidate calling the same assertion helper as the original. The search-only and All people candidates passed in run 41245990817 and are mapped back to their original test names. The combined-filter candidate failed; its creation-through-UI original remains required. If each candidate passes, the original test name can use the validated fixture and the duplicate candidate can be removed; the keyboard, no-results copy, repeated Clear, scope, category, identity and edit/cancel assertions stay intact. This moves setup only, not the UI behavior under test. The fixture is in-memory and is not evidence of disk persistence. The combined-filter candidate failed in run 41245990817 and is not a validated replacement; a late observation does not turn its failure into a pass. In run 41248595158 the same candidate exceeded four minutes during repeated XCTest animation-idle waits around menu taps; the cause is unresolved. Both original and candidate stay required.

## UI baseline inventory

Layer key: **native** = real platform integration; **app UI** = navigation, interaction, visual or accessibility contract; **integration** = persistence, importer or callback behavior; **unit** = pure model/policy behavior. Mixed tests remain UI tests until every unique UI assertion has a validated replacement. For every row marked Retain, the old-to-new mapping is the same named test and its existing helper calls: all assertions remain required at the UI layer. The lower layers listed are review candidates, not claims that their assertions are interchangeable. Import-route and preservation migrations are itemized above, including their native coverage tradeoffs.

| Existing UI test | Candidate lowest layers to review | Decision |
|---|---|---|
| `DeleteAllPeopleUITests.testConfirmationCancelDismissInterruptionAndDeletionIncludeHiddenPeople` | app UI, integration | Retain; assertion-level review pending. |
| `DeleteAllPeopleUITests.testCandidateDeletionCancelDismissAndInterruptedConfirmation` | app UI, integration | Unvalidated candidate; compound original retained. |
| `DeleteAllPeopleUITests.testCandidateDeletionPersistsForListedAndHiddenPeople` | app UI, integration | Unvalidated candidate; compound original retained. |
| `DeleteAllPeopleUITests.testEmptyDeletionAtLargestTextHasSafeDisabledActionAndCancel` | app UI, integration | Retain; assertion-level review pending. |
| `DeleteAllPeopleUITests.testFailedDeletionRetainsPeopleAndNeverShowsSuccess` | app UI, integration | Retain; assertion-level review pending. |
| `ExistingContactPreservationUITests.testExistingBirthInformationSurvivesMissingAndYearlessContactsReview` | native, app UI, integration | Replaced by the synthetic review matrix and payload-conversion test above; validate the migrated head. Real picker journeys remain required. |
| `ExistingContactPreservationUITests.testSyntheticExistingBirthInformationSurvivesMissingAndYearlessContactsReview` | app UI, integration | Passed in runs 41271020900, 41273073951 and migrated-head 41275059980; remains required. The latter full run failed other tests. |
| `IndexMembershipUITests.testDirectSaveWithoutCategoryOpensProfileAndMembershipSurvivesCategoryEditsCancelAndRelaunch` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testDirectFailedSaveAndCancelDoNotCreatePeopleAndLinkedCreationStaysUnlisted` | app UI, integration | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testCategoryFilterCombinesSearchKeepsUncategorizedAndPreservesSelectionAfterCancel` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testPreviewClearSearchRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Passed in run 41245990817; shared assertions move to the original test name. |
| `IndexMembershipUITests.testClearSearchRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Required; uses the validated in-memory fixture and retains the original shared assertions. The migrated head needs validation. |
| `IndexMembershipUITests.testPreviewClearEmptyCategoryRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Passed in run 41240567374; its assertions move to the original test name below. |
| `IndexMembershipUITests.testClearEmptyCategoryRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Required; uses the validated synthetic fixture instead of three UI-only setup creations. Validate the migrated head. |
| `IndexMembershipUITests.testPreviewClearCombinedSearchAndCategoryRepeatedlyPreservesPeople` | app UI, integration, unit | Failed in run 41245990817: the original five-second restoration waiter timed out; afterward all fixed-field restoration observations were true. Cause unresolved; original test remains required. |
| `IndexMembershipUITests.testClearCombinedSearchAndCategoryRepeatedlyPreservesPeople` | app UI, integration, unit | Retain; assertion-level review pending. |
| `IndexMembershipUITests.testPreviewClearAllPeopleSearchRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Passed in run 41245990817; shared assertions move to the original test name. |
| `IndexMembershipUITests.testClearAllPeopleSearchRestoresPeopleWithoutChangingRecords` | app UI, integration, unit | Required; uses the validated in-memory fixture and retains all shared assertions. The migrated head needs validation. |
| `IndexMembershipUITests.testClearSearchAndFiltersOnEmptyNotebookAtLargestText` | app UI, integration, unit | Retain; assertion-level review pending. |
| `KinUITests.testNormalColdLaunchOpensNotebookAndPreservesSavedPerson` | app UI, integration | Retain; assertion-level review pending. |
| `KinUITests.testSyntheticUnnamedDraftReviewOmitsTemporaryIdentityInEveryCreationFlow` | app UI, integration | Passed once in run 41240567374; all four unnamed-draft routes remain required. The one-route native smoke also remains required. |
| `KinUITests.testUnnamedDraftContactsReviewOmitsTemporaryIdentityInEveryCreationFlow` | native, app UI, integration | Replaced by the synthetic four-route test and one native direct-route smoke above; validate the migrated head. |
| `KinUITests.testNativeUnnamedDraftReviewOmitsTemporaryIdentity` | native, app UI | One real Contacts review remains required. |
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

- Keep the mapped UI tests and `validate` required; migrate an old assertion only after its replacement is recorded and validated. No skip, retry-to-green, or passing status for a failed native journey.
- A smaller required UI set must still include real Contacts and Photos, core navigation and data persistence, destructive-action safety, and representative accessibility sizes. The import and unnamed-review migrations remove six repeated native picker invocations; the preservation migration removes five more while retaining real native journeys, with the yearless-payload tradeoff documented above. Other membership and cadence still require assertion-level review.
- Validate lower-level replacements first, then any UI change on the exact commit. Exercise bounded repeated full suites and relevant order variation; report every failure and retain artifacts. A single green run is not a reliability guarantee.
- Historical native focus, picker readiness, Friend switch, Clear restoration and accessibility query stalls remain unresolved. Resource free/inactive counters are not a direct memory-pressure measurement.
