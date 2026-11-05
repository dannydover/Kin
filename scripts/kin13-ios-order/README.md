# Bounded iOS execution-order diagnostic

This one-time nonshipping diagnostic tests the unmodified source commit
`627d3d57df5ff3094d5872cd8a1beebf355ae0c7` on a fresh GitHub-hosted iOS 27
simulator using Xcode 27.0. It derives 164 exact iOS test identities and 164
hashed test-start titles from retained baseline run 42115785349. No real
Contacts or Photos access is granted. Source and diagnostic commits are recorded
separately in the retained artifacts.

The 35 baseline suites are partitioned without overlap. The alphabetically later
18 suites run first, then the earlier 17, using two `test-without-building`
invocations on the same freshly created simulator and a product built once from
the exact source. Each test keeps the existing execution allowance. The verifier
requires passing finalized results with zero skips, matching per-batch and full
identity sets, exactly one observed start for every baseline title hash, and a
different combined observed start sequence. Missing, duplicate, interrupted or
failed results remain failures. Both bundles, manifests, filtered progress, and
simulator cleanup are retained. The runner console stream is not uploaded
separately; XCTest bundles can contain synthetic test output.

This tests ordering across two explicit batches. It does not reproduce a single
continuous test-host process for all 164 tests, and cannot establish interaction
between the two batches within one process. It does not change the required PR
gate or erase the previous same-order trials and their cleanup observations.

The first attempt, run 42119226838, reported 94 and 70 passing identities and a
changed observed order, but both result uploads failed after packaging used an
incorrect temporary location. Its job failed; the unretained bundles cannot be
independently checked. Simulator shutdown, deletion and absence were verified.
The revised packager keeps the runner's temporary directory unchanged, preserves
partial bundles on summary failure, and validates each finalized archive hash.
