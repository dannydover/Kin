# Kin Dev

Select the shared **Kin Dev** scheme and **Dev** configuration. This uses
`com.intriguingideas.Kin.dev`, display name **Kin Dev**, and a separate blue
blueprint icon. Kin uses its own bundle identifier and native layered production
icon. The schemes keep identity, signing/entitlements and storage distinct.

Dev inherits Debug compiler behavior. All scheme actions, including Archive,
select Dev. Neither this scheme nor these instructions distribute an app.

## Isolation

The app's existing Application Support `Kin/Kin.sqlite`, photos and temporary
files resolve inside its own iOS data sandbox. A separate bundle identifier
creates a separate sandbox; no production data is read, copied or migrated.
The source has no shared App Group container, custom Keychain access, iCloud or
CloudKit use, extensions, account system or network backend. The Dev entitlement
file is deliberately empty. A signed build must use only its own application
identifier and default Keychain group; never add a production/shared group.

## Build and check

```sh
python3 -m unittest discover -s scripts/tests -v
scripts/test-core.sh
xcodebuild -project Kin.xcodeproj -scheme 'Kin Dev' -configuration Dev \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData \
  build CODE_SIGNING_ALLOWED=NO
python3 scripts/check-dev-app.py DerivedData/Build/Products/Dev-iphoneos/Kin.app
scripts/build-unsigned-device.sh
python3 scripts/check-release.py DerivedData/Build/Products/Release-iphoneos/Kin.app
```

Run KinTests with each scheme on a fresh isolated iPhone simulator. Release
unit tests use `@testable import`, so pass `ENABLE_TESTABILITY=YES` only on
the test command; do not change the checked-in Release settings. Automated
UI tests require the documented synthetic Photos fixture. Never test against a
personal notebook. Simulator results do not establish physical device behavior.

## Physical installation gate

Signing is manual and has no checked-in team or provisioning profile. Supply
only an already authorized existing development identity/team/profile locally.
Do not enable automatic provisioning or create credentials, App IDs, profiles,
new access, trust settings or Developer Mode without specific approval.
A profile for `com.intriguingideas.Kin` cannot sign this separate identifier.

Before any installation, verify the compiled signed app:

```sh
python3 scripts/check-dev-app.py --require-signed \
  DerivedData/Build/Products/Dev-iphoneos/Kin.app
```

After this passes, use `xcrun devicectl` to install only that verified app on the
existing trusted phone. Query both bundle identifiers to verify coexistence.
Launch only `com.intriguingideas.Kin.dev`; report installation and actual launch
separately. Never uninstall or replace the App Store Kin.

The development icon is a native SVG blueprint interpretation of the same
outlined two-disc K design used by the production icon. See
[icon provenance and preparation](DevIcon.md). Icon sources and flat fallback
assets are separate from screenshots and personal data.
