# Hosted signing workflow: review draft

This is a non-executable design, not a signing workflow. It does not create an
environment, consume credentials, sign an app, upload data or permit release.
No real signing material or access has been inspected. PR #61's unsigned
archive exercise is the only implemented hosted archive path so far.

The separate `scripts/verify-hosted-ci-evidence.py` is a working, read-only
preflight component, not an authorized signing workflow. It requires a clean
checkout of the exact workflow-dispatch main SHA, the reviewed CI workflow
digest, Xcode 27.0 build 27A266a on arm64, and the latest exact-source main-push
CI attempt with all five required jobs successful. It fetches GitHub's API
directly with the ephemeral Actions token, refuses redirects and incomplete
responses, and prints no raw response or token. It requires `contents: read`
and `actions: read` when eventually wired into a workflow. It does not itself
authenticate a signed artifact or prove that supporting test scripts have not
been changed maliciously; protected-main code review remains essential. A
successful preflight would not authorize signing. The current merged main CI is
failed, so this preflight must not claim that source is ready.

## Intended trust boundary

Use a manually initiated workflow on a protected main revision. Require a full
immutable commit SHA; verify it is the checked-out commit and is reachable from
the protected branch. Verify the reviewed required test result for that exact
source and compatible pinned Xcode build, rather than accepting a user-provided
boolean or an untrusted pull-request artifact. Refuse stale, incomplete,
failed or skipped evidence. Whether current GitHub token permissions can prove
all of these requirements is still unverified: do not implement or configure
credentials until the check has been designed and tested against actual APIs.

The intended `kin-signing` environment would restrict deployment to protected
main and require Danny's approval before exposing environment secrets. Confirm
the repository's actual plan and enforcement, including whether the same person
may initiate and approve. Never use a pull-request workflow, untrusted fork
code, or dynamically downloaded unpinned scripts in a credential-bearing job.
The signing job should have `contents: read` only unless a specific additional
permission is justified. Actions must be pinned to reviewed immutable versions.

## Inputs and execution

The proposed GitHub environment secrets are `APPLE_DISTRIBUTION_P12`,
`APPLE_DISTRIBUTION_P12_PASSWORD` and `APPLE_APPSTORE_PROFILE`. These are not
configured. The certificate's private key may sign other apps on the same Apple
team; the profile must match the explicit Kin bundle ID, team, distribution
certificate and allowed entitlements. Certificate/profile identity, expiry and
revocation status must be verified using authoritative local Apple tooling and
checked against owner-approved expected public identifiers. Exact identity values
and credential availability are not yet known; never guess them.

Create a new random-password temporary keychain inside the hosted runner's
private temporary directory. Install only the approved identity and profile,
restrict key use to the signing tools, build/archive/export the exact source,
and remove the keychain, profile, decoded files and intermediate archives in a
failure-safe cleanup step. A test must simulate failures at every stage, confirm
cleanup was attempted, and fail if cleanup cannot be verified. Hosted runner
termination is not proof of cleanup. Do not alter the owner's local keychain.

## Verification and outputs

Verify the signed app and export with `codesign` and Apple profile decoding;
compare signature certificate, explicit bundle ID, team, entitlements, version,
build, architecture and executable/dSYM identities with the approved inputs.
Record exact source/tree, Xcode/SDK builds, manifest hashes and verification
outcomes in a small allowlisted provenance manifest; fail closed on a mismatch.
No raw build output, credential, profile, keychain, device identifier, private
path or personal data may be sent to public logs or artifacts. Do not publish a
signed archive as a public GitHub artifact. The secure handoff needed for device
QA is undecided and requires separate review.

## Synthetic verification required before approval

Tests must cover invalid or stale source, missing/failed test evidence, wrong
toolchain, bundle/team/profile/certificate mismatch, expired profile, unexpected
entitlements, signature/architecture/dSYM mismatch, secret redaction, bounded
artifact output, interruption and cleanup failure. Tests must prove no success
manifest survives a failed check. Use synthetic inputs and mocks; they do not
prove that a real signing identity or signed build is valid. Review the final
workflow, test outputs, least-privilege scope, rotation and revocation plan before
asking for the specific environment and signing-secret configuration.

Upload, App Store Connect API credentials, processing, submission and release
are separate steps with separate approvals. Apple currently lists Developer as
an upload role, but App Manager or higher for submission; confirm the applicable
account, available role and actual API authentication path before deciding which
credential to request. Individual and team API keys differ in scope. Device QA
of the actual signed release candidate remains a separate requirement.
