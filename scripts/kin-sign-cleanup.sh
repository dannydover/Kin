#!/bin/bash
# REVIEW-ONLY: this unconditional guard must remain until specifically approved.
printf '%s\n' 'Signing cleanup is disabled in the local proposal.' >&2
exit 1

set +x
set -euo pipefail
[[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]]
work="$RUNNER_TEMP/kin-sign-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
if [[ ! -e "$work" && ! -L "$work" ]]; then
  printf '%s\n' 'Cleanup cannot be verified: workspace unavailable.' >&2
  exit 1
fi
test -d "$work" && test ! -L "$work"
failed=0
if [[ -L "$work/search-list-original" ]]; then
  failed=1
elif [[ -f "$work/search-list-original" ]]; then
  if python3 -c 'import pathlib,shlex,sys; p=shlex.split(pathlib.Path(sys.argv[1]).read_text()); assert all("\n" not in x for x in p); print("\n".join(p))' "$work/search-list-original" > "$work/search-list-restore"; then
    old=()
    while IFS= read -r path; do old+=("$path"); done < "$work/search-list-restore"
    if (( ${#old[@]} > 0 )); then
      security list-keychains -d user -s "${old[@]}" >/dev/null 2>&1 || failed=1
      if ! security list-keychains -d user > "$work/search-list-current" 2>/dev/null ||
         ! python3 -c 'import pathlib,shlex,sys; a,b=(shlex.split(pathlib.Path(x).read_text()) for x in sys.argv[1:]); assert a and a == b' "$work/search-list-original" "$work/search-list-current"; then failed=1; fi
    else failed=1; fi
  else failed=1; fi
else
  failed=1
fi
if [[ -L "$work/signing.keychain-db" ]]; then
  failed=1
elif [[ -e "$work/signing.keychain-db" ]]; then
  security delete-keychain "$work/signing.keychain-db" >/dev/null 2>&1 || failed=1
  if [[ -e "$work/signing.keychain-db" || -L "$work/signing.keychain-db" ]]; then failed=1; fi
fi
if [[ -L "$work/owned-profile" ]]; then
  failed=1
elif [[ -f "$work/owned-profile" ]]; then
  IFS= read -r profile < "$work/owned-profile" || failed=1
  if [[ ! "${PROFILE_UUID:-}" =~ ^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}$ ]] ||
     [[ "${profile:-}" != "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision" ]] ||
     [[ -L "$profile" || ! -f "$profile" ]] ||
     [[ -L "$work/profile-identity" || ! -f "$work/profile-identity" || -L "$work/profile-sha256" || ! -f "$work/profile-sha256" ]] ||
     [[ "$(stat -f '%d:%i' "$profile")" != "$(cat "$work/profile-identity")" ]] ||
     [[ "$(shasum -a 256 "$profile" | cut -d ' ' -f1)" != "$(cat "$work/profile-sha256")" ]]; then
    failed=1
  elif rm -f -- "$profile" && [[ ! -e "$profile" && ! -L "$profile" ]]; then
    rm -f -- "$work/profile-staging" "$work/profile-identity" "$work/profile-sha256" "$work/owned-profile" || failed=1
  else failed=1; fi
elif [[ -e "$work/profile-staging" || -L "$work/profile-staging" || -e "$work/owned-profile" ]]; then
  # Do not guess whether a partly staged or pre-existing profile is ours.
  failed=1
fi
# Remove secrets, raw logs and signed outputs even on failure. Keep ownership
# and search-list evidence, and any undeleted keychain, for safe recovery.
rm -f -- "$work/identity.p12" "$work/security.log" "$work/archive.log" "$work/export.log" "$work/verify.log" "$work/entitlements.plist" "$work/ExportOptions.plist" || failed=1
rm -f -- "$work"/codesign[0-9]* || failed=1
rm -rf -- "$work/Kin.xcarchive" "$work/DerivedData" "$work/export" "$work/inspect" || failed=1
if (( failed )); then printf '%s\n' 'Cleanup incomplete; private recovery evidence retained.' >&2; exit 1; fi
rm -rf -- "$work" || failed=1
if [[ -e "$work" || -L "$work" ]]; then failed=1; fi
if (( failed )); then printf '%s\n' 'Cleanup incomplete; private recovery evidence may remain.' >&2; exit 1; fi
