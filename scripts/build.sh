#!/bin/bash
# Coffer build check: regenerates the Xcode project and compiles for a generic iOS device without signing.
# Usage: ./scripts/build.sh
# Success = last line prints "BUILD OK". Any other result is a failure and must be fixed.
set -uo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Run: brew install xcodegen"; exit 1
fi

if [ ! -d Vendor/MobileVLCKit.xcframework ]; then
  echo "Vendor/MobileVLCKit.xcframework missing. Run: ./scripts/fetch-vlckit.sh  (about 250 MB, resumable)"; exit 1
fi

xcodegen generate --quiet || { echo "XCODEGEN FAILED"; exit 1; }

LOG=build/last-build.log
mkdir -p build
xcodebuild \
  -project Coffer.xcodeproj \
  -scheme Coffer \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build > "$LOG" 2>&1
STATUS=$?

# Show errors and warnings from our own sources only (not from Vendor / SPM checkouts).
grep -E "(error|warning):" "$LOG" | grep -v "/build/DerivedData/SourcePackages/" | grep -v "/Vendor/" | sort -u | head -200

if [ $STATUS -eq 0 ] && grep -q "BUILD SUCCEEDED" "$LOG"; then
  echo "BUILD OK"
else
  echo "BUILD FAILED (full log: $LOG)"
  exit 1
fi
