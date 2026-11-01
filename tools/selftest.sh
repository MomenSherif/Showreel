#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
# A second copy of Showreel opens no windows while another copy runs, so
# the run would wait forever. Quit the running copy first (docs/FIXLOG.md).
if pgrep -f "Showreel.app/Contents/MacOS/Showreel" >/dev/null; then
  echo "Quitting the running Showreel first"
  osascript -e 'quit app "Showreel"' >/dev/null 2>&1
  sleep 1
  pkill -f "Showreel.app/Contents/MacOS/Showreel" 2>/dev/null
fi
rm -rf ~/Library/Saved\ Application\ State/com.momensherif.showreel.savedState
store=/tmp/Showreel-self.store
rm -f $store $store-shm $store-wal
APP_STORE=$store ~/Applications/Showreel.app/Contents/MacOS/Showreel --selftest -ApplePersistenceIgnoreState YES
