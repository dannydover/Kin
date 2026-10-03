# Kin

Kin is an iPhone notebook for remembering the people in your friends' families:
names, children, ages, relationships, and the little details worth keeping.

## Development status

Kin is in active development and is not yet a stable public release.

This checkout contains the family notebook implementation, its shared Xcode
scheme, and unit/integration tests. It targets **iPhone only, iOS 26 or later**,
using **Xcode 27, the Swift 6.4 compiler, and Swift 6 language mode**.

## App features

- Friends, current and former partners, and children grouped into families.
- Exact birthdays or estimated ages with reference dates, plus estimated school grades.
- Editable notes, optional photos, and one-time Contacts name/photo imports.
- Local Core Data storage, search, and explicit Save/Cancel editing.
- Adaptive layouts and accessibility support, including larger text.

Future features and proposals are tracked in [GitHub issues](https://github.com/dannydover/Kin/issues).
An issue is a proposal or work item, not a release commitment.

## Open, build, and test

Use a Mac with Xcode 27 and an installed iOS 26 or newer iPhone simulator runtime.
Xcode 27 requires macOS Tahoe 26.6 or later. Select Xcode's developer directory
explicitly if Command Line Tools or another Xcode is your system default:

```sh
git clone https://github.com/dannydover/Kin.git
cd Kin
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
open Kin.xcodeproj
```

In Xcode, select the shared **Kin** scheme and an available **iPhone simulator**.
Use **Product > Build**, **Product > Run**, or **Product > Test**. The shared
scheme includes the complete KinTests unit/integration suite (63 tests in 16
suites); the retained starter UI-test templates are not part of that suite.

```sh
# Core-only package suite (50 tests); no external packages.
scripts/test-core.sh

# Full suite, including UIKit Contacts/photo integration tests.
xcodebuild -project Kin.xcodeproj -scheme Kin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -derivedDataPath DerivedData test CODE_SIGNING_ALLOWED=NO

# Compile a Release build for iPhone without provisioning or signing.
scripts/build-unsigned-device.sh
```

Use a matching installed simulator name and OS in the test destination. iOS 26
compatibility testing is separate from the iOS 27 CI runtime; the deployment
target remains iOS 26.0. An unsigned device build is a compilation check and
cannot be installed as a signed app. For personal device development, configure
your own team locally and keep signing settings and materials out of commits.

Debug-only in-memory previews can be launched with `--kin-preview list` or
`--kin-preview empty`. They use fictional fixtures and do not open the saved
notebook. Release builds omit this preview entry point.

## Continuous integration

[Build and test](.github/workflows/ci.yml) runs on ordinary pull requests and
pushes to `main` with read-only repository permissions and no persisted checkout
credentials. It checks the indexed repository for prohibited data, runs both test
suites after a clean app build, and compiles unsigned iPhone and simulator Release builds. It does not
provision, distribute, or upload build products or logs as artifacts.

Release checks verify the iOS 26 minimum, iPhone-only device family, privacy
manifest, absence of debug previews and personal build paths, and absence of
developer signing or provisioning. The simulator linker may embed its own
ad-hoc signature; this uses no developer identity or signing credentials.

The workflow uses the arm64 `xcode-27` preview runner image, explicitly selecting
`/Applications/Xcode_27.app/Contents/Developer`. It prints and verifies Xcode 27.0
build 27A266a and Swift 6.4, prints SDK/runtime information, and tests on iPhone 17
with iOS 27.0. Toolchain/image changes fail visibly rather than silently changing
the required compiler. Runner availability and installed versions are documented
in the [official runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md);
see Apple's [Xcode system requirements](https://developer.apple.com/xcode/system-requirements).

The package has no external dependencies or `Package.resolved`. When dependencies
are introduced, commit the generated app lockfile for reproducible resolution.

## Data and privacy

The app keeps its notebook on the device. It has no account
system, app backend, analytics, or third-party package dependencies. Optional
Contacts and photo imports are one-time snapshots; ordinary operating-system
backup behavior still applies. Kin has no in-app sync or export feature.

Read the [privacy policy](https://www.intriguingideas.com/kin-privacy-policy)
for the app's data practices, including support correspondence. Do not put real
family information, children's details, Contacts exports, or notebook contents
in issues, pull requests, screenshots, or test fixtures.

## Support and security

For help, use [Kin support](https://www.intriguingideas.com/kin-support).
For suspected security vulnerabilities, use GitHub's private
[Report a vulnerability](https://github.com/dannydover/Kin/security/advisories/new)
form. Do not post exploitable details in public issues. If private reporting is
unavailable, email [kin-support@intriguingideas.com](mailto:kin-support@intriguingideas.com)
without secrets or personal notebook data.

## Contributing

Start with an issue for a substantial change, then open a focused pull request.
State which commit and tools you used, what changed, and how you tested it.
Use fictional names, dates, notes, and images, and test only with devices and data
you own or have permission to use.

Keep app data, signing materials, build products, and local execution evidence out
of commits. Include relevant tests with behavior changes. After staging changes, run
`python3 scripts/check-repository.py` to inspect the exact index contents. The
same guard runs against CI's checkout. It blocks unexpected files, signing and
credential patterns, personal paths/identifiers, and unreviewed raster artwork.
It complements human review; it cannot establish that arbitrary prose is
fictional or detect every secret. Review changed fixtures and assets before
publication. Public fixtures must remain synthetic.

## License and branding

The software is licensed under the [MIT License](LICENSE), which permits reuse,
modification, distribution, and commercial use under its terms.

The MIT License does not grant permission to use the Kin name or logo to imply
official origin or endorsement by Intriguing Ideas, LLC. This branding clarification
does not change the MIT terms or exclude asset copyrights from the license.
