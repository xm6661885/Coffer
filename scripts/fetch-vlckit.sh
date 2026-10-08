#!/bin/bash
# Downloads MobileVLCKit (static xcframework) into Vendor/. Safe to re-run; resumes partial downloads.
set -euo pipefail
cd "$(dirname "$0")/.."
VER="3.7.3-319ed2c0-79128878"
URL="https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-${VER}.tar.xz"
DEST="Vendor/MobileVLCKit.xcframework"
if [ -d "$DEST" ]; then echo "MobileVLCKit already present at $DEST"; exit 0; fi
mkdir -p Vendor/.tmp
for i in $(seq 1 50); do
  if curl -fL --retry 5 --retry-delay 3 -C - -o Vendor/.tmp/vlc.tar.xz "$URL"; then break; fi
  echo "Download interrupted, resuming (attempt $i)..."; sleep 3
done
xz -t Vendor/.tmp/vlc.tar.xz 2>/dev/null || tar -tf Vendor/.tmp/vlc.tar.xz >/dev/null || { echo "Archive incomplete. Re-run this script to resume."; exit 1; }
tar -xf Vendor/.tmp/vlc.tar.xz -C Vendor/.tmp
mv Vendor/.tmp/MobileVLCKit-binary/MobileVLCKit.xcframework "$DEST"
rm -rf Vendor/.tmp
echo "OK: $DEST"
