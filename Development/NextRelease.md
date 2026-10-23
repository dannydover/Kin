# Next release candidate: 1.1.0

Local review branch: `feature/kin-1.1-improvements`, based on the preserved Kin Dev
identity commit `0caefd4`. The shipped v1 commit and production bundle identifier and signing
configuration remain unchanged. The Core Data schema and protected storage rules are unchanged. An optional payload field records explicit list inclusion; older payloads preserve their prior category-based visibility without a write-on-open migration. No new capability is included.

## Version recommendation

Recommend **1.1.0**: this adds age presentation, direct import/save, independent
list inclusion, a searchable relationship chooser and confirmed notebook-wide
deletion, alongside optional relationship details, layout improvements and new artwork. A patch
number would understate those additive user-visible changes; no incompatible data
change calls for a major version. This is a recommendation, not a submitted version.
Source metadata is **1.1.0, build 5** for the local release candidate. This build
number is locally unused; App Store Connect availability remains unverified.

## Public What's New draft — pending final validation and approval

- See babies' ages in months until their first birthday when an exact birthday is recorded. Approximate ages
  keep their original precision.
- Save a new person straight from Contacts review, including a chosen family or
  partner relationship. Review names and age before importing and saving.
- Start a new child's surname with an editable suggestion from the person whose
  profile you opened.
- Add parents and children without choosing a relationship type. Optional details
  remain available whenever you need them.
- Add or import someone directly without choosing a connection label. Your people keeps them visible, and saving opens their profile. Manage list inclusion separately from optional labels.
- Link an existing person from a separate searchable list, with people available to tap immediately and relationship details below the creation choices.
- Delete every saved person in this Kin notebook, including hidden people and their relationships, notes and photos, with a separate confirmation and straightforward Cancel.
- Keep an existing birthday or estimated age when importing a contact without a usable birthday; change it only when you choose to.
- More consistent relationship action buttons.
- A new Kin app icon.
- Clearer Contacts guidance and a more compact unknown-age label make information
  easier to scan.

The owner confirmed completed calendar months before the first birthday, then
years, with “Less than 1 month” for newborns. The centralized presentation policy
records that choice.
Month-end anniversaries clamp to the final valid day; the existing March-first
leap-day *year* transition remains authoritative. Estimated whole-year ages never
become exact month counts. Age and photo eligibility calculations are unchanged.

## How the public update notes work

App Store Connect has a version-specific, localizable **What's New in this
Version** field. It is required for updates and accepts up to 4,000 characters.
These are the public, human-readable changes associated with that app version.
They are written and reviewed separately from Git commit messages, technical
GitHub release notes, TestFlight testing notes and private App Review notes.

Before a release, edit the draft to include only shipped, verified behavior,
check every supported language, then enter it in the new version's metadata
alongside the selected build and other submission information. This local work
does not create that version or submit metadata. Publishing a GitHub release
alone does not fill the App Store field.

Sources: [Apple's version metadata reference](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
and [creating an App Store version](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/).

## Scope and review checks

- #14: calendar-based exact-month display, common formatter, source precision,
  singular/plural, month/year boundaries and local civil-day refresh.
- #36: one-time editable/clearable surname suggestion only for a fresh Add child.
- #37: visible footnote helper blocks under their associated sections, semibold
  lead-ins, no fixed font size/opacity, tested actual warm-background contrast.
- #39: collapsed optional relationship details; Unspecified is unchanged as the
  new-parent/child default, while stored/selected types remain editable.
- #40: explicit Import and Save for new people only, editable names/age and
  optional connection labels, atomic existing store transaction, retained review on error,
  stable identity across explicit retries and repeated confirmation.
- #41: semantic secondary age typography and scaled minimum child-preview width;
  one-line age status at standard sizes and vertical layout at accessibility sizes.

#38 photo-preview work, tree/inference features and unrelated backlog are excluded.
Existing-person Contacts imports retain their Import-then-Save semantics.

## Follow-up review scope

Direct additions and new Contacts imports start in Your people, with no category
required or inferred. A successful direct save opens the saved identity’s profile.
An explicit Show in Your people toggle manages inclusion separately from categories
on edits and relationship-based creation. Linked new people start unlisted; All
people continues to include every record. Existing categorized people retain
visibility; existing uncategorized people remain unlisted. The optional Codable
field falls back to the prior rule when absent, then freezes that resolved choice
in memory until an explicit save. No Core Data entity, protection rule or reset
path is changed. Legacy payload, precision, photo, identity, relationship,
transaction failure and retry tests cover this transition.

Add parent, Add child and Add partner present Create and Link before relationship
details. Link opens a separate searchable list populated immediately. Selection
opens an unsaved confirmation; duplicate names include stable notebook references.
Cancel/back keeps choices unsaved; search never creates or links a person.

The owner accepted the installed build 4 relationship controls, corrected deletion
wording, cancellation and retained data, after earlier checks 1–5 and 7. That is
physical QA of build 4, not the subsequent contact-preservation and clipping fixes.
Manual accessibility step 6 is deferred to a later version, not passed and not a
current owner QA gate. Basic physical lock/unlock and foreground recovery were
reported complete; stronger lock-during-save and reboot/first-unlock evidence is
tracked separately. Final candidate automated results and archive validation are
recorded in local release evidence. No submission or release approval is implied.
#38 remains excluded.

## Existing-person birthday preservation — #32

A selected contact with missing, unavailable, yearless, invalid or ambiguous birth
information keeps the existing editor’s exact birthday, estimated age and reference
date, or Unknown. This includes deliberate unsaved age corrections. Valid complete
source birthdays replace normally; explicit reviewed changes, including Unknown,
remain available. Import updates the draft; Save persists the same identity and
relationships. Cancel and save failure use the existing preservation/retry path.
Retaining an age does not establish that a new contact photo belongs to an adult:
photo inclusion is initially off for an unusable source and requires explicit
confirmation while retaining the existing eligibility checks. No schema migration
or repair of older saved records is performed.

## Delete all people — #7

The navigation menu opens a scope explanation and saved-record count. A separate
destructive confirmation is required; Cancel or dismissing beforehand changes
nothing. This local-only action removes all Person records and their associated
relationships, notes and managed photo data, including unlisted people. It keeps
unrelated settings, source Contacts, external copies and backups. No export or
undo window is included. Kin currently has no sync queue, cloud container or
shared-data deletion to propagate; any future sync/sharing needs its own design.

Core Data deletes managed records in the existing transaction, including cascaded
links and external binary photo storage. It does not reset or replace a notebook,
change the schema, or remove unrelated files. The monotonic notebook reference
counter remains. Failures use rollback/reopen recovery; a post-commit failure can
mean deletion committed, so the UI says it could not confirm completion and asks
the user to reopen/check, rather than claiming everything was kept or succeeded.
Synthetic tests cover both sides of commit, protected-data refusal, repeated taps,
empty stores, cancellation, process interruption before confirmation, relaunch and
managed external-media cleanup. These are logical app deletions, not a claim to
erase storage forensically or remove OS backups/external copies.

## Icon review

The supplied G-2 reference is preserved as outlined SVG plus a native layered
production icon. Its K is a compound-path cutout; the child disc is in front.
The matching Dev blueprint is authored SVG, retaining the same geometry. The
built-in image service failed before rendering, so it contributed no pixels;
no API/CLI fallback or credentials were used. Source processing, native rendering
and format normalization are recorded in Development/IconDesign/README.md.

Native exports were inspected in Default, Dark, TintedLight, TintedDark,
ClearLight and ClearDark. The two discs and K remain identifiable at 60 pixels;
Default and the Dev flat graphic were also inspected at 29 pixels. TintedDark
uses the system's subdued treatment and should receive physical appearance
review, along with wallpaper interaction in Clear modes. Native previews are not
physical-device acceptance or App Store validation. The source PNG masters are
opaque 1024-square sRGB without manually rounded corners. The in-app illustration
is unchanged. Source metadata is prepared as 1.1.0/build 5. The released v1 baseline
and installed App Store app are unchanged by these local assets and settings.
