# Next release draft: 1.2.0

Local branch `feature/kin-1.2-improvements` starts from the exact validated 1.1
source. The submitted source/archive remain separate. Source metadata is 1.2.0,
build 6; App Store Connect availability has not been queried or changed here.

## Version recommendation

1.2.0 fits additive offline defaults, category filtering and import review.
No incompatible storage change is intended. Stored identifiers, existing people,
relationships, optional list membership and protected-storage rules are preserved.

## Public What's New draft

- Get an editable gender suggestion when adding a new person by name or reviewing
  a new Contacts import. Your selection always takes priority, and existing
  people's gender stays unchanged.
- Filter your people list by Friend, Family or Colleague alongside name search.
  All keeps everyone already on your list, including people without a category.
  Clear search and filters in one tap when a search or category has no matches.
- Preview eligible Contacts photos before importing, alongside the name, gender
  and birth information you can review and edit.
- Clearer People screen and Show on main list wording, with connection choices
  below Photo in the shared person editor, plus correctly sized editor buttons.
- Easier-to-follow guidance that clearly identifies screen, setting and action
  names, with consistent emphasis.

These public notes are separate from Git commits and private QA evidence. Entering
them into App Store Connect, uploading a build, submitting and releasing each
remain outside this local implementation task.

## Data source

The Mac verified the supplied official SSA ZIP's 7,860,026 bytes and agreed
SHA-256. Pooling 1940–2025 exactly, minimum count 100 and integer dominant-sex
threshold 85%, generated 13,373 M-associated and 22,486 F-associated spellings
(35,859 total). No suppression correction or cohort-conflict filter was added.
See [source provenance](DataSources/SSA.md). These associations describe recorded
applications, not individual identity; all suggestions remain editable.

## Verification status

Candidate-specific test results, interrupted attempts, build hashes and toolchain
versions belong in the private verification manifest. Passing focused tests alone
does not establish release readiness.
The [owner QA plan](QA-NextRelease.md) records baseline acceptance and targeted
rechecks. The owner reported checklist steps 1–11 passed on installed 1.2.0 (6), including
largest-text and VoiceOver steps. Subsequent local UX fixes require a coordinated
update and targeted recheck; baseline QA does not need repeating. The full
accessibility audit beyond that checklist is deferred, not passed. The accepted 1.1
protection-test limitation remains separate and has not been relabeled passed.
