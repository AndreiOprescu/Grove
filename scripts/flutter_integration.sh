#!/bin/bash
# Run the Day Planner integration test on one platform:
# macos | ios | android | windows.
# macos and windows run the desktop app. ios starts an iPhone simulator.
# android makes and starts an emulator (the SDK must be in ANDROID_HOME).
set -euo pipefail
target="${1:-}"
cd "$(dirname "$0")/../app"
test_file=integration_test/planner_test.dart
flutter pub get

case "$target" in
  macos|windows)
    flutter test "$test_file" -d "$target"
    ;;

  ios)
    # The first iPhone simulator that this Xcode can run.
    list="$(xcrun simctl list devices available)"
    udid="$(grep -m1 'iPhone' <<< "$list" | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' || true)"
    if [ -z "$udid" ]; then
      echo "no iPhone simulator found" >&2
      exit 1
    fi
    xcrun simctl boot "$udid" || true   # "already booted" is not an error
    xcrun simctl bootstatus "$udid" -b
    status=0
    flutter test "$test_file" -d "$udid" || status=$?
    xcrun simctl shutdown "$udid" || true
    exit "$status"
    ;;

  android)
    sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
    if [ -z "$sdk" ]; then
      echo "set ANDROID_HOME to the Android SDK" >&2
      exit 1
    fi
    tools="$sdk/cmdline-tools/latest/bin"
    image='system-images;android-34;default;x86_64'
    avd=grove_test
    # "yes" answers the licence questions. It stops with an error when the
    # other side closes, and that is normal.
    (yes || true) | "$tools/sdkmanager" --install "$image" emulator platform-tools > /dev/null
    echo no | "$tools/avdmanager" create avd --force -n "$avd" -k "$image" --device pixel_6
    "$sdk/emulator/emulator" -avd "$avd" -no-window -no-audio -no-boot-anim \
      -no-snapshot -gpu swiftshader_indirect > /dev/null 2>&1 &
    adb="$sdk/platform-tools/adb"
    "$adb" wait-for-device
    # Wait for the system to start. Stop after 10 minutes.
    tries=0
    until [ "$("$adb" shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = "1" ]; do
      tries=$((tries + 1))
      if [ "$tries" -gt 300 ]; then
        echo "the Android emulator did not start" >&2
        "$adb" emu kill || true
        exit 1
      fi
      sleep 2
    done
    status=0
    flutter test "$test_file" -d emulator-5554 || status=$?
    "$adb" emu kill || true
    exit "$status"
    ;;

  *)
    echo "usage: $0 macos|ios|android|windows" >&2
    exit 2
    ;;
esac
