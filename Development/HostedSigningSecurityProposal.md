# Proposed hosted signing security boundary

Status: design only. No GitHub environment, credential, Apple permission or
signing workflow has been created or configured by this proposal.

## First protected signing exercise

Propose an environment named `kin-signing` in `dannydover/Kin`, restricted to
the protected main branch and gated by Danny's approval for each signing job.
Confirm the repository's actual plan, administrators, reviewer availability,
and enforcement behavior before configuration. A workflow change would still
need review: code executed by an approved job could access environment secrets.

For an explicitly approved signing-only exercise, the intended environment
secret inputs are `APPLE_DISTRIBUTION_P12` (an Apple Distribution certificate
**including its private key** in a password-protected `.p12`),
`APPLE_DISTRIBUTION_P12_PASSWORD`, and `APPLE_APPSTORE_PROFILE` (a matching App
Store Connect provisioning profile for `com.intriguingideas.Kin`). The profile is
app-specific; the distribution private key may authorize signing beyond Kin.
Do not assume an existing certificate, profile or private key is available.
The runner would create a random temporary keychain, import the key only there,
validate bundle, team, profile, entitlements and artifact identity, and delete
temporary material even on failure. Never print or upload signing materials.
The exact reviewed workflow, cleanup, artifact handling and threat model must
exist before requesting or installing any secrets. Public GitHub artifacts must
not be assumed private. This exercise does not upload or submit an app.

## Later Apple access

Uploading and processing a verified build requires separate App Store Connect
authorization. Apple documents Developer as an eligible upload role, but the
appropriate account, app restrictions and supported authentication method must
be verified before requesting a key. An individual API key inherits its user's
permissions and cannot use provisioning endpoints; Apple team keys cover every
app in the account. Do not create either without a concrete reviewed use and
separate approval. Submission and manual release require App Manager, Admin or
Account Holder access and their own owner approvals; an upload-only credential
should not silently acquire those privileges. Apple account agreements may still
require an Account Holder action.

## Risks and authorization

The first configuration decision would authorize a persistent GitHub environment
and secrets, not publication. A compromised approved workflow or runner could use
or disclose the signing key; a compromised App Store Connect key could act with
its assigned account role. Before asking Danny, provide the exact workflow,
environment protections, proposed secret names, provider/account, scope,
recipient, rotation and revocation approach, and a no-secret test result.
Separately request permission for any Apple API key, upload, review submission or
release. Physical-device QA of the actual signed candidate remains required.

References: https://docs.github.com/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development ;
https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment ;
https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api ;
https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/ ;
https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/ .
