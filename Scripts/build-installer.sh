#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
INSTALLER="build/Install with love.app"
ICONSET=".build/InstallHeart.iconset"
mkdir -p "$INSTALLER/Contents/MacOS" "$INSTALLER/Contents/Resources" "$ICONSET"
cp .build/release/macinoInstaller "$INSTALLER/Contents/MacOS/macinoInstaller"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/Installer/InstallHeart.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" Resources/Installer/InstallHeart.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$INSTALLER/Contents/Resources/InstallHeart.icns"
cp Resources/InstallerInfo.plist "$INSTALLER/Contents/Info.plist"
rm -rf "$INSTALLER/Contents/Resources/macino.app"
ditto build/macino.app "$INSTALLER/Contents/Resources/macino.app"
codesign --force --sign - "$INSTALLER"
codesign --verify --deep --strict "$INSTALLER"
