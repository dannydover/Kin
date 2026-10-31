# Nonshipping Photos query order comparison

Hypothesis: the Photos navigation-bar accessibility query may stall because of
state accumulated by prior tests in the same simulator, or it may stall
independently of those tests. This single A/B run uses the same pinned toolchain,
fresh synthetic simulator, runner Contacts grant and synthetic Photos seed in
both arms. One arm runs the original photo-removal test alone; the other first
runs the four tests that preceded it in the failed UI-1 run. The diagnostic
verifies the actual selected identities and observed test-start order.

A test-only print immediately before and after the existing 15-second Photos
navigation-bar wait records whether that synchronous query returns. The original
assertion, time limits, UI actions and all end-state checks remain unchanged.
A result is never marked passed if the test fails, skips or does not finalize.

If only the ordered arm stalls, shared prior state or order is a supported
hypothesis, not a proven cause. If both stall, the issue can occur without those
predecessors, but its source remains unknown. If both pass, the comparison is
inconclusive and stops; do not repeat it simply to obtain a failure. Runner
contention and instrumentation can affect timing.

The uploaded artifact retains fixed test identities, counts, observed order,
allowlisted progress/readiness stages, failure category and digest, and
separate simulator cleanup records. Raw XCTest bundles are not uploaded because
they can contain unrelated hosted-process diagnostics. The original full-run
failure bundle is retained separately.
