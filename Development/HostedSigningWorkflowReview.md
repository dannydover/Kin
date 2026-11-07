# Hosted signing workflow: review draft

This is a non-executable design, not a signing workflow. It does not create an
environment, consume credentials, sign an app, upload data or permit release.
No real signing material or access has been inspected. PR #61's unsigned
archive exercise is the only implemented hosted archive path so far.

The separate `scripts/verify-hosted-ci-evidence.py` is a read-only
preflight component, not an authorized signing workflow. It requires a clean
checkout of the exact workflow-dispatch main SHA, verifies GitHub reports main
as protected, and requires the reviewed CI workflow
digest, Xcode 27.0 build 27A266a on arm64, and the latest exact-source main-push
CI attempt with all five required jobs successful. For this draft it also
rejects any other failed or incomplete main-push run for the same source and
rejects rerun attempts; a later pass cannot silently erase an earlier failure.
This deliberately conservative policy
requires review before use. It fetches GitHub's API
directly with the ephemeral Actions token, refuses redirects and incomplete
responses, and prints no raw response or token. It requires `contents: read`
and `actions: read` when eventually wired into a workflow. It does not itself
authenticate a signed artifact or prove that supporting test scripts have not
been changed maliciously, or verify which branch rules are enforced and who can
bypass them; protected-main code review remains essential. A
successful preflight would not authorize signing. Main or CI can change after
the check: the eventual signing design must revalidate at the point of use and
cannot claim a cross-system atomic lock. The current merged main CI is
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
GitHub automatically creates a referenced nonexistent environment without
protection rules. Therefore do not activate an environment-referencing workflow
until the existing environment and its required reviewer, branch restriction and
bypass settings have been explicitly configured and independently verified.
An unprivileged preflight must fail if those protections cannot be read or do not
match the reviewed policy. Do not rely on the environment name alone. GitHub's
documented environment response shows reviewer and branch-policy fields but does
not document an administrator-bypass field in its example. A supported way to
verify the intended bypass setting remains unresolved; a missing field must not
be interpreted as disabled. See
https://docs.github.com/en/rest/deployments/environments . The script's
`verify_signing_environment` evaluates the required response contract. GitHub's documented branch-policy
example also omits the `type` field that the contract requires. GitHub's
official OpenAPI schema does define `type` for branch-policy responses; an
omitted example field is not evidence that the API cannot return it. At schema
revision `1237c2cea548efd96665ea8ba0a3970adac5c576`, the environment schema
does not define `can_admins_bypass`; that is not proof that the live response
lacks it or that GitHub cannot enforce the setting. The documented read
endpoints support Actions read permission and public resources can be read
without it. A real response and the owner-approved configuration must be
verified before relying on either field; missing fields fail closed.

The preflight now calls the fixed, read-only environment and branch-policy
endpoints and applies this contract after its source/CI checks. Tests inject
synthetic responses only. It does not create an environment, access secrets,
sign or upload. The manual-only `hosted-signing-preflight.yml` invokes it on an
exact current main SHA with read-only GitHub token permissions and no signing
environment or signing secrets. It has not been hosted-dispatched: a manual
workflow first needs to exist on the default branch. The known failed main CI
and an unconfigured environment prevent a successful preflight. A successful
read is not an atomic guarantee that protection persists through a later job.

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

The currently unwired keychain component handles SIGTERM, SIGINT and SIGHUP
on the main thread as interruption failures and attempts cleanup, restoring
prior signal handlers. Synthetic tests exercise interruption during import
and cleanup. An unknown prior handler aborts before keychain creation; a
handler-restoration failure is reported. This is best effort, not a guarantee: SIGKILL, runner loss and
some signal timing windows can prevent or interrupt cleanup. A complete workflow
must use an owned, bounded post-job cleanup strategy and fail closed on missing
evidence. The component can optionally stage owner-reviewed profile bytes by
UUID and SHA-256 in a pre-existing private, owned directory. It creates the
file exclusively without following a final symlink, refuses an existing file,
and attempts to remove only the file it created after checking identity and
content. Changed or missing files produce cleanup failure rather than deleting
a replacement. These are synthetic tests only: actual Xcode discovery and
profile authorization are not verified. Directory and file checks do not
defend against a hostile same-user process racing the final unlink; runner
isolation and independent cleanup are still required. No workflow calls this
component or installs a profile.

An unwired `scripts/isolated-signing-keychain.py` component stages this lifecycle:
it permits only a GitHub-hosted runner, creates its own temporary workspace and
keychain, suppresses raw command output, bounds each security/cleanup subprocess,
and reports original and cleanup failures separately. Its tests use only a fake
security backend. It is not called by a workflow and has never handled a real
credential. The macOS `security` tool receives passwords in process arguments;
other same-user processes on that runner may observe them. The `apple:` key
partition may permit more Apple-signed tools than just codesign. The caller must
still prove the protected environment, validate the certificate and profile,
bound the overall build operation, handle interruptions, and independently
verify keychain cleanup. Do not use this component with real material until the
complete workflow and these risks have been reviewed and explicitly approved.
The `RUNNER_ENVIRONMENT` string is a defensive check, not trusted proof of the
runner or the GitHub environment's protections. Failures are retained as fixed
categories without secret-bearing messages; a category is not a full diagnosis.

## Verification and outputs

The unwired `scripts/verify-signature-integrity.py` runs a bounded, quiet
`codesign --verify --deep --strict --all-architectures` check on an app bundle,
with an explicit Apple-generic anchor, Kin bundle ID and owner-supplied team
requirement. It separately extracts the leaf certificate and checks its SHA-256
against an owner-reviewed fingerprint. Values are validated before use, and
commands have bounded runtimes and suppressed output. Synthetic tests mock
the command; no signed Kin product has been checked. The requirement syntax
was compiled locally with `csreq`, but actual distribution-certificate behavior
remains unverified. Recursive checking is limited to nested code recognized by
`codesign`; it is not an inventory of all executable content. The verification
and extraction are separate calls, so the caller must prevent mutation between
them. This does not establish profile authorization, current revocation,
entitlement policy, provenance or authorization to hand off a build.

The read-only `scripts/verify-signed-candidate.py` integrates that signer check
with bounded app-metadata, exact reviewed profile-hash, and exact reviewed
signed-entitlements comparisons. It rejects `get-task-allow` and bounds and
cleans up its own entitlement-inspection process. Its `verify_with_preflight`
entry point invokes source/CI/environment checks before and after candidate
checks. It does not lock the source, environment or app; the future caller must
use a protected immutable workspace. A profile-hash match only identifies the
owner-reviewed bytes; it does not prove Apple issued or currently authorizes
them. No check binds the artifact to the source, and no signing or handoff
workflow invokes this module. Tests use synthetic data and fake signer output;
the entitlement subprocess limits have also been exercised with a harmless
local child. No signed Kin app has been verified.

The same module now also compares the signed archive app and exported app
against the reviewed identity, profile bytes and entitlements, checks that the
archive binary, exported binary and dSYM report the same arm64 UUID, and
returns their hashes alongside preflight-observed source identifiers only
after a second preflight. Synthetic tests compose this check inside the actual
temporary-keychain/profile transaction, including a mismatch and cleanup path.
The build/export steps and signer outputs in those tests are fake. This is a
local consistency observation, not proof that Xcode built either binary from
that source: no controlled Xcode archive/export orchestration or IPA-container
verification is implemented yet. No workflow calls the signed-output check.

Verify the signed app and export with `codesign` and Apple profile decoding;
compare signature certificate, explicit bundle ID, team, entitlements, version,
build, architecture and executable/dSYM identities with the approved inputs.
The signed entitlements must match the reviewed app policy and be authorized by
the profile; Apple's profile entitlement allowlist can include extra entries
and wildcards, so raw dictionary equality is not a correct profile check.
Record exact source/tree, Xcode/SDK builds, manifest hashes and verification
outcomes in a small allowlisted provenance manifest; fail closed on a mismatch.
No raw build output, credential, profile, keychain, device identifier, private
path or personal data may be sent to public logs or artifacts. Do not publish a
signed archive as a public GitHub artifact. GitHub documents that people with
repository read access may download workflow artifacts; this repository is
public. A GitHub artifact is therefore not the proposed private handoff.

Apple TN3125 states that the profile's DER-encoded form, not the decoded
property-list view, is the source of truth on modern iOS; it also warns that
the profile format is undocumented and its examples are for debugging. Merely
decoding the plist and comparing its values cannot establish profile
authorization or revocation. Do not promote the synthetic identity contract to
a release guard on that basis. A supported validation and processing path and
its assurance boundaries still need review and a separately approved real
trial. See https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles .

The candidate handoff is direct upload of the verified signed IPA from the
ephemeral runner to Apple's App Store Connect, followed by processing and an
explicitly approved TestFlight distribution to existing authorized testers. The
same verified build would be selected for later App Review. This path requires
separate approval for Apple credentials and each applicable upload/distribution;
it is not implemented or tested here. Apple supports build uploads through
Transporter or altool, but this repository's account access, selected tool and
API-key compatibility remain unverified. If direct transfer cannot be supported
securely, stop: no private artifact store has been identified or approved as a
fallback. Record IPA hash and Apple's returned build identity without logging
secrets or treating an upload request as proof of processing or publication.

An existing approved Distribution identity and matching App Store Connect
profile can be supplied for manual Xcode signing and export without granting a
team-wide App Store Connect API key solely for signing. Local checks and Xcode
export cannot establish that Apple will accept the build or that a profile or
certificate has not been revoked. Apple-side upload and processing remain a
separately approved validation step. An optional team API key could query current
profile state, but it has broader account scope and is not a prerequisite for
manual signing; do not request one by default.

The unsigned archive exercise runs a bounded read-only `xcodebuild -help` probe
on its pinned Xcode to check that its help advertises local export, manual
signing, App Store Connect method and profile/certificate/team options. It
does not sign, export, check an actual profile, or prove the options will work
for Kin. Missing or changed help fails the exercise; it does not change the
required test gate. The probe retains no raw help output.

An IPA payload comparison is under synthetic review. It compares
each regular file in `Payload/Kin.app` with the inspected exported app and
rejects additional file content and symlinks. It has not been tested on an
actual Xcode export, which may legitimately contain additional files or links.
It does not compare file modes, establish that source produced either artifact,
or prove Apple authorization, profile freshness, or release readiness. Inputs
must remain immutable; the comparison does not protect against concurrent
same-user changes. No workflow invokes this candidate.

The synthetic archive orchestrator exercises preflight, a temporary profile
and keychain transaction, fixed archive/export command plans, archive/export/IPA
comparison, and a separate injected cleanup observation. Its injected runner,
security backend and cleanup observer must be fakes; it has no CLI and no
workflow calls it. It uses fixed synthetic credentials and fabricates the app
and IPA in tests. Requested command deadlines are not enforced by this module.
Its fake exported app layout has not been established as actual Xcode output,
and keychain discovery by Xcode has not been demonstrated. The observed source
and artifact hashes are not proof that the source produced the artifacts.
A real path still needs a bounded process runner, isolated source and external
build-input controls, verified profile/keychain discovery, safe IPA inspection,
independent hosted post-job cleanup, and a secure delivery decision. Its fake
cleanup observer is not evidence of cleanup after runner loss or SIGKILL.

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

References: https://docs.github.com/actions/managing-workflow-runs/downloading-workflow-artifacts ;
https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/ ;
https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles .
