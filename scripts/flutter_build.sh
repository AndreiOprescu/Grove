#!/bin/bash
# Build the Flutter app for one platform: macos | ios | android | windows.
# `appbundle` makes the Android file for the Play Store (.aab).
# Output paths are printed by flutter at the end.
set -euo pipefail
target="${1:-}"
cd "$(dirname "$0")/../app"
flutter pub get
# The keys of the Supabase project, when the file is there (see
# app/config/supabase.example.json). With no file the app has no sync.
defines=""
if [ -f config/supabase.json ]; then
  defines="--dart-define-from-file=config/supabase.json"
fi
case "$target" in
  macos)   flutter build macos --release $defines ;;
  ios)     flutter build ios --release --no-codesign $defines ;;
  android) flutter build apk --release $defines ;;
  appbundle) flutter build appbundle --release $defines ;;
  windows) flutter build windows --release $defines ;;
  *) echo "usage: $0 macos|ios|android|appbundle|windows" >&2; exit 2 ;;
esac
