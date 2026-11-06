#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(tr -d '\n' < VERSION)"
plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
if [ "$version" != "$plist_version" ]; then
    echo 'VERSION and Info.plist must match.' >&2
    exit 1
fi
./Scripts/package-dmg.sh
artifact="macino-${version}-arm64.dmg"
cp build/macino.dmg "build/$artifact"
(cd build && shasum -a 256 "$artifact" > SHA256SUMS.txt)
echo "Release files: build/$artifact and build/SHA256SUMS.txt"
echo 'Upload them with the notes from docs/releases/ to a GitHub release.'
