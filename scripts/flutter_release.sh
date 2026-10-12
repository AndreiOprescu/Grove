#!/bin/bash
# Make the release build of Grove for one platform, and put the files to
# hand out in app/build/dist/: macos | windows | android | ios.
#
#   macos    grove-macos.zip          the app, zipped
#   windows  grove-windows/           the folder with grove.exe
#   android  grove-android.apk        to install on a phone
#            grove-android.aab        the file for the Play Store
#   ios      grove-ios-unsigned.zip   Runner.app, zipped; needs signing
#
# Nothing is signed with a key of the owner. What that means on each system
# is in docs/acceptance/F12-release.md. The build itself is
# scripts/flutter_build.sh, so the key file of Supabase is used when it is
# there (app/config/supabase.json). With no file the app has no sync.
set -euo pipefail
target="${1:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"
case "$target" in
  macos|windows|android|ios) ;;
  *) echo "usage: $0 macos|windows|android|ios" >&2; exit 2 ;;
esac

"$root/scripts/flutter_build.sh" "$target"
if [ "$target" = android ]; then
  "$root/scripts/flutter_build.sh" appbundle
fi

cd "$root/app"
dist=build/dist
mkdir -p "$dist"
made=()
case "$target" in
  macos)
    # ditto keeps the links and the rights of the files inside the app.
    rm -f "$dist/grove-macos.zip"
    ditto -c -k --keepParent build/macos/Build/Products/Release/Grove.app \
      "$dist/grove-macos.zip"
    made=("$dist/grove-macos.zip")
    ;;
  windows)
    rm -rf "$dist/grove-windows"
    cp -R build/windows/x64/runner/Release "$dist/grove-windows"
    made=("$dist/grove-windows")
    ;;
  android)
    cp build/app/outputs/flutter-apk/app-release.apk "$dist/grove-android.apk"
    cp build/app/outputs/bundle/release/app-release.aab "$dist/grove-android.aab"
    made=("$dist/grove-android.apk" "$dist/grove-android.aab")
    ;;
  ios)
    rm -f "$dist/grove-ios-unsigned.zip"
    ditto -c -k --keepParent build/ios/iphoneos/Runner.app \
      "$dist/grove-ios-unsigned.zip"
    made=("$dist/grove-ios-unsigned.zip")
    ;;
esac

echo
echo "Release files for $target, in app/$dist:"
du -sh "${made[@]}"
