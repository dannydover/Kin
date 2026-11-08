# Disabled hosted Kin Dev delivery proposal

This is separate from PR #61 and the provisional 1.3 metadata. No signing or
upload path is active. The caller workflow has an unconditional false
signing job and no environment reference. The signing and cleanup scripts
both exit immediately. The uploader CLI also exits immediately. These guards are
intentional and must not be removed until reviewed and specifically approved.

## Proposed sequence and current limitations

Run existing reusable required CI on the exact current main commit, then require
a protected GitHub environment approval. In the same isolated job, perform the
existing manual Xcode archive/export proposal and inspect app identity, version,
signer and profile. A signing-only trial removes its IPA during cleanup. A
separately approved upload trial would build again and call `kin_upload_review.py` before
the existing always-run cleanup removes the private workspace. This avoids a
public signed IPA artifact. Its caller records only fixed outcome categories,
never raw altool output or secrets.
After a tool-success response, the disabled proposal signs a short-lived JWT and
polls Apple's documented build-uploads endpoint for the fixed Dev app, version
and build. It requires exactly one matching upload and a linked build reporting
`VALID`; pending, duplicate, incomplete, HTTP failure, timeout or unavailable
results remain unverified. Processing metadata equality is not proof of byte
identity. The response shape, permissions, JWT key type, and behavior have not
been verified with the real Apple account. Every nonzero upload exit, exception,
interruption or timeout is uncertain. No automatic upload retry is allowed;
reconcile the exact account/app/build with Apple before a separately approved
retry. The private marker is an owned runner-local file, NOT durable across
runner loss, and must not be treated as proof that no upload happened. The
disabled job proposes a fixed-field outcome artifact after cleanup: it contains
only run/source identity, Dev bundle ID, and an allowlisted outcome. A missing,
malformed or unrecognized marker maps to `unknown`; successful tool return maps
to processing-unverified. If the runner dies before artifact upload, no outcome
is available and reconciliation is still mandatory. There is no automatic retry.

The candidate command is `xcrun altool --upload-app -f <ipa> -t ios --apiKey
<key-id> [--apiIssuer <issuer-id>] --output-format xml`. Apple documents altool
uploads and separate build processing. The credential-free hosted probe
https://github.com/dannydover/Kin/actions/runs/42503548601 confirmed that pinned
Xcode 27.0 altool help advertises the four proposed flags. This is not an
authentication, key-lookup, upload or processing test. The disabled helper stages synthetic key
bytes in a private temporary HOME and removes it before declaring tool success.
Apple documents this key location for altool notarization; actual App Store
upload lookup, arguments and individual-key compatibility on hosted Xcode 27.0
remain unverified. Local Xcode 27.2 `xcrun altool --help` returned a missing
Defaults.properties error. Do not activate the uploader based on these tests.
An individual key associated with the owner account is one option to
investigate; it inherits that account's access and is not established as
app-limited. Apple says team keys cover all apps. The applicable account role,
individual-key support, approved private-key handoff and actual processing API
behavior remain unresolved. A team provisioning API key is not
required merely to do manual signing.

## Proposed protection and approvals, not configured

Use a pre-existing explicitly verified environment restricted to the protected
main branch, with Danny as required reviewer and administrator bypass disabled
where supported. Since Danny is also the likely dispatcher, the workable
single-owner proposal permits his self-approval; it is an explicit reduction
from independent review, not a second-person check. If self-review must be
prevented, a separately authorized second dispatcher or reviewer is required.
The owner
must verify these settings; a missing environment can be silently auto-created
without safeguards. Do not reference a not-yet-configured environment.

The credential-free hosted probe run 42503548601 used GitHub's Hosted Compute
Agent, MacCloud, image xcode-27-arm64 version 20261104.0337.1. This is evidence
for that run only, not proof a future label will select a GitHub-hosted isolated
VM. Before credentials, verify the future runner mapping and GitHub's documented
fresh-runner isolation; do not rely on runner-supplied environment strings to
establish trust. A self-hosted or unverified runner must not receive secrets.
GitHub describes fresh GitHub-hosted VMs at
https://docs.github.com/en/actions/concepts/runners/github-hosted-runners.

The 85-minute example budget reserves 5 minutes for checkout, 40 for signing,
20 for upload, 5 for cleanup, 5 for evidence and 10 slack. Each bounded step
must actually return within its budget for that reserve to apply; cancellation,
SIGKILL, detached processes and runner loss can still defeat cleanup. Signing
and upload remain disabled; the mode selector describes a signing-only trial
versus a separately approved upload trial and does not itself enable either.

Separately obtain explicit approval before storing an existing Apple Distribution
P12/private key (`KIN_P12_BASE64`), its password (`KIN_P12_PASSWORD`) and matching
profile (`KIN_PROFILE_BASE64`) as environment secrets. Public identifiers are
`KIN_TEAM_ID`, `KIN_PROFILE_UUID`, `KIN_CERT_SHA256`, `KIN_VERSION` and
`KIN_BUILD`. The distribution private key may sign other apps on the team.
A separately approved signing trial is required after implementation and review.
Uploader access would need its own specifically approved Apple credential and
recipient: a proposed `KIN_ASC_PRIVATE_KEY_P8_BASE64` plus `KIN_ASC_KEY_ID`, and
`KIN_ASC_ISSUER_ID` only if the supported auth mode requires it. Key staging has
only been exercised with synthetic bytes. Apple credentials can grant broader account or app
access; establish minimum compatible role and scope before creating any key.

Before upload, use the existing authenticated Apple account read-only to check
Kin's build number and internal TestFlight group auto-distribution/recipients;
upload approval must cover any resulting tester exposure. Actual upload,
TestFlight distribution, submission and release are distinct permissions.
Physical-device review of the actual candidate remains required. On 2026-11-08,
the signed-in account showed no production Kin internal testing groups and All
Testers showed zero testers. A separate Kin Dev app and internal group were
subsequently created with automatic distribution selected; the group showed
one internal tester (Danny) and zero builds on the latest read. Whether altool
uploads are automatically distributed remains unverified. Build Uploads for production
listed 1.2.0 (6), 1.1.0 (5), and 1.0.0 (1), with no
1.3 build displayed. This is not a reservation or guarantee of acceptance;
recheck before upload. Danny reported accepting the updated developer program
agreement; the warning was absent on the next read-only Apps-page inspection.
No agreement was accepted by this workflow.

## Evidence and limitations

`test_upload_review.py` executes the actual orchestration helper with injected
fake runners and harmless owned subprocesses only; one path composes the real
processing parser with a synthetic Apple response. The local suite checks
success, nonzero, timeout, interruption, marker-based duplicate blocking, input
validation, disabled CLI, script order and processing categories. It does not sign or transmit, verify Apple
behavior, establish runtime profile/keychain cleanup, or model runner death.
The original local fake cleanup suite was run separately; it does not prove
actual Xcode behavior. Cleanup is best effort on runner loss or SIGKILL. The
rehearsal CI failure, launch failure and Friend/Save intermittency remain.

Apple: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
Apple processing records: https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-builduploads
Apple JWTs: https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
Apple altool notarization key location (not proof of upload compatibility): https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool
Apple keys: https://developer.apple.com/documentation/AppStoreConnectAPI/creating-api-keys-for-app-store-connect-api
Apple TestFlight: https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/
GitHub environments: https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments
