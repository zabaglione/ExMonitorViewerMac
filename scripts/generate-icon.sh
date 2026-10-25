#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ICONSET_PARENT="$ROOT_DIR/build/iconset"
ICONSET_DIR="$ICONSET_PARENT/AppIcon.iconset"
GENERATOR="$ROOT_DIR/build/generate-icon"

mkdir -p "$ROOT_DIR/build" "$ROOT_DIR/Resources"
rm -rf "$ICONSET_PARENT"
xcrun swiftc \
  -module-cache-path "$ROOT_DIR/build/SwiftModuleCache" \
  "$SCRIPT_DIR/generate-icon.swift" \
  -o "$GENERATOR"
"$GENERATOR" "$ICONSET_DIR"
xcrun iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/Resources/AppIcon.icns"
printf 'Generated icon: %s\n' "$ROOT_DIR/Resources/AppIcon.icns"
