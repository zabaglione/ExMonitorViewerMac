#!/bin/bash
set -euo pipefail

# Package an already notarized, stapled app. This script does not notarize the DMG.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
EXPECTED_APP_NAME="ExMonitorViewerMac.app"

usage() {
  printf 'Usage: %s <notarized-%s>\n' "$0" "$EXPECTED_APP_NAME" >&2
}

fail() {
  printf 'package-dmg: %s\n' "$1" >&2
  exit 1
}

if [[ "$#" -ne 1 ]]; then
  usage
  exit 64
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail 'DMG packaging requires macOS.'
fi

APP_ARGUMENT="$1"
if [[ "$APP_ARGUMENT" = /* ]]; then
  APP_CANDIDATE="$APP_ARGUMENT"
else
  APP_CANDIDATE="$ROOT_DIR/$APP_ARGUMENT"
fi

if [[ ! -d "$APP_CANDIDATE" || -L "$APP_CANDIDATE" ]]; then
  fail "App bundle is missing or is a symlink: $APP_CANDIDATE"
fi

APP_PATH="$(cd -- "$APP_CANDIDATE" && pwd -P)"
APP_NAME="${APP_PATH##*/}"
if [[ "$APP_NAME" != "$EXPECTED_APP_NAME" ]]; then
  fail "Expected $EXPECTED_APP_NAME, received $APP_NAME."
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  fail "App bundle has no Contents/Info.plist: $APP_PATH"
fi

BUNDLE_TYPE="$(/usr/bin/plutil -extract CFBundlePackageType raw -o - "$INFO_PLIST")" || fail 'Could not read CFBundlePackageType.'
BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")" || fail 'Could not read CFBundleIdentifier.'
BUNDLE_EXECUTABLE="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")" || fail 'Could not read CFBundleExecutable.'

if [[ "$BUNDLE_TYPE" != 'APPL' || "$BUNDLE_ID" != 'com.zabaglione.ExMonitorViewerMac' ]]; then
  fail "Unexpected app identity: type=$BUNDLE_TYPE bundle-id=$BUNDLE_ID"
fi
if [[ -z "$BUNDLE_EXECUTABLE" || "$BUNDLE_EXECUTABLE" == */* || ! -x "$APP_PATH/Contents/MacOS/$BUNDLE_EXECUTABLE" ]]; then
  fail 'App executable is missing or invalid.'
fi

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"; then
  fail 'App code signature verification failed.'
fi
if ! /usr/bin/xcrun stapler validate "$APP_PATH"; then
  fail 'App notarization ticket validation failed; provide a stapled app.'
fi
if ! /usr/sbin/spctl --assess --type execute --verbose=2 "$APP_PATH"; then
  fail 'Gatekeeper did not accept the app.'
fi

BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
OUTPUT_DMG="$DIST_DIR/ExMonitorViewerMac.dmg"
mkdir -p "$BUILD_DIR" "$DIST_DIR"
WORK_DIR="$(/usr/bin/mktemp -d "$BUILD_DIR/package-dmg.XXXXXX")"

cleanup() {
  local exit_code=$?
  trap - EXIT
  if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
    /bin/rm -rf -- "$WORK_DIR"
  fi
  exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

STAGING_DIR="$WORK_DIR/staging"
STAGED_APP="$STAGING_DIR/$EXPECTED_APP_NAME"
TEMP_DMG="$WORK_DIR/ExMonitorViewerMac.dmg"
mkdir -p "$STAGING_DIR"

# Copy into a private staging directory so the signed source bundle stays untouched.
/usr/bin/ditto "$APP_PATH" "$STAGED_APP"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP" || fail 'Staged app signature verification failed.'

# The two Finder items provide the standard drag-to-Applications install layout.
# No DS_Store editing, volume mounting, GUI automation, or app modification is used.
/usr/bin/hdiutil create \
  -srcfolder "$STAGING_DIR" \
  -volname 'ExMonitorViewerMac' \
  -fs HFS+ \
  -format UDZO \
  "$TEMP_DMG"
/usr/bin/hdiutil verify "$TEMP_DMG"

if [[ ! -s "$TEMP_DMG" ]]; then
  fail 'hdiutil produced an empty DMG.'
fi
/bin/mv -f "$TEMP_DMG" "$OUTPUT_DMG"
printf 'Created DMG: %s\n' "$OUTPUT_DMG"
