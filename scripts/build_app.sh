#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME="Grove"; BUNDLE_ID="local.grove.app"; VERSION="1.0.0"
BUILD=build; APP="dist/$APP_NAME.app"
mkdir -p "$BUILD" dist
swift build -c release --product Grove
BIN="$(swift build -c release --show-bin-path)/Grove"

# Icon
swift scripts/make_icon.swift "$BUILD"
ICONSET="$BUILD/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"

# Bundle
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
    <key>CFBundleURLSchemes</key><array><string>grove</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
