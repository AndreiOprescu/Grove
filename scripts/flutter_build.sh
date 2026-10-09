#!/bin/bash
# Build the Flutter app for one platform: macos | ios | android | windows.
# Output paths are printed by flutter at the end.
set -euo pipefail
target="${1:-}"
cd "$(dirname "$0")/../app"
flutter pub get
case "$target" in
  macos)   flutter build macos --release ;;
  ios)     flutter build ios --release --no-codesign ;;
  android) flutter build apk --release ;;
  windows) flutter build windows --release ;;
  *) echo "usage: $0 macos|ios|android|windows" >&2; exit 2 ;;
esac
