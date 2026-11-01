#!/bin/zsh
# Builds Showreel and installs it to ~/Applications/Showreel.app.
# Build products live in ~/Library/Developer/Showreel, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh            release build, install
#        ./build.sh --debug    debug build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
set -euo pipefail
here=${0:A:h}
name="Showreel"
scratch="$HOME/Library/Developer/$name/build"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# Sign with your Apple Development certificate when you have one (Xcode >
# Settings > Accounts). Otherwise sign ad hoc, which is fine for your own Mac.
#
# Use the certificate's SHA-1 hash, not its name: two certificates with the
# same name make codesign fail with "ambiguous". Skip revoked certificates:
# `find-identity -v` still lists them, and the kernel kills an app signed with
# one (exit 137). The working hash is cached, because permissions like Screen
# Recording belong to the signature: changing it makes macOS ask again.
identity="${SIGN_IDENTITY:-}"
cache="$HOME/Library/Developer/$name/sign-identity"
if [[ -z "$identity" && -f "$cache" ]]; then
  identity=$(<"$cache")
  security find-identity -v -p codesigning 2>/dev/null | grep -q "$identity" || identity=""
fi
if [[ -z "$identity" ]]; then
  probe=$(mktemp -d)/probe
  cp /usr/bin/true "$probe"
  for candidate in $(security find-identity -v -p codesigning 2>/dev/null | grep '"Apple Development: ' | awk '{print $2}'); do
    codesign --force --sign "$candidate" "$probe" 2>/dev/null || continue
    # Capture first: spctl exits non-zero for any unnotarized build, and with
    # pipefail that would hide grep's answer.
    verdict=$(spctl -a -vv -t exec "$probe" 2>&1 || true)
    if [[ "$verdict" != *REVOKED* ]]; then
      identity=$candidate
      mkdir -p "${cache:h}" && print -r -- "$identity" > "$cache"
      break
    fi
  done
  rm -rf "${probe:h}"
fi
[[ -n "$identity" ]] || identity=-

swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  # A comment-only edit compiles to the same objects, so nothing relinks and
  # the binary stays older. Only real errors fail the build.
  errors=$(swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error:" | head -20)
  if [[ -n "$errors" ]]; then
    echo "build failed: binary is older than $stale"
    echo "$errors"
    exit 1
  fi
  touch "$bin"
fi

app="$HOME/Applications/$name.app"
mkdir -p "$HOME/Applications"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  car="$here/Resources/Assets.car"
  if [[ ! -f "$car" || -n "$(find "$here/Icon/AppIcon.icon" -newer "$car" | head -1)" ]]; then
    "$here/tools/make_icon.sh"
  fi
  cp -X "$car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
fi
xattr -cr "$app"
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "installed $app (signed: ${identity})"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$app"
fi
