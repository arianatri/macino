#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MODE="${1:-release}"
swift build -c "$MODE" --triple arm64-apple-macosx14.0
APP="build/macino.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$MODE/macino" "$APP/Contents/MacOS/macino"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
./Scripts/build-android-tools.sh
./Scripts/build-reader-tools.sh
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
