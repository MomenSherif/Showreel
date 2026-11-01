#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
set -u
# A second copy of Showreel opens no windows while another copy runs, so
# the run would wait forever. Quit the running copy first (docs/FIXLOG.md).
if pgrep -f "Showreel.app/Contents/MacOS/Showreel" >/dev/null; then
  echo "Quitting the running Showreel first"
  osascript -e 'quit app "Showreel"' >/dev/null 2>&1
  sleep 1
  pkill -f "Showreel.app/Contents/MacOS/Showreel" 2>/dev/null
fi
app=~/Applications/Showreel.app/Contents/MacOS/Showreel
store=/tmp/Showreel-test.store
shots=/tmp/Showreel-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.momensherif.showreel.savedState
# Seed data only fills an empty store, so start from nothing.
rm -f $store $store-shm $store-wal
rm -rf $shots
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app -ApplePersistenceIgnoreState YES
