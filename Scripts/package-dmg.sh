#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/build.sh release
if [ ! -x .build/packaging-venv/bin/dmgbuild ]; then
    python3 -m venv .build/packaging-venv
    .build/packaging-venv/bin/pip install 'dmgbuild==1.6.5' 'ds_store==1.3.1' 'mac_alias==2.2.2'
fi
swift Scripts/make-install-assets.swift "$PWD/Resources/Installer"
python3 Scripts/verify-compatibility.py
python3 Scripts/verify-android-tools.py
python3 Scripts/verify-reader-tools.py
.build/packaging-venv/bin/dmgbuild -s Scripts/dmg-settings.py 'macino' build/macino.dmg
hdiutil verify build/macino.dmg
verify_mount="$PWD/.build/dmg-verify"
mkdir -p "$verify_mount"
hdiutil attach -nobrowse -readonly -mountpoint "$verify_mount" build/macino.dmg >/dev/null
verify_copy="$(mktemp -d "$PWD/.build/install-check.XXXXXX")"
trap 'hdiutil detach "$verify_mount" >/dev/null; rm -rf "$verify_copy"' EXIT
codesign --verify --deep --strict "$verify_mount/macino.app"
python3 Scripts/verify-android-tools.py "$verify_mount/macino.app"
python3 Scripts/verify-reader-tools.py "$verify_mount/macino.app"
[ "$(readlink "$verify_mount/Applications")" = "/Applications" ]
[ ! -e "$verify_mount/Install with love.app" ]
ditto "$verify_mount/macino.app" "$verify_copy/macino.app"
codesign --verify --deep --strict "$verify_copy/macino.app"
swift Scripts/verify-installed-launch.swift "$verify_copy/macino.app"
"$verify_copy/macino.app/Contents/MacOS/macino" --reader-playback-test
hdiutil detach "$verify_mount" >/dev/null
rm -rf "$verify_copy"
trap - EXIT
echo "DMG ready: $PWD/build/macino.dmg"
