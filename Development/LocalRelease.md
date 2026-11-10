# Local release validation

GitHub's required `validate` check covers the repository/privacy guard, Python
script tests and simulator-free Swift Core tests. It does not run the iOS
simulator suites or compile a Release app. Run those checks on Mac Studio for
the exact candidate source and record their results before device QA or release.
Earlier hosted failures and passes remain historical evidence; this cutover does
not establish that intermittent simulator or Friend behavior was fixed.

1. Freeze and review the candidate. After approved merge, check out the exact
   `main` commit, confirm `git status --porcelain` is empty and record `git rev-parse
   HEAD`, the source tree, Xcode version and build, installed SDK/runtime,
   scheme, version and build. Confirm build availability in App Store Connect;
   build 7 was only provisional. Do not override the checked-in version locally.
2. On an isolated, fresh simulator with synthetic fixtures, run the full iOS
   unit/integration and UI suites for the relevant schemes using Xcode's Test
   action or the commands in the README. Record the selected tests, completed
   result counts, failures, skips and simulator cleanup. A missing, partial,
   failed or skipped required result is not a pass. Prepare synthetic Contacts
   and Photos fixtures as the tests require; preserve all real user data. Native
   Photos/Contacts manual testing is required when the changes affect those
   flows. Do not claim physical device behavior from simulator results.

   For a newly created and booted synthetic-only simulator, seed its photo and
   grant Contacts only to the relevant UI test runner before the suite:

   ```sh
   python3 scripts/create-simulator-photo.py "$TMPDIR/kin-synthetic-photo.png"
   xcrun simctl addmedia "$SIMULATOR_ID" "$TMPDIR/kin-synthetic-photo.png"
   xcrun simctl privacy "$SIMULATOR_ID" grant contacts com.intriguingideas.KinUITests.xctrunner
   # For the separate Kin Dev UI runner, use:
   xcrun simctl privacy "$SIMULATOR_ID" grant contacts com.intriguingideas.Kin.dev.uitests.xctrunner
   ```

   Set `SIMULATOR_ID` to the UUID of the isolated simulator you created; delete
   only that simulator after the run and verify it is absent. The test runner's
   synthetic Contacts cleanup must also complete. Retain the finalized result
   bundle privately. The README contains example `xcodebuild` commands.
3. Build and validate the unsigned Release device app on Mac Studio using
   `scripts/build-unsigned-device.sh` and `scripts/check-release.py`. Run the
   Release scheme's applicable simulator tests locally. Record the outcome and
   toolchain. Keep all test results and build products private.
4. First archive **Kin Dev** for TestFlight using the ordinary Xcode Archive
   action and Organizer, with its separate Dev bundle identifier and authorized
   Dev distribution profile. Verify signed identity and entitlements preserve
   its separate sandbox; never install a Dev artifact over production Kin. Keep
   the archive and dSYMs privately, together with a short record binding exact
   source SHA/tree, Xcode, scheme, bundle, version/build and validation results.
   Existing signing access and actual archive/export still require verification;
   this local process does not resolve the earlier keychain failure. Upload
   requires the separately applicable approval and TestFlight settings review.

   The App Store distribution signature has debugging disabled and may contain
   Apple's `beta-reports-active` entitlement. Validate its signed entitlements
   with `scripts/check_dev_entitlements.py`, passing a private plist extracted
   with `codesign --display --entitlements :-` and the reviewed team identifier.
   This distribution check permits either no explicit keychain access groups or
   only the exact Dev app group; it rejects shared and unexpected entitlements.
   `scripts/check-dev-app.py --require-signed` is a separate development-install
   check and intentionally requires a development profile with debugging enabled.
5. Install the processed Kin Dev build via TestFlight and complete
   [Kin Dev manual QA](QA-NextRelease.md), including the required Friend-on,
   save and relaunch persistence check. Document the result against the exact
   build. Dev QA does not establish production Release signing, existing-data
   upgrade or the final production binary's behavior.
6. For production, separately archive the reviewed exact-main Release source,
   preserve its archive/dSYMs and evidence, verify identity, version/build and
   upgrade/device behavior, and obtain applicable approval before upload,
   submission and release. Verify actual App Store approval **and distribution**
   of the intended build. TestFlight, processing and submission are not store
   distribution. Only then prepare/publish the GitHub release using
   [RELEASING.md](../scripts/RELEASING.md).

The retired hosted signing workflows must be absent from merged main before any
later decision to delete their GitHub environment or secrets. This document does
not authorize deleting them or change the required GitHub branch protections.
