#!/bin/bash
# Lint, format check and unit/widget tests for the Flutter app in app/.
set -euo pipefail
cd "$(dirname "$0")/../app"
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
