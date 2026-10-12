# F12 · The app icon of the Flutter app

Branch `feat/xp-logo`, from `feat/cross-platform-flutter` at `9bf9ecc`.

## What changed

The Flutter app had the default Flutter icon. Now it has the Grove logo
"Night sprout": a cream sprout on a dark green tile, with a small sun. The
owner picked it from 5 options on 2026-10-12.

| System | Files | Shape |
|---|---|---|
| macOS | `app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{16,32,64,128,256,512,1024}.png` | rounded tile, clear edge, shadow |
| iOS | the 15 `Icon-App-*.png` in `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/` | full square, no alpha |
| Android | `app/android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` | rounded tile fills the picture |
| Windows | `app/windows/runner/resources/app_icon.ico` (16, 24, 32, 48, 64, 256) | rounded tile fills the picture |

The script `scripts/make_flutter_icons.swift` draws all of them:

```
swift scripts/make_flutter_icons.swift
```

No `Contents.json`, manifest or build file changed: the file names are the same.

## Proof

- New test file `app/test/app_icons_test.dart`, 4 tests (one per system). Each
  test reads each icon file and checks: the pixel size its slot needs, a dark
  green tile, a cream stem in the middle (128 pixels and up). macOS: a clear
  corner. iOS: no alpha in the file. Windows: each size is 32 bits.
- Test first: with the old icons all 4 tests failed (the tile was not green).
  With the new icons all 4 pass.
- `./scripts/flutter_test.sh`: 2279 tests passed, analyze clean, format clean.
  The base has 2275.
- I looked at the pictures at 256, 32 and 16 pixels (macOS), 180 and 20 (iOS),
  192 and 48 (Android) and the 256 picture of the `.ico`, on a light and on a
  dark background.

## CI

See the pull request for the run of the workflow `flutter`.

## Not verified

- The icon on a real Windows machine, a real Android phone and a real iPhone.
- The small sizes of the `.ico` in the Windows task bar (only the bytes are
  tested).
- An Android phone that asks for an adaptive icon shows the picture on a white
  plate. There is no adaptive icon yet (`docs/assumptions.md`).
