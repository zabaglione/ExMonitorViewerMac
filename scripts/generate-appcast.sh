#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TOOLS="$ROOT_DIR/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
ACCOUNT=ExMonitorViewerMac

if [[ $# -ne 2 || ! -d "$1" || "$2" != https://* ]]; then
  printf 'Usage: %s <final-release-archives-directory> <https-download-url-prefix>\n' "$0" >&2
  exit 64
fi
for tool in generate_keys generate_appcast sign_update; do
  if [[ ! -x "$TOOLS/$tool" ]]; then
    printf 'Resolve the pinned Sparkle package with scripts/build.sh first.\n' >&2
    exit 1
  fi
done
EXPECTED_KEY="$(/usr/bin/plutil -extract SUPublicEDKey raw -o - "$ROOT_DIR/Sources/ExMonitorViewerMac/Info.plist")"
# Read only the public key. Never generate or export a private key here.
ACTUAL_KEY="$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)"
if [[ "$ACTUAL_KEY" != "$EXPECTED_KEY" ]]; then
  printf 'The Keychain update signing key is missing or does not match this app.\n' >&2
  exit 1
fi
"$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 \
  --download-url-prefix "$2" "$1"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$1/appcast.xml"
printf 'Signed appcast prepared locally. Publish archives before publishing the feed.\n'
