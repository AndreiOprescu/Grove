# F12 · The gaps of the shell — proof

Plan: `docs/cross-platform-plan.md` (milestone F12, parity with the Mac app). Branch `feat/xp-shell-gaps`, draft PR #18 into `feat/cross-platform-flutter`. Date: 2026-10-11.

The Swift app is the model: `Sources/Grove/GroveApp.swift`, `Sources/Grove/Layouts/RootView.swift`, `Sources/Grove/Shared/CommandPalette.swift`, `Sources/Grove/Settings/SettingsView.swift`, and `PLAN.md` §5.8.

Check: `./scripts/flutter_test.sh` (2026-10-11, after the merge of `origin/feat/cross-platform-flutter` at `b7a20b9`: 2196 tests passed, analyze clean, format clean). 98 of them are new with this branch. The base has 2098.
CI: see "CI" below.

No new package. No new entitlement. The app id did not change (`local.grove.grove`). No engine folder was edited.

## The 7 parts

| # | Part | Was the gap real? | Built? | Verified? |
|---|---|---|---|---|
| 1 | Command palette | Yes | Yes | Tests and pictures. Not tried by hand. |
| 2 | Keys and menus | Yes | Yes | Tests. The Mac menu bar was not looked at by eye. |
| 3 | Errors of the store | Yes | Yes | Tests and pictures. |
| 4 | Window size and title bar | Yes | Yes | Mac: device test on this Mac. Windows: device test on the CI. Not tried with a real mouse. |
| 5 | The shown name "Grove" | Yes | Yes, but one text on Windows stays (Q-40) | Tests, a clean Mac build, CI builds. |
| 6 | Idle CPU | Yes | In part: the background and the plants | Measured, numbers below. The planner and Today are still high. |
| 7 | "Show data folder" | Yes | Yes, Mac and Windows | Mac: one device check. Windows: not verified. |

## 1 · Command palette

The gap: before this branch the Flutter app had no palette window, no "Search" button and no key for it. The store had the search (`paletteOpen`, `PaletteSearch`) with no screen.

Built:

- `app/lib/ui/shell/command_palette.dart`: the window (`PaletteHost`, `CommandPalette`), as `CommandPalette.swift`: a text field; it finds tasks, events and notes, runs commands and jumps to a day; up and down choose a row, Return runs it, Esc or a click next to the box closes it; a `>` first keeps only the commands.
- `app/lib/ui/shell/top_buttons.dart`: the "Search" pill with the name of the key (`⌘K` on a Mac, `Ctrl K` on the others), and the gear.
- Cmd+K (Ctrl+K on Windows and Android) opens and closes it (`app/lib/ui/app.dart`, `ShellKeys`).
- A phone gets the search picture with no word, and a box as wide as the screen allows.

Tests: `app/test/ui/shell/command_palette_test.dart` (26 tests), 8 pictures `palette_*.png` in `app/test/ui/goldens/` (`f12_shell_golden_test.dart`). The top strip changed, so 64 older pictures with the whole window were made again and looked at. After the merge of the base on 2026-10-12, 2 more pictures were made again for the same cause and looked at: `planner_subtasks_grove_light.png` and `planner_focus_done_grove_light.png` in `app/test/ui/planner/goldens/`; only the top strip is different.

Not verified: the palette with a real keyboard on Windows, Android and iOS.

## 2 · Keys and menus

The gap: the window had only the keys T, 1 to 5 and comma. No menu bar on the Mac, no gear.

Built (`app/lib/ui/shell/app_menus.dart`, `app/lib/ui/app.dart`):

- One list `shellMenus` makes both the Mac menu bar (`PlatformMenuBar`) and the keys of the other systems (`Shortcuts` and `Actions` of Flutter).
- Keys: Cmd+N new task, Opt+Cmd+N new event, Shift+Cmd+N new note, Cmd+comma Settings, Cmd+K palette, Cmd+Z and Shift+Cmd+Z undo and redo, Cmd+1 to 5 the screens, T today. Ctrl in place of Cmd on Windows and Android.
- Menus on the Mac: Grove (the system's), File, Edit, View, Go, Window.
- The gear at the top right opens Settings. A phone has "Settings…" in the Appearance menu.

Decisions (lines in `docs/assumptions.md`): Edit has only Undo and Redo; no Help menu; the keys do nothing while a window (Settings, the palette, an error) is open; Undo in a text field goes to the store, as in the Swift app.

Tests: `app/test/ui/shell/app_menus_test.dart` (19 tests), 2 new tests in `app/test/ui/shell/root_view_test.dart`.

Not verified: the Mac menu bar by eye (the tests read the list that Flutter gives to the system, not the bar on the screen). The keys on a real Windows keyboard.

## 3 · Errors of the store

The gap: `store.errorMessage` was shown nowhere. A failed save was silent.

Built: `app/lib/ui/shell/error_alert.dart` (`ErrorGate`, `showErrorAlert`). A small window with the title "Grove", the text of the store and "OK", as the `.alert("Grove", …)` of `RootView.swift`. "OK" clears the message. A second error while the window is open gets its own window after the first.

Tests: `app/test/ui/shell/error_alert_test.dart` (10 tests), 3 pictures `error_*.png`.

## 4 · Window

The gap: the Mac window opened 800 × 600 with a title bar (`MainMenu.xib`). The Windows window opened 1280 × 720 at the point 10, 10 and had no smallest size.

Built:

- Mac (`app/macos/Runner/MainFlutterWindow.swift`): opens 1280 × 800 in the middle of the screen, never under 1100 × 620, hidden title bar, the screens reach the top edge. An empty part of the top strip moves the window (`app/lib/ui/shell/window_drag.dart`, channel `grove/window`, method `drag`).
- Windows (`app/windows/runner/win32_window.cpp`, `main.cpp`): opens with a client area of 1280 × 800 in the middle of the work area, and the person cannot make it smaller than 1100 × 620 (`WM_GETMINMAXINFO`). On a screen that is smaller than these sizes the window fills the free part of the screen. It keeps its title bar.
- `scripts/flutter_integration.sh macos|windows` also runs `app/integration_test/window_test.dart`.

Decisions: `PLAN.md` says the smallest size is 960 × 620, the Swift code says 1100 × 620; the code wins. The Mac window does not remember its size and place (`isRestorable = false`): without it the system put back an old frame and the window was off the screen.

Tests: `app/test/ui/shell/window_drag_test.dart` (7 tests). The device test on this Mac printed: `GROVE_WINDOW system=macOS window=1280.0x800.0 screen=1512.0x982.0 paddingTop=0.0 dock=84.0,5.0`. `./scripts/flutter_integration.sh macos` passed (9 planner tests and 1 window test). The lines of the CI runs are under "CI".

Not verified, please try by hand on the Mac: move the window by the top strip with the mouse; click the buttons of the strip; make the window as small as it goes; full screen. On Windows: open the app on a normal screen and check the first size and the smallest size. I could not compile or run the Windows code on this Mac; the CI compiles it and runs it on a small screen only.

## 5 · The shown name

The gap: the Mac build was `grove.app`, and the name in the menu bar, under the Android icon and in the Windows title was "grove".

Built: "Grove" in `app/macos/Runner/Configs/AppInfo.xcconfig` (`PRODUCT_NAME`), the Xcode project and scheme, `app/ios/Runner/Info.plist` (`CFBundleName`), `app/android/app/src/main/AndroidManifest.xml` (`android:label`), the Windows window title (`main.cpp`) and "File description" (`Runner.rc`).

Not changed, by rule: the bundle id, the Android `applicationId` and `namespace`. Not changed, and asked in **Q-40**: the Windows "Product name" (`grove`). With the "Company name" it makes the data folder `%APPDATA%\local.grove\grove`; a change would start the app with an empty folder. `grove.exe` keeps its name.

Tests: `app/test/app_name_test.dart` (9 tests: 6 for the name, 3 for the ids and the folder). Before the change 5 failed. A clean build with `./scripts/flutter_build.sh macos` gave `build/macos/Build/Products/Release/Grove.app` with `CFBundleName` Grove, `CFBundleExecutable` Grove, `CFBundleIdentifier` local.grove.grove.

The scripts: `scripts/flutter_build.sh`, `scripts/flutter_integration.sh`, `scripts/flutter_idle.sh` and `.github/workflows/flutter.yml` do not name the app file; they still work (CI below). `scripts/flutter_release.sh` on the branch `feat/xp-release` (PR #14) names `grove.app`: a request is in `docs/tracks.md`.

Know this: the Swift app is also `Grove.app` (id `local.grove.app`). The Flutter build has the same file name and another id. `./scripts/install.sh` was not run.

Not verified: the name under the icon on a real phone.

## 6 · Idle CPU

The gap: the app with nothing to do used 29 to 47 % of one core and drew 120 frames a second.

How it is measured: `./scripts/flutter_idle.sh` makes a profile build of `app/tool/idle_check.dart` (the real screens, its own empty data folder), opens it, and reads the processor time of the app with `ps` at second 5 and at second 25. The number is the share of one core. This Mac, 2026-10-11. The owner used the Mac at the same time, so a number moves by about 10 points between runs.

| Screen | Before (`667286c`) | After, old window (`dd3157c`) | After, window 1280 × 800 |
|---|---|---|---|
| Garden | 29 %, 120 frames a second | 10 %, 30 | 23 %, 30 |
| Notes | 40 %, 120 | 7 %, 16 | 11 %, 16 |
| Planner | 43 %, 120 | 55 %, 120 | 43 %, 120 |
| Today | 47 %, 120 | 49 %, 120 | 50 %, 120 |
| Planner, Motion off | 0 % | 0 % | 0 % |

What was built: the background and the plants ask for a frame only when they step (`app/lib/ui/theme/slow_clock.dart`, 10 tests in `app/test/ui/theme/slow_clock_test.dart`). Before, a `Ticker` asked for a frame at each refresh of the screen.

What is not done: the planner and Today are as high as before. The cause is the `Ticker` of the now line in `app/lib/ui/planner/planner_grid.dart`. That folder belongs to the planner helper; the request, with the change ready to copy, is in `docs/tracks.md`. "Near nothing" is reached only with Motion off.

## 7 · "Show data folder"

The gap: Settings → Data showed the path and "Copy the path" only. The Swift app has `Button("Show data folder")`.

Built: the button "Show data folder" on a Mac and on Windows (`app/lib/ui/settings/settings_tabs.dart`, `SettingsFiles.canShowFolder` and `showFolder` in `settings_view.dart`, the real call in `app/lib/ui/system/system_tools.dart`: `launchUrl(Uri.directory(path))` of `url_launcher`). "Copy the path" stays. When the system does not open the folder the window says so.

Tests: 4 new tests in the group "Data" of `app/test/ui/settings/settings_view_test.dart`. One device check on this Mac, in the sandbox of the debug build, with a file that is not kept: `GROVE_FOLDER can=true shown=true missing=false dir=/Users/andrei/Library/Containers/local.grove.grove/Data/tmp/grove-show-folder…` (a folder of the app opens, a folder that is not there gives false).

Not verified: Explorer on Windows (I read the code of `url_launcher_windows`: it gives a `file:` address to `ShellExecuteW`). The button in the release build of the Mac app with the real data folder.

## CI

Workflow `flutter`, 4 jobs. Each job runs `./scripts/flutter_test.sh`, `./scripts/flutter_build.sh <system>` and `./scripts/flutter_integration.sh <system>`.

The last code commit is `6baeeb2`. Run 38164051282 (push), 2026-10-11: **success**.

| Job | Result | What it shows |
|---|---|---|
| android (Linux) | success | 2196 tests, the build, the device test of the planner |
| windows | success | 2195 tests and 1 skipped (a picture parked before this branch), `grove.exe` built with the new window code, 9 planner tests, the window test: `GROVE_WINDOW system=windows window=1008.0x681.0 screen=1024.0x768.0 paddingTop=0.0 dock=16.0,5.0` |
| macos | success | 2196 tests, `Release/Grove.app` built (59.2MB), 9 planner tests, the window test: `GROVE_WINDOW system=macOS window=1100.0x674.0 screen=1024.0x768.0 paddingTop=0.0 dock=84.0,5.0` |
| ios | success | 2196 tests, the build, the device test of the planner |

Earlier runs of this branch: 38157187332 (`1c2f7c5`), 38157382838 (`f5a88fe`) and 38157913112 (`dd3157c`) were green. Run 38162697134 (`3c20f16`) and run 38163112481 (`2ac26a7`) were red in the windows job only: the window test asked for 1100 points of width on a screen of 1024 × 768, and Windows does not make a window bigger than the screen (it gave 1028 × 681). One fix round: `6baeeb2` (the window fills the free part of such a screen; the test allows it).

The screen of the CI machines is 1024 × 768. So the CI proves the smallest size on the Mac and the small-screen case on Windows. The first size 1280 × 800 is proved on this Mac only. On Windows the first size and the smallest size on a big screen are **not verified**.

## Questions and requests

- **Q-40** (`docs/questions.md`, open, has a default): the Windows "Product name" stays "grove" or becomes "Grove".
- `docs/tracks.md`: the now line of the planner (idle CPU); `Grove.app` in `scripts/flutter_release.sh`; the pictures of Track A that were made again.
- `docs/assumptions.md`: 19 lines that start with "2026-10-11 · Cross-platform port F12 shell gaps".
