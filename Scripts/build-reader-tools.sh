#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cache="$PWD/.build/tts-tools"
models="${MACINO_TTS_MODEL_CACHE:-/Users/arian/dev/llm/macino-tts}"
dest="$PWD/build/macino.app/Contents/Resources/Reader"
mkdir -p "$cache" "$models" "$dest/Licenses" "$dest/fa" "$dest/en"
fetch() {
    local url="$1" file="$2" hash="$3"
    if [ ! -f "$file" ]; then curl -fL --retry 2 "$url" -o "$file"; fi
    echo "$hash  $file" | shasum -a256 -c -
}
fetch https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-arm64-shared-lib.tar.bz2 "$cache/runtime.tar.bz2" ae77050cdae565496059d96f5ab33d77b397a0864282a4e4a26e3b3b3effb948
fetch https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v1.13.8/sherpa-onnx/c-api/c-api.h "$cache/c-api.h" 2a1b95084be8fd1deb3228fcad2fd3f7f0258b64582f7402281ec174c7b7f4ce
fetch https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fa_IR-amir-medium.tar.bz2 "$models/fa.tar.bz2" 46af65c1cdd86ec300db3998f2bf31a68d9e38da930c0655c1ff6f610e84f864
fetch https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-ljspeech-medium.tar.bz2 "$models/en.tar.bz2" 3dfb4b759d8be032a4903a9538d128b0fda2a06ab1de6cbc2d93a97e2dd83dba
runtime="$cache/sherpa-onnx-v1.13.8-osx-arm64-shared-lib"
[ -d "$runtime" ] || tar -xjf "$cache/runtime.tar.bz2" -C "$cache"
for spec in 'fa fa_IR-amir' 'en en_US-ljspeech'; do
    read -r lang name <<< "$spec"
    source="$models/vits-piper-$name-medium"
    [ -d "$source" ] || tar -xjf "$models/$lang.tar.bz2" -C "$models"
    cp "$source/$name-medium.onnx" "$dest/$lang/model.onnx"
    cp "$source/tokens.txt" "$dest/$lang/tokens.txt"
    cp "$source/MODEL_CARD" "$dest/Licenses/$lang-MODEL_CARD.txt"
done
if [ ! -d "$dest/espeak-ng-data" ]; then ditto "$models/vits-piper-fa_IR-amir-medium/espeak-ng-data" "$dest/espeak-ng-data"; fi
cp "$runtime/lib/libsherpa-onnx-c-api.dylib" "$runtime/lib/libonnxruntime.dylib" "$dest/"
clang -O2 -arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -framework Foundation -I"$cache" -L"$dest" -lsherpa-onnx-c-api Sources/ReaderSpeech/main.m -o "$dest/macino-speech"
install_name_tool -change '@rpath/libsherpa-onnx-c-api.dylib' '@loader_path/libsherpa-onnx-c-api.dylib' "$dest/macino-speech"
install_name_tool -change '@rpath/libonnxruntime.dylib' '@loader_path/libonnxruntime.dylib' "$dest/libsherpa-onnx-c-api.dylib"
install_name_tool -id '@loader_path/libsherpa-onnx-c-api.dylib' "$dest/libsherpa-onnx-c-api.dylib"
install_name_tool -id '@loader_path/libonnxruntime.dylib' "$dest/libonnxruntime.dylib"
if [ -f Sources/ReaderImport/main.swift ]; then
    swiftc -O -target arm64-apple-macosx14.0 -framework AppKit -framework PDFKit Sources/ReaderImport/main.swift -o "$dest/macino-reader-import"
fi
for spec in 'sherpa-onnx https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v1.13.8/LICENSE' 'onnxruntime https://raw.githubusercontent.com/microsoft/onnxruntime/v1.24.3/LICENSE' 'espeak-ng https://raw.githubusercontent.com/espeak-ng/espeak-ng/1.52.0/COPYING'; do
    read -r name url <<< "$spec"
    [ -f "$cache/$name-LICENSE.txt" ] || curl -fsSL "$url" -o "$cache/$name-LICENSE.txt"
    cp "$cache/$name-LICENSE.txt" "$dest/Licenses/"
done
cp Resources/Reader-NOTICES.txt "$dest/Licenses/NOTICES.txt"
mkdir -p "$dest/Sources"
cp Sources/ReaderSpeech/main.m "$dest/Sources/macino-speech.m"
cp "$cache/c-api.h" "$dest/Sources/c-api.h"
cp Scripts/build-reader-tools.sh "$dest/Sources/build-reader-tools.sh"
for file in libsherpa-onnx-c-api.dylib libonnxruntime.dylib macino-speech macino-reader-import; do
    [ ! -f "$dest/$file" ] || codesign --force --sign - "$dest/$file"
done
