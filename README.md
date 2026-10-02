# Kin

Kin is an iPhone notebook for remembering the people in your friends' families:
names, children, ages, relationships, and the little details worth keeping.

## Development status

Kin is in active development and is not yet a stable public release.

**This public checkout currently contains the original SwiftUI starter project.**
The fuller app implementation has been developed and tested locally but has not
been published to this repository. Cloning `main` does not yet provide the family
notebook features or its 63-test development suite. The starter unit and UI test
targets are present, but they are not that suite.

The local implementation targets **iPhone only, iOS 26 or later**, using
**Xcode 27, the Swift 6.4 compiler, and Swift 6 language mode**. The public starter
project still has iOS 26.5 as its deployment target, Swift 5 language mode, and
iPhone/iPad device families. Publishing the app implementation will reconcile
those settings; this README does not change them.

## App features in local development

These features are implemented locally and are not yet available in a public clone:

- Friends, current and former partners, and children grouped into families.
- Exact birthdays or estimated ages with reference dates, plus estimated school grades.
- Editable notes, optional photos, and one-time Contacts name/photo imports.
- Local Core Data storage, search, and explicit Save/Cancel editing.
- Adaptive layouts and accessibility support, including larger text.

Future features and proposals are tracked in [GitHub issues](https://github.com/dannydover/Kin/issues).
An issue is a proposal or work item, not a release commitment.

## Open, build, and test this checkout

Use a Mac with Xcode 27 and an installed iOS simulator runtime compatible with
the checkout's deployment target. Xcode 27 requires macOS Tahoe 26.6 or later.
The current starter needs iOS 26.5 or later; an iOS 27 iPhone simulator is suitable.

```sh
git clone https://github.com/dannydover/Kin.git
cd Kin
open Kin.xcodeproj
```

In Xcode, select the **Kin** scheme and an available **iPhone simulator**.
Use **Product > Build** to build, **Product > Run** to launch, and
**Product > Test** to run the test targets included in your checkout. Xcode can
create the scheme automatically; no shared scheme is currently committed on
`main`. If needed, create a Kin scheme in **Product > Scheme > Manage Schemes**
and add the KinTests and KinUITests targets to its Test action.

Simulator development avoids physical-device provisioning. To run on your own
iPhone, configure your own development team locally. Never commit certificates,
private keys, provisioning profiles, or machine-specific signing settings.

The public starter has no external Swift package dependencies or
`Package.resolved`. It also has no `Package.swift` or helper scripts, so
`swift test` and local-development script commands do not apply to this checkout.
When package dependencies are introduced, commit the generated app lockfile so
contributors use the same resolved versions.

These instructions describe the checked-in project structure. A fresh-clone
build and test run was not performed for this documentation change.

## Data and privacy

The local app implementation keeps its notebook on the device. It has no account
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
of commits. Include relevant tests with behavior changes. Do not assume the local
development features are available until their implementation is published.
