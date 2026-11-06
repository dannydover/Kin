# Kin 1.3 hosted release plan

The objective is to build and publish the approved App Store release without
depending on the owner's Mac or an unlocked desktop. Human review of the actual
signed release candidate and explicit release approval remain separate steps.

1. Exercise an unsigned iPhone Release archive on the hosted runner, with a
   pinned Xcode build and fail-closed source, identity and provenance checks.
   The separate PR-only exercise is not a distributable artifact and contacts
   no Apple services. Its result does not validate signing or publishing.
2. Design a protected, ephemeral signing environment and verify a signed archive,
   export, profile, entitlement, version, binary and symbol provenance. Actual
   certificate, profile, credential and environment configuration requires
   separate action-specific approval; never commit or log those materials.
3. Under separately approved Apple access, upload the exact verified artifact,
   wait for processing, reconcile immutable build identity and inspect metadata.
   Apple's documented upload options include Transporter and altool:
   https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
4. Obtain physical-device QA on the signed release candidate, including the
   applicable checklist in Development/Kin13LayeredValidation.md. Only after
   explicit approval may automation submit the matching build for review or
   request release. Verify the resulting App Store Connect state; an API request
   alone is not proof that Apple processed, approved or published it. Apple's
   API supports build and app-management automation:
   https://developer.apple.com/app-store-connect/api/

The validation and release archive should use the same verified source and
compatible pinned hosted toolchain. Any source, build-input or toolchain mismatch
requires explicit review; do not reuse a simulator test as proof of the signed
binary. Account agreements, Apple-side processing and other account-holder
actions may still require human intervention. No step here authorizes creating
credentials, changing security settings, submission or publication.
