#!/bin/zsh
# Puts whisper.cpp's xcframework in Vendor/ (git-ignored), checked by SHA-256.
# build.sh runs this when it is missing. Change the release here and in
# nothing else: Package.swift points at Vendor/whisper.xcframework.
set -euo pipefail
here=${0:A:h:h}
release=b5454
sum=e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b
target="$here/Vendor/whisper.xcframework"
[[ -d "$target" && -f "$here/Vendor/whisper-$release" ]] && exit 0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
url="https://github.com/ggml-org/whisper.cpp/releases/download/$release/whisper-$release-xcframework.zip"
echo "fetching whisper.cpp $release"
curl -fL --retry 3 --connect-timeout 20 -o "$tmp/w.zip" "$url"
got=$(shasum -a 256 "$tmp/w.zip" | awk '{print $1}')
[[ "$got" == "$sum" ]] || { echo "whisper.cpp checksum mismatch: $got"; exit 1; }
unzip -q "$tmp/w.zip" -d "$tmp"
rm -rf "$here/Vendor/whisper.xcframework" "$here"/Vendor/whisper-*(N)
mkdir -p "$here/Vendor"
mv "$tmp/build-apple/whisper.xcframework" "$target"
touch "$here/Vendor/whisper-$release"
