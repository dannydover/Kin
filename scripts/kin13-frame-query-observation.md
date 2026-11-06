# Relationship action frame observation

In required run 41609900446, the largest-text relationship-action journey
exceeded its four-minute allowance. The retained XCTest spindump located the
test runner in the second consecutive `action.frame` measurement: the width
assertion after the height assertion. It was waiting for a remotely evaluated
accessibility snapshot. This observation does not identify why the query stalled.

The test now reads one action-frame snapshot for its existing height, width,
horizontal-position and largest-text assertions. Each scroll observation also
uses one frame rather than resolving that same frame separately for each edge.
The 18-gesture limit, hittability check, bounds, minimum sizes, navigation and
relationship assertions are unchanged. Sampling a single frame gives those
geometry checks one consistent observation; it can differ from observations
taken at separate instants. A remaining frame query can still block, so this
change does not establish a fix for the timeout or other picker failures.
