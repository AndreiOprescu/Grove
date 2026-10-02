#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build_app.sh
osascript -e 'tell application "Grove" to quit' 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Grove.app"
cp -R dist/Grove.app "$HOME/Applications/Grove.app"
# Desktop icon: a symlink shows the app icon and opens the app on double-click.
ln -sfn "$HOME/Applications/Grove.app" "$HOME/Desktop/Grove"
touch "$HOME/Applications/Grove.app"     # refresh Finder icon cache
open "$HOME/Applications/Grove.app"
echo "Installed. Double-click 'Grove' on the Desktop."
