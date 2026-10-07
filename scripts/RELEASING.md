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
