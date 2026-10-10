#!/bin/bash
# Lint, format check and unit/widget tests for the Flutter app in app/.
set -euo pipefail
cd "$(dirname "$0")/../app"
flutter pub get
# lib/core and lib/data are pure Dart: no Flutter imports (docs/cross-platform-plan.md).
if grep -rn "package:flutter" lib/core lib/data; then
  echo "lib/core and lib/data must not import Flutter" >&2
  exit 1
fi
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
