#!/bin/zsh
# Packs ~/Applications/Showreel.app (from build.sh) into a disk image with an
# Applications shortcut, so people drag the app across to install it.
#   tools/make-dmg.sh [output.dmg]     default: ./Showreel.dmg
set -euo pipefail
name="Showreel"
app="$HOME/Applications/$name.app"
out="${1:-$PWD/$name.dmg}"
[[ -d "$app" ]] || { echo "no $app: run ./build.sh first"; exit 1; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/$name.app"
ln -s /Applications "$stage/Applications"
rm -f "$out"
hdiutil create -volname "$name" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$out" >/dev/null
echo "wrote $out"
