# Focused next-release QA plan

Use synthetic people and photos only. Preserve existing notebook data; do not
reset, uninstall, or use Delete All as part of this plan.

On October 27, the owner reported steps 1–11 passed on installed Kin Dev 1.2.0
(6), including both the largest-text and VoiceOver checklist steps. This is
owner-reported physical acceptance of that candidate, with three reported UX
refinements handled afterward. It is not acceptance of uninstalled changes or
a comprehensive accessibility audit. The baseline checklist below is retained
for reference, not a request to repeat it.

## Targeted recheck after a coordinated update

1. With a search and category selected, use Clear search and filters. Confirm
   search/category clear together, the keyboard closes, and the unfiltered People
   screen returns without changing saved categories. Try a no-match search and
   an empty category, including with largest text.
2. In Edit person, confirm Cancel fits inside its background at normal/largest
   text, stays separate from Save, and still cancels without saving.
3. Check representative list, relationship and Contacts guidance: exact feature
   names are semibold and clearly described as screens, settings or actions;
   paragraphs wrap naturally and VoiceOver reads complete sentences without
   formatting markers. No baseline QA rerun is required.

## People and category filtering

1. Add one person with no category, one Friend, one Family, and one Colleague.
   All on the People screen includes all four. Each category shows only its
   matching visible people; overlapping categories never duplicate a person.
2. Combine a category with name search, including no matches. Clear search and
   change categories repeatedly. Edit then cancel a person; the filter remains.
3. With no search matches or an empty category, tap Clear search and filters.
   Search and category reset together, the keyboard closes, and the unfiltered
   People view returns. Repeat from All people and with an empty notebook; no
   people, saved categories or list-inclusion choices should change.
4. A linked-only relative stays outside the main list unless Show on main list
   is enabled. Guidance identifies this as a setting and distinguishes the
   People and All people screens. Changing categories does not change list inclusion.

## Name-based defaults

Use names from the verified bundled snapshot, including Michael, Mike and Chris,
and an unmatched synthetic spelling. An automatic new draft recalculates on name
edits and clears to Unspecified when unmatched. Select each available gender,
including reselecting Unspecified; subsequent name edits keep that choice.
Review a new Contacts import, edit its name and gender, then cancel and retry.
The earlier draft must remain unchanged on cancel or failed save. An existing
person's import preserves their chosen gender. No name is sent to a service.

## Eligible Contacts preview

Use a synthetic contact with an established adult birthday and synthetic photo,
a contact with no photo, an unknown/partial birthday, and an ineligible birthday.
Verify that preview and imported photo agree. Correct the reviewed birthday and
check eligibility updates. Existing retained age alone must not opt in a newly
selected contact's photo. Cancel, save failure, retry and repeated import must
retain correct identity and never save an unreviewed photo.

## Remaining Add parent acceptance (#24)

Previously accepted existing-person parent/child/partner chooser checks remain
accepted for their tested build. Remaining physical acceptance uses synthetic
people: create a new parent manually; import a new parent; link it to the open
child with the intended direction; choose each optional parentage type; retain
multiple parents; cancel without partial creation; remove a link while keeping
both people; reject duplicate links and ancestry cycles. Recheck relaunch and
identity after save. Automated coverage must supplement these, not fabricate a
phone pass.

## Accessibility acceptance (#46)

The owner completed the baseline largest-text and VoiceOver checklist on the
installed candidate. Recheck only the subsequent changed screens after an update.
Check that explanatory text identifies exact screen, setting and action names
in semibold, with one natural VoiceOver reading order and no raw formatting
markers. Check that the editor’s Cancel text sits inside its background, stays separate
from Save, and still cancels without saving. Check the clear-search action while
the keyboard is open. The full accessibility audit is deferred, not passed.
Relevant screens include
manual new-person entry,
Contacts selection/review and Import and Save, searchable relationship chooser,
baby-age fields and the new filter. Check all controls remain reachable and text
unclipped. With VoiceOver, check labels, selected values, navigation, cancel/back,
error announcements and focus after save. Automated layout/accessibility audits
are useful evidence but do not establish physical VoiceOver acceptance.

The previously accepted protection-test limitation (#19) is separate; this work
neither repeats that security investigation nor labels its inconclusive case passed.
