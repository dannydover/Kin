# Release preparation protocol

Keep the README evergreen. Record each candidate's change list and public What's
New separately from private App Review notes and private verification evidence.
Never put signing materials, device identifiers or personal notebook data in a PR.

1. Develop on a feature branch and open a draft PR early once publication is
   authorized. Run automated checks and record the owner's Kin Dev QA against an
   identified source revision and build. Deferred checks remain explicitly deferred.
2. Freeze code, assets, version/build and the reviewed notes. Merge only after
   approval and required checks, without bypassing branch protections. Recheck
   the resulting main commit: a squash merge creates a different SHA from the
   feature branch and from any archive built before that merge.
3. Archive a clean checkout of that exact main SHA using existing authorized
   signing. Verify the archive's actual bundle identity, version/build, icon,
   privacy/entitlements and dSYM identity. Preserve the archive, dSYMs and a private
   build manifest binding source SHA/tree, toolchain, settings, artifact hashes,
   tests and any limitations. Do not substitute branch or squash SHAs in the record.
4. Validate with Apple, then upload only after the relevant authorization. Wait
   for processing and verify the selected build and metadata in App Store Connect.
   Validation, upload, submission and release are distinct operations.
5. Obtain the owner's final go/no-go identifying the build, public notes and
   release choice. Submit only within that approval. Verify actual store
   availability separately from submission, approval or processing status.
6. Prepare the public GitHub release from verified shipped provenance using
   [the repository release instructions](../scripts/RELEASING.md). Never infer a
   shipped archive SHA solely from the current main branch or version number.

For historical cleanup, preserve the original archive-source identity. If an
existing source tree is published through a connector that recreates commit
metadata, verify the remote tree exactly and record both SHAs honestly. An
identical file tree does not make two commit hashes identical. Do not replace a
submitted binary merely to make Git history appear to follow a newer protocol.
Record any historical uncommitted build-configuration patch and its scope in
private provenance; do not silently present an application-source commit as a
clean exact archive-source commit when those differ.
