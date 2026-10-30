# App Store release drafts

Create one GitHub release for each **public App Store version**, using the exact
commit and version/build used for its shipped app. TestFlight uploads and ordinary
merges do not create releases. This workflow prepares a draft with generated
notes; a maintainer reviews and publishes it after App Store availability.

## Record and verify the shipped source

1. Record the full commit SHA, `MARKETING_VERSION`, and `CURRENT_PROJECT_VERSION`
   when preparing the App Store archive. Use a clean checkout, without local
   version/build overrides. Confirm the archive's actual version/build matches
   these source settings and the App Store Connect build selected for release.
   The workflow checks repository settings; it cannot establish which signed
   archive Apple received or whether Apple has made it available.
2. Complete the physical-device release checklist in the README, including
   existing-notebook update and real lock/unlock protection checks. Keep private
   evidence and signing material outside GitHub.
3. Require a successful **Build and test** main push run on that exact SHA. A PR
   merge-preview check or a successful check on a later commit does not qualify.
   The latest attempt and its `validate` job must both succeed. If it failed or
   was cancelled, investigate and complete CI before preparing a draft.

## Prepare the draft

After this change is reviewed and merged into `main`, open **Actions → Draft App
Store release → Run workflow**. Select **main** and supply:

| Input | Value |
| --- | --- |
| `source_sha` | Full lowercase 40-character shipped commit SHA, on main history |
| `version` | Exact app Release `MARKETING_VERSION`, such as `1.0` |
| `build` | Exact positive integer app Release `CURRENT_PROJECT_VERSION` |
| `previous_tag` | Previous published stable version tag; empty for the first release |

The version tag is canonical: `1.0` and `1.0.0` both use `v1.0.0`. The build is
recorded in the title and an identity marker in the body, rather than creating a
second release tag for the same public version. Preserve that marker when editing
notes. For subsequent releases, choose the immediately preceding shipped version
as the notes baseline; its published tag must resolve to an ancestor of the source.

The workflow runs trusted scripts from the dispatch commit on main. It reads the
shipped source as data and never executes source-commit scripts or builds an app.
It uses only the ephemeral `GITHUB_TOKEN` with `contents: write` and `actions: read`
for the draft job. Checkout credentials are not persisted. No additional secrets,
signing identities, uploaded app binaries, logs, or evidence artifacts are needed.
GitHub's automatic source archives are ordinary public repository source.

Dispatches are serialized. The guard rejects changed main, missing/unsuccessful
source CI, mismatched app settings, alternate version tags, and conflicting tags
or release identities. Existing lightweight and annotated canonical tags are
accepted only when they resolve to the exact source. A matching draft or published
release is a no-op, preserving manually reviewed notes. It never updates, deletes,
or force-moves a tag or release. A failed/uncertain create can be rerun with the
same inputs; inspect any conflict before taking further action.

GitHub may defer materializing a new draft's tag until publication. The draft's
`target_commitish` is explicitly the shipped SHA, and the guard checks any tag
that already exists. Before publishing, verify the target and any existing tag
again; do not edit release identity or move tags concurrently with this workflow.
Publication remains a maintainer action.

## Review and publish

1. Read the generated notes in the draft. Remove internal implementation detail,
   incorrect release commitments, or anything unsuitable for public release notes.
   Confirm the change range and previous tag, and preserve the identity marker.
2. Confirm the title, version/build, full source SHA, and tag match the shipped
   App Store build. Attach no signed binaries, credentials, device identifiers,
   private device evidence, signing files, or real notebook data.
3. Confirm that **this version is publicly available on the App Store**. When
   ready, deliberately publish the reviewed draft through GitHub's release UI.
   This workflow cannot publish it or attest to App Store availability.
4. Verify the published tag resolves to the shipped SHA. Never repoint a published
   version to a different commit/build; investigate discrepancies explicitly.

## Failures and limitations

- If main moves after dispatch, rerun from current main with the same shipped
  source. If source CI is pending, wait for it to finish before rerunning.
- GitHub's current API restricts release targets whose workflow files differ
  from the default branch. `GITHUB_TOKEN` cannot receive workflow-write permission.
  This guard conservatively requires identical `.github/workflows` trees at the
  shipped source and current main. This includes historical commits predating this
  workflow: prepare a separately reviewed manual release for those commits rather
  than granting additional credentials or changing the shipped source.
- The guard supports the current explicit app Release settings and integer build
  format. If the project moves to inherited/xcconfig settings or a different build
  format, revise validation in a reviewed change first.
- API/permission failures stop without overwrite or credential fallback. There is
  no rollback that deletes pre-existing releases/tags. Inspect GitHub after an
  uncertain response, then safely retry the same identity.

## Validate a change to this automation

```sh
python3 -m unittest discover -s scripts/tests -v
actionlint .github/workflows/draft-release.yml
git add .github/workflows/draft-release.yml scripts/draft-release.py \
  scripts/tests/test_draft_release.py scripts/RELEASING.md README.md
python3 scripts/check-repository.py
git diff --cached --check
```

Tests use synthetic API state and make no GitHub writes. Do not run the script
locally with a credential to test it; an end-to-end draft creation needs explicit
release authorization after review.

References: GitHub's [release API](https://docs.github.com/en/rest/releases/releases),
[workflow run API](https://docs.github.com/en/rest/actions/workflow-runs),
[Git references API](https://docs.github.com/en/rest/git/refs), and
[GITHUB_TOKEN permissions](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token).

## Proposed one-time Kin 1.2 release-risk exception — review required

This exception applies only to the already-shipped Kin **1.2.0 (6)** and
source `6172840e99687e917aa74db01442fbc4bfb0a6cc`. All other versions keep the
existing policy. This provision allows a separately approved manual release
only after this change is reviewed and merged through normal protections and
an owner explicitly accepts the actual current release risks. Preparing or
merging this policy alone is not approval to release.

This is reduced assurance: the shipped source's exact-source main CI failed;
the later main-push run 40986605922 failed three of 184 tests, zero skips.
PR #57 run 40981748050 previously passed all 184. UI failures have moved across
scenarios and remain unexplained; passing physical-device QA and an unsuccessful
phone reproduction do not rule out a real product defect. The signed archive
records Xcode 27.1 (27A9275), iPhoneOS SDK 27.1; hosted CI used Xcode 27.0
(27A266a). Do not claim the toolchains or resulting binaries are identical.

1. Reverify archive identity, clean recorded source, version/build, signing
   evidence and public App Store availability. Keep private evidence outside
   GitHub. Confirm the source is in current main history.
2. Compare versioned production inputs against the later reviewed source; run
   `python3 scripts/verify-kin12-exception.py VALIDATION_SHA` as a read-only path
   preflight and independently review changed files, project build phases,
   external or generated inputs and archive provenance. A path allowlist is not
   a complete provenance or build-environment attestation. Document and obtain
   explicit acceptance of the known toolchain difference; stop for any new or
   unresolved material input or provenance discrepancy.
3. Inspect and record the latest run and attempt for shipped source and later
   main, including pending, failed, cancelled or incomplete checks. Preserve
   earlier failures and the passing PR evidence. If evidence changes or any
   required fact is uncertain, stop for a fresh owner decision; never label a
   failed or incomplete run successful or represent the earlier PR result as
   a later main-push pass.
4. Obtain an explicit owner decision on the exact, current evidence and risk,
   including the lower CI assurance and toolchain difference, before creating a
   draft, tag or release. This exception waives the exact-source successful-CI
   requirement for this release only; it does not change `validate`, tests,
   workflow permissions, branch protection or other release requirements.
5. Current main workflow files differ from shipped source, so the existing
   automated draft guard deliberately rejects this case. Do not bypass or alter
   it. Use a separately reviewed manual release only after approval. Verify the
   version, build, source ancestry, immediately previous published tag, canonical
   tag and any existing draft or release for conflicts, and recheck main and tag
   state before writes. Set `v1.2.0` to the exact shipped source; never move an
   existing tag. Verify the final release and tag after publication.
6. Public release notes must accurately disclose shipped and later CI source
   SHAs, actual test outcomes and the toolchain difference, with no private
   logs, signed binaries, credentials or device identifiers. The exception must
   not be described as equivalent to a passing exact-source validation.
