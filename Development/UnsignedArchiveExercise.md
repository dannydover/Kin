# Unsigned hosted archive exercise

This bounded PR-only exercise explores whether the archive mechanics can run on
a standard hosted macOS runner without an unlocked personal Mac. It creates an
**unsigned** archive in the runner's temporary directory. It is not an App Store
build, cannot be installed as a signed app, and does not upload, submit or
publish anything. The ordinary required CI aggregate is unchanged.

The separate workflow runs a job only on a pull request from this repository
with the designated exercise branch. Remove this one-off workflow before merge. It pins the same Xcode 27.0 build and arm64 runner as current
CI. It records the actual checkout commit and tree (on a pull request this can
be GitHub's merge commit), app source tree, actual Xcode and iPhone SDK versions
and builds, bundle/version/build, executable and dSYM hashes, and the matching
architecture and UUID in a seven-day sanitized manifest. It does not retain the
archive, binary, raw build log, signing assets, personal data, or credentials.
The job uses only a short-lived contents-read token and never contacts Apple.

Verification requires a clean checkout matching the workflow event SHA; matching
literal Release project identity, built app plist and archive plist; unsigned
iPhone Release checks; the actual SDK and Xcode build metadata; and a matching
arm64 executable/dSYM UUID. Missing, mismatched or unparseable evidence fails
the job and removes any earlier manifest. A clean metadata comparison is not a
claim of binary reproducibility or a substitute for signed archive verification.

Run the exercise once on the exact review head and inspect job outcome and the
sanitized manifest. Runner availability, installed SDKs and archive output must
be verified by that run; local compilation alone does not validate GitHub's
Xcode 27.0 image. Do not treat an empty or missing manifest, timeout or failed
job as a pass. A subsequent real signed archive needs a separately reviewed
protected execution environment and approved distribution signing materials.
Apple upload further requires separately approved Apple access and processing
verification. Physical-device QA, submission and release approval remain
independent decisions. Do not weaken the Mac's lock or keychain protections.
