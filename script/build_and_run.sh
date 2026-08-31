#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Rewrite"
BUNDLE_ID="com.rewriteapp.Rewrite"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/work/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

stop_current_debug_build() {
  # Match the project-local app bundle, not any separately installed Rewrite app.
  pkill -f "$APP_BINARY" >/dev/null 2>&1 || true
}

build() {
  xcodebuild \
    -project "$ROOT_DIR/RewriteApp.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    -derivedDataPath "$DERIVED_DATA" \
    build
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

stop_current_debug_build
build

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -f "$APP_BINARY" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
