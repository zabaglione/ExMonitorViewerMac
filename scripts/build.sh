#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/build/DerivedData"
DIST_APP_PATH="$ROOT_DIR/dist/ExMonitorViewerMac.app"
SIGNING_IDENTITY="${EXMONITOR_SIGN_IDENTITY:--}"
CONFIGURATION=Release
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  CONFIGURATION=Debug
fi
APP_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/ExMonitorViewerMac.app"

ensure_app_stopped() {
  PROCESS_STATUS=0
  /usr/bin/pgrep -x ExMonitorViewerMac >/dev/null || PROCESS_STATUS=$?
  if [[ "$PROCESS_STATUS" -eq 0 ]]; then
    printf 'Quit ExMonitorViewerMac before rebuilding. Ad-hoc signing changes can require refreshing Screen Recording permission.\n' >&2
    exit 2
  elif [[ "$PROCESS_STATUS" -ne 1 ]]; then
    printf 'Unable to inspect running applications. Run this script from a local terminal with process access.\n' >&2
    exit 2
  fi
}

ensure_app_stopped

xcodebuild \
  -project "$ROOT_DIR/ExMonitorViewerMac.xcodeproj" \
  -scheme ExMonitorViewerMac \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -clonedSourcePackagesDirPath "$ROOT_DIR/build/SourcePackages" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_STYLE=Manual \
  REGISTER_APP_WITH_LAUNCH_SERVICES=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  printf 'Build succeeded but app product was not found: %s\n' "$APP_PATH" >&2
  exit 1
fi

ensure_app_stopped
mkdir -p "$ROOT_DIR/dist"
rm -rf "$DIST_APP_PATH"
ditto "$APP_PATH" "$DIST_APP_PATH"
LSREGISTER_PATH="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
if [[ -x "$LSREGISTER_PATH" ]]; then
  "$LSREGISTER_PATH" -u "$APP_PATH"
  "$LSREGISTER_PATH" -f "$DIST_APP_PATH"
fi
printf 'Built app: %s\n' "$DIST_APP_PATH"
