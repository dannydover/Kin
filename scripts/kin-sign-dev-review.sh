#!/bin/bash
# Guard direct invocation outside the separately approved signing-only job.
if [[ "${KIN_DEV_SIGNING_ONLY:-}" != 1 ]]; then
  printf '%s\n' 'Kin Dev signing requires the approved signing-only job.' >&2
  exit 1
fi

# Everything below is illustrative and has NOT been exercised with signing.
# The example reserves separate step deadlines plus job-level cleanup slack.
set +x
set -euo pipefail
umask 077
[[ "${GITHUB_REF:-}" == refs/heads/main && "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ ]]
[[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]]
[[ "${TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ && "${PROFILE_UUID:-}" =~ ^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}$ ]]
[[ "${VERSION:-}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ && "${BUILD:-}" =~ ^[1-9][0-9]*$ ]]
[[ "${CERT_SHA256:-}" =~ ^[a-f0-9]{64}$ ]]
test -n "${P12_BASE64:-}" && test -n "${P12_PASSWORD:-}" && test -n "${PROFILE_BASE64:-}"
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
test -z "$(git status --porcelain)"
test "$(git ls-remote https://github.com/dannydover/Kin.git refs/heads/main 2>/dev/null | cut -f1)" = "$GITHUB_SHA"
test "$(xcodebuild -version)" = "$(printf 'Xcode 27.0\nBuild version 27A266a')"
test "$(uname -m)" = arm64
work="$RUNNER_TEMP/kin-sign-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
mkdir -m 700 "$work"
profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profile_dir"
profile="$profile_dir/$PROFILE_UUID.mobileprovision"
# noclobber prevents replacing an existing profile; marker follows creation.
touch "$work/profile-staging"
[[ ! -e "$profile" && ! -L "$profile" ]]
( set -o noclobber; printf '%s' "$PROFILE_BASE64" | base64 -D > "$profile" )
stat -f '%d:%i' "$profile" > "$work/profile-identity"
shasum -a 256 "$profile" | cut -d ' ' -f1 > "$work/profile-sha256"
printf '%s\n' "$profile" > "$work/owned-profile"
printf '%s' "$P12_BASE64" | base64 -D > "$work/identity.p12"
key_password="$(openssl rand -hex 24)"
security list-keychains -d user > "$work/search-list-original" 2> "$work/security.log"
security create-keychain -p "$key_password" "$work/signing.keychain-db" >>"$work/security.log" 2>&1
security set-keychain-settings -lut 3600 "$work/signing.keychain-db" >>"$work/security.log" 2>&1
security unlock-keychain -p "$key_password" "$work/signing.keychain-db" >>"$work/security.log" 2>&1
security import "$work/identity.p12" -k "$work/signing.keychain-db" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >>"$work/security.log" 2>&1
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$key_password" "$work/signing.keychain-db" >>"$work/security.log" 2>&1
security list-keychains -d user -s "$work/signing.keychain-db" >>"$work/security.log" 2>&1
unset P12_BASE64 P12_PASSWORD PROFILE_BASE64 key_password
export_options="$work/ExportOptions.plist"
TEAM_ID="$TEAM_ID" PROFILE_UUID="$PROFILE_UUID" EXPORT_OPTIONS="$export_options" python3 -c '
import os, plistlib
with open(os.environ["EXPORT_OPTIONS"], "xb") as f:
    plistlib.dump({"destination":"export", "method":"app-store-connect", "signingStyle":"manual", "teamID":os.environ["TEAM_ID"], "signingCertificate":"Apple Distribution", "provisioningProfiles":{"com.intriguingideas.Kin.dev":os.environ["PROFILE_UUID"]}}, f)
'
xcodebuild -project Kin.xcodeproj -scheme 'Kin Dev' -configuration Dev -destination 'generic/platform=iOS' \
  -derivedDataPath "$work/DerivedData" -archivePath "$work/Kin.xcarchive" archive \
  CODE_SIGN_STYLE=Manual "DEVELOPMENT_TEAM=$TEAM_ID" "PROVISIONING_PROFILE_SPECIFIER=$PROFILE_UUID" \
  'CODE_SIGN_IDENTITY=Apple Distribution' >"$work/archive.log" 2>&1
xcodebuild -exportArchive -archivePath "$work/Kin.xcarchive" -exportPath "$work/export" \
  -exportOptionsPlist "$export_options" >"$work/export.log" 2>&1
ipa="$work/export/Kin.ipa"
test -f "$ipa" && test ! -L "$ipa"
# Reject unsafe names, link entries, oversized archives and multiple apps.
# This is not a general hostile-archive extractor; Xcode output remains trusted.
python3 scripts/check_ipa_layout.py "$ipa"
mkdir -m 700 "$work/inspect"
# The IPA is produced in this owned workspace; extraction policy requires review.
ditto -x -k "$ipa" "$work/inspect"
app="$work/inspect/Payload/Kin.app"
test -d "$app" && test ! -L "$app"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")" = com.intriguingideas.Kin.dev
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Info.plist")" = "$BUILD"
cmp -s "$profile" "$app/embedded.mobileprovision"
codesign --verify --deep --strict --all-architectures --test-requirement "=anchor apple generic and identifier \"com.intriguingideas.Kin.dev\" and certificate leaf[subject.OU] = \"$TEAM_ID\"" "$app" >"$work/verify.log" 2>&1
( cd "$work"; codesign --display --extract-certificates "$app" >/dev/null 2>&1 )
test "$(shasum -a 256 "$work/codesign0" | cut -d ' ' -f1)" = "$CERT_SHA256"
codesign --display --entitlements - --xml "$app" >"$work/entitlements.plist" 2>>"$work/verify.log"
python3 scripts/check_dev_entitlements.py "$work/entitlements.plist" "$TEAM_ID"
shasum -a 256 "$ipa" | cut -d ' ' -f1 > "$work/ipa-sha256"
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
test -z "$(git status --porcelain)"
test "$(git ls-remote https://github.com/dannydover/Kin.git refs/heads/main 2>/dev/null | cut -f1)" = "$GITHUB_SHA"
printf '%s\n' 'Dev candidate verified in private workspace; no upload occurred.'
