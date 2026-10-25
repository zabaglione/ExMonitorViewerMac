#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ "$(uname -m)" != "arm64" ]]; then
  printf 'Tests require a local arm64 Mac host.\n' >&2
  exit 2
fi

xcodebuild \
  -project "$ROOT_DIR/ExMonitorViewerMac.xcodeproj" \
  -scheme ExMonitorViewerMac \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$ROOT_DIR/build/TestDerivedData" \
  -clonedSourcePackagesDirPath "$ROOT_DIR/build/SourcePackages" \
  ARCHS=arm64 \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_STYLE=Manual \
  test
