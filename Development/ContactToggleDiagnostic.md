# Nonshipping import-review switch observation

Hypothesis: the immediate off value after the single tap may reflect delayed
observation, missed event delivery, or a binding/state problem. This one-run
diagnostic keeps the original test and assertion: it saves the value at the
original assertion point and, only if it is off, observes for five seconds
before asserting the saved value. A later on value therefore does not turn the
original failure into a pass.

The disposable build logs fixed-field touch hit tests, review-binding entry and
state, monotonic action markers, geometry presence and an app heartbeat. A
late state change supports an observation-timing hypothesis; a captured touch
and binding transition with an unchanged accessibility value suggests further
state/observation investigation. Missing events alone never prove non-delivery,
even with a calibrated window, because the operating-system log can drop data.
Instrumentation can change timing. A passing test, incomplete capture or failure
before the target action is inconclusive; do not repeat it merely for a failure.

The original full-run failure remains retained separately. The public diagnostic
artifact contains fixed test identity, final counts, allowlisted event values,
failure category and digest, and simulator cleanup outcomes. Raw XCTest bundles
are not uploaded because they can contain unrelated hosted-process diagnostics.
The runner uses a fresh simulator with default synthetic sample contacts, no
Contacts or Photos permission grant and no photo seeding; those differences from
the full CI setup limit comparison. The build and any injected app code are
isolated from the release source.
