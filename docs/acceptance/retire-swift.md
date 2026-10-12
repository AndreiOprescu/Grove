# The Swift app is out of the repo, and the app id is `local.grove.app`

Branch `feat/xp-retire-swift`, from `feat/cross-platform-flutter` at `3c75315`.
Date: 2026-10-12. Flutter 3.47.7, on the owner's Mac.

On 2026-10-12 the owner said: the Swift app is retired. It goes out of the repo, and the
Flutter app gets the id `local.grove.app` now (cards Q-26 and Q-30 in `docs/questions.md`;
the plan is in `docs/acceptance/F12-release.md`, part 3).

**The Swift code is not lost.** It stays in the git history. The last commit that has it is
`3c75315`. To see a file: `git show 3c75315:Sources/Grove/GroveApp.swift`.

## What was taken out

192 files with 26 118 lines, all with `git rm`:

| What | Files |
|---|---|
| `Sources/` | 120 (the app `Grove` and the library `GroveCore`) |
| `Tests/` | 67 |
| `Package.swift` | 1 |
| `scripts/build_app.sh`, `scripts/install.sh`, `scripts/test.sh`, `scripts/make_icon.swift` | 4 |

Also: the lines `.build/` and `dist/` are out of the root `.gitignore`. Only the Swift
build made these folders.

Nothing else called the deleted files. I looked in `.github/workflows/`, `scripts/`, `app/`,
`supabase/`, `README.md`, `app/README.md` and `CLAUDE.md`. The three workflows (`flutter`,
`release`, `supabase`) never built the Swift app.

## What was kept, and why

| Kept | Why |
|---|---|
| `PLAN.md` | It is the spec of what Grove does. A note under its title says which parts are history |
| `design/layouts.html` | The visual reference |
| `scripts/make_flutter_icons.swift` | It draws the icon of the Flutter app |
| `scripts/make_tray_icons.py` | It draws the tray icons of the Flutter app |
| The `.swift` files in `app/macos/` and `app/ios/` | They are the native shell of the Flutter app, not the old app |
| Comments in `app/` that name a Swift file (`// Port of Sources/…`) | They say where a rule comes from. The file is in the git history |
| Old proof files in `docs/` | They say what was true on their day |
| The 7 screen pictures in `docs/images/` | They show the Swift app. The README says so under the first picture |

## The app id

Old: `local.grove.grove`. New: `local.grove.app`.

| File | Change |
|---|---|
| `app/macos/Runner/Configs/AppInfo.xcconfig` | line 11, the id of the Mac app |
| `app/macos/Runner.xcodeproj/project.pbxproj` | 3 lines, `local.grove.app.RunnerTests` |
| `app/ios/Runner.xcodeproj/project.pbxproj` | 6 lines: 3 for the app, 3 for `RunnerTests` |
| `app/android/app/build.gradle.kts` | `namespace` and `applicationId` |
| `app/android/app/src/main/kotlin/local/grove/app/MainActivity.kt` | moved with `git mv` from `…/local/grove/grove/`; the line `package local.grove.app` |
| `app/test/app_name_test.dart` | the test of the id, changed first |
| `README.md` | the data folder of the Mac |

Not changed, on purpose:

- Windows. The data folder stays `%APPDATA%\local.grove\Grove`. The id of the reminders
  stays `local.grove.Grove` (`app/lib/services/local_notifications_gateway.dart`).
- No manifest, entitlement, plist, script, workflow or Dart file had the id. I looked for
  `local.grove.grove`, `local/grove/grove` and `grove_grove` in the whole tree.

## New: `scripts/flutter_install.sh`

It takes the place of the old `scripts/install.sh`. For the Mac only. It goes to the repo
root, runs `./scripts/flutter_release.sh macos`, quits a running Grove, copies
`app/build/macos/Build/Products/Release/Grove.app` to `~/Applications/Grove.app` (an old
copy is replaced), makes the link `~/Desktop/Grove`, opens the app and prints one line.

**I did not run it.** It would replace the app in `~/Applications` and start Grove with
the new id. Only the syntax is checked.

## Texts

`CLAUDE.md` (the Swift lines, the branch rule, the install script), `README.md` (the part
"The first Grove" is out; the install command for the Mac; a note in "Update"; "Uninstall";
the tree), `app/README.md` (the install script), `PLAN.md` (a note under the title, nothing
else), `docs/questions.md` (one line under Q-26 and under Q-30),
`docs/acceptance/F12-release.md` (a dated note at the top of part 3), `docs/assumptions.md`
(10 lines at the end).

## Proof

Test first. I changed `app/test/app_name_test.dart`, then ran it with the old id in the
project files:

```
$ cd app && flutter test test/app_name_test.dart
00:00 +8 -2: Some tests failed.
  … the id and the data folder stay Android: the application id
  … the id and the data folder stay macOS and iOS: the bundle id
```

After the change of the id:

```
$ cd app && flutter test test/app_name_test.dart
00:00 +10: All tests passed!
```

One old check failed after the change: "no `grove.app` in the Xcode project". The new id
has these letters in it. The check is about the file name `Grove.app`, so it now takes the
id out of the text first. It is logged in `docs/assumptions.md`.

The whole check:

```
$ ./scripts/flutter_test.sh
Formatted 351 files (0 changed) in 0.73 seconds.
No issues found! (ran in 2.0s)
00:50 +2686: All tests passed!
exit 0
```

The Mac build, and the id inside the built app (the app was not opened):

```
$ ./scripts/flutter_build.sh macos
✓ Built build/macos/Build/Products/Release/Grove.app (59.3MB)
$ /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' app/build/macos/Build/Products/Release/Grove.app/Contents/Info.plist
local.grove.app
$ codesign -dv app/build/macos/Build/Products/Release/Grove.app
Identifier=local.grove.app
Signature=adhoc
```

The Android build (146 seconds), and the id in the manifest that the build made (the APK
was not put on a phone):

```
$ ./scripts/flutter_build.sh android
Running Gradle task 'assembleRelease'...                          140.2s
✓ Built build/app/outputs/flutter-apk/app-release.apk (70.6MB)
$ grep -o 'package="[^"]*"' app/build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml
package="local.grove.app"
$ grep -o 'android:name="local[^"]*MainActivity"' <the same file>
android:name="local.grove.app.MainActivity"
```

The rest:

```
$ zsh -n scripts/flutter_install.sh
(no output, exit 0)
$ git ls-files | grep -E '^(Sources|Tests)/|^Package.swift'
(no output)
$ git grep -n 'local\.grove\.grove' -- . ':!docs'
(no output)
```

## CI

See the pull request for the run of the workflow `flutter` (the 4 systems, with the device
tests).

## Not verified

- `scripts/flutter_install.sh` was never run.
- The app was never started with the new id. So I did not see the new data folder
  `~/Library/Containers/local.grove.app/`, and I did not see Export and Import work in the
  built app. The tests cover them (`app/test/data/data_export_test.dart`, with its group
  "JSON from the Mac app"), not a real file of the owner.
- iOS and Windows were not built here. CI builds them.
- A phone. With the new id, Android and iOS see a new app beside the old one.
- Two points of `docs/acceptance/F12-release.md`, part 3, are still open. The Swift app
  had the id `local.grove.app` too. (1) macOS may move its old settings file
  `~/Library/Preferences/local.grove.app.plist` into the new folder of the Flutter app.
  That file has only settings of the Swift app, no data. (2) Reminders that the Swift app
  set and that did not ring yet are under the same id. Their names are not numbers, and
  the read of the list in the Flutter app may fail on them. Not tested. If reminders do not
  work after step 3, tell the builder.

## Steps for the owner

Do them in this order.

1. If the Swift app has data you want: open it, **Settings**, **Export JSON…**. Keep the
   file. Do this first: step 3 puts the Flutter app in the place of the Swift app
   (`~/Applications/Grove.app`).
2. In the Flutter app: **Settings ▸ Data ▸ Export JSON…**. Keep the file.
3. After the merge, in the repo: `./scripts/flutter_install.sh`
4. Open Grove, **Settings ▸ Data ▸ Import JSON…**, pick the file.
5. When you are sure that all is there, delete `~/Library/Application Support/Grove/` (the
   Swift data) and `~/Library/Containers/local.grove.grove/` (the Flutter data under the
   old id).

What you must know:

- **Grove starts empty after step 3.** The new id has a new, empty data folder. Step 4
  brings the data back. Nothing is deleted before step 5.
- **Import takes one file and replaces all data with it.** If you have a file from step 1
  and a file from step 2, pick the one with the data you want to go on with. Grove cannot
  join the two.
- **Import is off while you are signed in to sync.** Import first, sign in after. If all
  your data is in your sync account, a sign-in (Settings ▸ Sync) can take the place of
  step 4. But sync is not yet proven against a real project (README), so the file of
  step 2 is the safe way.
- **The theme and a few small settings start fresh.** They are not in the export file:
  the theme, light or dark, motion, the zoom of the planner, the working hours, the daily
  limit, the length of a new block, the first day of the week, reminders on or off and
  their lead time. macOS may ask again if Grove may show reminders, and you may have to
  sign in to sync again (not tested).
- **The Swift code stays in the git history** (up to commit `3c75315`).
