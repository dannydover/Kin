#!/bin/bash
# REVIEW ONLY: must remain disabled until credentials and execution are approved.
printf '%s\n' 'Kin Dev upload is disabled.' >&2
exit 1

set +x
set -euo pipefail
umask 077
[[ "${GITHUB_REF:-}" == refs/heads/main && "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ ]]
[[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]]
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
test -z "$(git status --porcelain)"
work="$RUNNER_TEMP/kin-sign-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
ipa="$work/export/Kin.ipa"
test -f "$ipa" && test ! -L "$ipa" && test -f "$work/ipa-sha256"
test "$(shasum -a 256 "$ipa" | cut -d ' ' -f1)" = "$(cat "$work/ipa-sha256")"
evidence="$RUNNER_TEMP/kin-upload-evidence-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
mkdir -m 700 "$evidence"
KIN_VERIFIED_IPA="$ipa" KIN_UPLOAD_EVIDENCE_DIR="$evidence" python3 scripts/kin_upload_review.py
