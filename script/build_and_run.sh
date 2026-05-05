#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/SwiftClip.app"

cd "$PROJECT_DIR"

if pgrep -x SwiftClip >/dev/null 2>&1; then
  pkill -x SwiftClip || true
fi

xcodebuild \
  -project SwiftClip.xcodeproj \
  -scheme SwiftClip \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

/usr/bin/open -n "$APP_PATH"

if [[ "${1:-}" == "--verify" ]]; then
  sleep 2
  pgrep -x SwiftClip >/dev/null
fi

if [[ "${1:-}" == "--telemetry" || "${1:-}" == "--logs" ]]; then
  /usr/bin/log stream --info --predicate 'subsystem == "app.swiftclip"'
fi
