#!/bin/zsh
# Build Grove and install it on this Mac: the app goes to ~/Applications and
# an icon goes on the Desktop. macOS only.
#
# The build is scripts/flutter_release.sh, so the key file of Supabase is
# used when it is there (app/config/supabase.json). The data of Grove is not
# touched. It is in ~/Library/Containers/local.grove.app/.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname)" != Darwin ]]; then
  echo "This script is for the Mac only." >&2
  exit 2
fi
BUILT="app/build/macos/Build/Products/Release/Grove.app"
APP="$HOME/Applications/Grove.app"
LINK="$HOME/Desktop/Grove"

./scripts/flutter_release.sh macos
if [[ ! -d "$BUILT" ]]; then
  echo "The build made no app at $BUILT. Nothing was installed." >&2
  exit 1
fi

# Quit a running Grove. No error when none runs. Wait up to 10 seconds for it
# to go, or `open` below would show the old one again.
osascript -e 'if application "Grove" is running then tell application "Grove" to quit' 2>/dev/null || true
for i in {1..20}; do
  pgrep -x Grove >/dev/null 2>&1 || break
  sleep 0.5
done

mkdir -p "$HOME/Applications"
rm -rf "$APP"
# ditto keeps the links and the rights of the files inside the app.
ditto "$BUILT" "$APP"
# Desktop icon: a symlink shows the app icon and opens the app on double-click.
# A real file or folder with that name is left alone.
if [[ -L "$LINK" || ! -e "$LINK" ]]; then
  ln -sfn "$APP" "$LINK"
else
  echo "There is a file or a folder '$LINK' already. No Desktop icon was made." >&2
fi
touch "$APP"     # refresh Finder icon cache
open "$APP"
echo "Installed. Double-click 'Grove' on the Desktop, or open Grove in ~/Applications."
