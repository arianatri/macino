#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
cache="$root/.build/android-tools"
prefix="$cache/prefix"
destination="$root/build/macino.app/Contents/Resources/Android"
mkdir -p "$cache" "$destination/Licenses" "$destination/Sources"
fetch() {
    local url="$1" path="$cache/$2" hash="$3"
    if [ ! -f "$path" ]; then curl -fL --retry 2 "$url" -o "$path"; fi
    echo "$hash  $path" | shasum -a 256 -c -
}
fetch https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2 libusb.tar.bz2 fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf
fetch https://codeload.github.com/libmtp/libmtp/tar.gz/refs/tags/v1.1.23 libmtp.tar.gz 93ba3f860805f793ffaec3886ed5a2c1ea0a2e0407974c1d1b732d4d38ce34bc
fetch https://github.com/Genymobile/scrcpy/releases/download/v5.0.1/scrcpy-macos-aarch64-v5.0.1.tar.gz scrcpy.tar.gz 33611e51977a8289e2e124b220f727895181ef2eb9060e0987a4dc2db9cf0d6b
export PATH="/opt/homebrew/bin:/opt/homebrew/opt/libtool/libexec/gnubin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=14.0
export CFLAGS="-O2 -arch arm64 -mmacosx-version-min=14.0"
export LDFLAGS="-arch arm64 -mmacosx-version-min=14.0"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
if [ ! -f "$prefix/lib/libmtp.9.dylib" ]; then
    for tool in autoreconf automake pkg-config; do command -v "$tool" >/dev/null || { echo 'Build prerequisites: brew install autoconf automake libtool pkgconf'; exit 1; }; done
    tar -xjf "$cache/libusb.tar.bz2" -C "$cache"
    (cd "$cache/libusb-1.0.30"; ./configure --prefix="$prefix" --disable-static; make -j4; make install)
    tar -xzf "$cache/libmtp.tar.gz" -C "$cache"
    (cd "$cache/libmtp-1.1.23"; autoreconf -fi; ./configure --prefix="$prefix" --disable-static --disable-mtpz; make -j4; make install)
fi
cp "$prefix/lib/libmtp.9.dylib" "$destination/"
cp "$prefix/lib/libusb-1.0.0.dylib" "$destination/"
clang -fobjc-arc -arch arm64 -mmacosx-version-min=14.0 -framework Foundation \
    -I"$prefix/include" -L"$prefix/lib" -lmtp Sources/AndroidMTP/main.m -o "$destination/macino-mtp"
install_name_tool -change "$prefix/lib/libmtp.9.dylib" '@loader_path/libmtp.9.dylib' "$destination/macino-mtp"
install_name_tool -id '@loader_path/libmtp.9.dylib' "$destination/libmtp.9.dylib"
install_name_tool -change "$prefix/lib/libusb-1.0.0.dylib" '@loader_path/libusb-1.0.0.dylib' "$destination/libmtp.9.dylib"
install_name_tool -id '@loader_path/libusb-1.0.0.dylib' "$destination/libusb-1.0.0.dylib"
tar -xzf "$cache/scrcpy.tar.gz" -C "$cache"
for name in scrcpy adb scrcpy-server; do cp "$cache/scrcpy-macos-aarch64-v5.0.1/$name" "$destination/"; done
cp "$cache/scrcpy-macos-aarch64-v5.0.1/LICENSE" "$destination/Licenses/scrcpy-APACHE-2.0.txt"
cp "$cache/libmtp-1.1.23/COPYING" "$destination/Licenses/libmtp-LGPL.txt"
cp "$cache/libusb-1.0.30/COPYING" "$destination/Licenses/libusb-LGPL.txt"
cp "$cache/libusb.tar.bz2" "$cache/libmtp.tar.gz" "$destination/Sources/"
cp Resources/Android-NOTICES.txt "$destination/Licenses/NOTICES.txt"
for binary in libusb-1.0.0.dylib libmtp.9.dylib macino-mtp adb scrcpy; do
    codesign --force --sign - "$destination/$binary"
done
