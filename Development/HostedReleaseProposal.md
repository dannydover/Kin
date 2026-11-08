# Hosted release: disabled preparation

This draft prepares a hosted path without depending on the owner's Mac. It does
not configure access, sign, upload, distribute or release an app. The signing
job is unconditionally skipped, has no environment reference, and both signing
scripts independently exit before doing work. Do not enable them without a
reviewed follow-up and the owner's specific approvals.

## Test gate and probe

`ci.yml` retains all existing required jobs, assertions, result and cleanup
gates. It adds `workflow_call` and pins its existing checkout and artifact v4
actions to the observed official commits. A manual release caller validates its
selected SHA against its main-dispatch SHA and then calls this exact CI through
native `needs`; signing depends on both. A local same-repository reusable
workflow resolves at the caller's commit and uses the caller context. The
release caller has a different concurrency group from the called CI. These
semantics and actual nested artifacts require hosted verification.

Until a manual workflow is available on the default branch, the ordinary PR CI
adds two lightweight PR-only jobs: check out the caller SHA and invoke the small
`reusable-ci-probe-target.yml`, which checks the same SHA and event context. It
does not rerun the full test suite. It exercises a reusable-workflow call and
`needs`, but does **not** prove that the full CI workflow has executed through
the manual release caller. The existing `validate` dependencies are unchanged;
the probe's own failure remains visible in the overall workflow. Existing
native picker and lifecycle failures remain historical evidence, not passes.

## Signing and cleanup design under review

Before any credential-bearing workflow is enabled, the owner must specifically
approve and verify a protected GitHub environment, its reviewers, main-only
branch restriction and administrator-bypass policy. GitHub can implicitly
create a missing environment without protections. No environment is referenced
here. The proposed signing inputs are an approved Distribution identity,
password, matching profile and owner-reviewed public team, profile and signer
identifiers. Secret storage, runner isolation and misuse risk require explicit
approval. No team-wide provisioning API key is required merely for manual Xcode
signing. The existing CI and all caller actions use the full SHAs observed for
checkout v4.4.0 and upload-artifact v4.6.2; a pin fixes a specific revision and
does not prove a prior floating-tag run used it.

The disabled scripts outline temporary keychain/profile setup, Xcode Release
archive and local manual export, bundle/version/team/certificate checks, a
limited entitlement check and cleanup. They are not a production signing path.
Fake-tool tests cover failure propagation and recovery; actual keychain/profile
discovery, certificate trust, entitlement policy, Xcode export compatibility,
logs and post-job cleanup still need a reviewed real trial. Passwords passed to
`security` can be visible to other same-user processes. Code signing and profile
hash checks do not establish Apple authorization or revocation.

The IPA screen rejects common unsafe ZIP paths, links, multiple apps and size
limits before `ditto` extracts job-produced output. It is not a general
hostile-archive extractor, `ditto` may interpret metadata differently, and it
may reject legitimate exports. A local hash and before/after source checks are
job observations, not an independent build attestation; transient source
changes, external inputs and same-user races remain. Cleanup verifies observed
search-list and file state, fails on missing evidence, and retains private
recovery markers on failure while attempting to delete private build materials
and logs. Runner loss or forced termination can defeat cleanup; no cleanup
record proves otherwise. No raw log or signed artifact is uploaded here.

The repository guard's narrowly scoped proposed exception permits two exact
quoted variable-only Xcode arguments only in the named script; tests retain
literal, mixed-value and other secret checks. It is a detector, not a shell
semantic verifier, and requires normal review. This draft's tests use synthetic
data and fake tools; they do not prove real Xcode or Apple behavior.

## Later delivery and release

Direct delivery to the owner's identified App Store Connect app is the chosen
design, but no uploader or credential is configured. Upload requires a separate
approval and supported Apple authentication. Do not publish signed IPAs in
public artifacts. Reconcile an uncertain upload against provider records rather
than automatically retrying; matching version/build metadata is not proof Apple
received the local IPA bytes.

Before upload, inspect the intended account's internal TestFlight groups,
automatic-distribution settings and recipients: an upload may expose a build
without a separate distribution call. Approval must cover that exposure, or the
owner must separately change the settings. Upload, TestFlight distribution,
submission and release remain distinct decisions. Physical-device review of
the actual signed candidate, including applicable Contacts and Photos checks,
remains required.

References: [GitHub reusable workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations),
[GitHub Xcode signing](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications),
[GitHub environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments),
[Apple profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles),
[Apple uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[Apple internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).
