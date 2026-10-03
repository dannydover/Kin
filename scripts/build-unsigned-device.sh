#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
# Local compilation only. This neither provisions nor produces an installable signed app.
exec /usr/bin/xcodebuild -project Kin.xcodeproj -scheme Kin \
  -destination 'generic/platform=iOS' -configuration Release -derivedDataPath DerivedData \
  build CODE_SIGNING_ALLOWED=NO DEPLOYMENT_POSTPROCESSING=YES \
  STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=debugging "$@"
