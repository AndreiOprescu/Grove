# F12 · The gaps of the shell — proof

Plan: `docs/cross-platform-plan.md` (milestone F12, parity with the Mac app). Branch `feat/xp-shell-gaps`, draft PR #18 into `feat/cross-platform-flutter`. Dates: 2026-10-11 and 2026-10-12.

The Swift app is the model: `Sources/Grove/GroveApp.swift`, `Sources/Grove/Layouts/RootView.swift`, `Sources/Grove/Shared/CommandPalette.swift`, `Sources/Grove/Settings/SettingsView.swift`, and `PLAN.md` §5.8.

Check: `./scripts/flutter_test.sh` (2026-10-12, after the merge of `origin/feat/cross-platform-flutter` at `ec73831`: 2393 tests passed, analyze clean, format clean). 118 of them are new with this branch: 98 from 2026-10-11 and 20 from 2026-10-12 (1 for the scripts, 13 for the focus timer, 6 for the zoom keys). The base has 2275.
CI: see "CI" below.

No new package. No new entitlement. The app id did not change (`local.grove.grove`). No engine folder was edited.

## The parts

Parts 1 to 7 are from 2026-10-11. Parts 8 to 10 and the change in part 5 are from 2026-10-12.

| # | Part | Was the gap real? | Built? | Verified? |
|---|---|---|---|---|
| 1 | Command palette | Yes | Yes | Tests and pictures. Not tried by hand. |
| 2 | Keys and menus | Yes | Yes | Tests. The Mac menu bar was not looked at by eye. |
| 3 | Errors of the store | Yes | Yes | Tests and pictures. |
| 4 | Window size and title bar | Yes | Yes | Mac: device test on this Mac. Windows: device test on the CI. Not tried with a real mouse. |
| 5 | The shown name "Grove" | Yes | Yes. The Windows "Product name" too, since 2026-10-12 (Q-40: B) | Tests, a clean Mac build, CI builds. Not on a real Windows machine. |
| 6 | Idle CPU | Yes | In part: the background and the plants | Measured, numbers below. The planner and Today are still high. |
| 7 | "Show data folder" | Yes | Yes, Mac and Windows | Mac: one device check. Windows: not verified. |
| 8 | `Grove.app` in the release build and the speed check | Yes | Yes | A test, and both scripts run on this Mac. The speed numbers are not a clean measure. |
| 9 | The focus timer on each screen | Yes | Yes | Tests. Not tried by hand. |
| 10 | "Zoom In" and "Zoom Out" for the whole window | Mostly no: the two lines were there. The keys `+` and the number pad were missing | The missing keys | Tests. Not tried on a real keyboard. |

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

Tests: `app/test/ui/shell/app_menus_test.dart` (19 tests then; 25 with part 10), 2 new tests in `app/test/ui/shell/root_view_test.dart`.

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

**Changed on 2026-10-12, Q-40 answered B:** the Windows "Product name" is "Grove" (`app/windows/runner/Runner.rc`, the line `VALUE "ProductName"`). Only that text changed. The "Company name" (`local.grove`), the "Internal name" (`grove`), the file name `grove.exe`, `BINARY_NAME` and the app id are the old ones. The data folder is now `%APPDATA%\local.grove\Grove`. On a normal Windows disk that is the same folder as `%APPDATA%\local.grove\grove`, because big and small letters are equal there. On a disk set to tell them apart the app starts with a new empty folder; the old one stays where it is. The test 'Windows: the two names of the data folder, and the file name' in `app/test/app_name_test.dart` failed first (expected "Grove", got "grove"), then passed. The scripts and the workflows find the build as before: none of them reads the "Product name"; `scripts/flutter_release.sh` copies `build/windows/x64/runner/Release`, and `.github/workflows/flutter.yml` names `app/build/windows/x64/runner/Release/`. **Not verified: on a real Windows machine** (the "Details" tab of `grove.exe`, and that the app finds its old data folder).

Tests: `app/test/app_name_test.dart` (9 tests then: 6 for the name, 3 for the ids and the folder; 10 with part 8). Before the change 5 failed. A clean build with `./scripts/flutter_build.sh macos` gave `build/macos/Build/Products/Release/Grove.app` with `CFBundleName` Grove, `CFBundleExecutable` Grove, `CFBundleIdentifier` local.grove.grove.

The scripts: `scripts/flutter_build.sh`, `scripts/flutter_integration.sh`, `scripts/flutter_idle.sh` and `.github/workflows/flutter.yml` do not name the app file; they still work (CI below). `scripts/flutter_release.sh` on the branch `feat/xp-release` (PR #14) named `grove.app`: done in part 8.

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

## 8 · `Grove.app` in the release build and the speed check

The gap: PR #14 was written when the Mac build was `grove.app`. `scripts/flutter_release.sh` (line 36) and `scripts/flutter_perf.sh` (3 lines) named `grove.app` and the program `Contents/MacOS/grove`. The disk of this Mac does not tell big and small letters apart, so the old name still worked here. A disk that does would not find the app.

Built: both scripts name `Grove.app` and `Contents/MacOS/Grove`. `docs/acceptance/F12-release.md` names the same. Nothing to change in `.github/workflows/release.yml`, `app/tool/perf_start.dart`, `app/integration_test/perf_test.dart`, `scripts/flutter_build.sh`, `scripts/flutter_idle.sh` and `scripts/flutter_integration.sh`: they do not name the app file. The zip keeps its name `grove-macos.zip`.

Test: 'macOS: the scripts name the same app and the same program' in `app/test/app_name_test.dart`. It failed first (9 passed, 1 failed), then all 10 passed.

Proof on this Mac, 2026-10-12:

- `./scripts/flutter_release.sh macos`: exit 0. It printed `✓ Built build/macos/Build/Products/Release/Grove.app (59.0MB)` and `Release files for macos, in app/build/dist: 24M build/dist/grove-macos.zip`. The zip holds `Grove.app/Contents/MacOS/Grove`.
- `./scripts/flutter_perf.sh macos`: the three changed lines ran (the apps started from `start.app/Contents/MacOS/Grove` and `frames.app/Contents/MacOS/Grove`). **The numbers are not a clean measure**: the Mac was busy with other builds and tests. Start: 543 ms for the first start of the day, then 271 to 303 ms. Memory after the walk: `rss_mb` 172.1, `max_rss_mb` 230.1. Frames: `planner_week_scroll` 525 frames at 120.0 a second, `planner_block_drag` 418 frames at 119.5 a second, no late frame.

Not verified: the other 3 frame scenarios. In the first run the app stopped before the step "walk" (exit 1). In the second run the frames part ended after 2 of 5 scenarios, with no "done" line. Both times `/Users/andrei/Applications/Grove Flutter.app` (the same app id, `local.grove.grove`) was started from outside in the same seconds. I think that start quit my test app; I did not prove it. A third run of the start part alone passed. The `release` workflow on GitHub was not started: it is for the owner.

## 9 · The focus timer on each screen

The gap: `FocusLayer` was in `PlannerView.build` only. A session that ran while the person was on Notes or on the Garden had no timer on the screen. The Mac app hosts the timer in the window (`RootView.swift`, the overlay at the bottom right).

Built:

- `app/lib/ui/shell/root_view.dart`: `RootView.contentLayer`. It wraps the part of the window under the top strip (the left panel and the screen). On a phone it wraps the part between the top strip and the bar at the bottom. It stays when the screen changes.
- `app/lib/ui/app.dart` passes it on; `app/lib/ui/store_app.dart` gives `FocusLayer(store: …, child: content)`.
- `app/lib/ui/planner/planner_view.dart`: the `FocusLayer` is out of `build`. This is the one edit in the planner folder (the layer removed, an import removed, a comment), plus one comment line in `focus_card.dart`. Without it the planner would have two timers.

Tests: `app/test/ui/shell/focus_host_test.dart` (13 tests). With the old hosting 10 of them failed. They cover: the timer on Notes and on the Garden; one timer and one layer on each of the 5 screens; it counts on while the screen changes; "Mark done" and the cross on another screen; the place (230 wide, 16 from the bottom right corner of the window; on a phone 16 over the bar); the layer is made one time. One older test got one more second of clock: 'a session that ended on another screen asks at once' in `app/test/ui/planner/planner_focus_test.dart` (the timer is on Notes too now and reads the clock at its next beat). No picture changed.

Know this:

- On Today the timer is at the corner of the window. Before it was at the corner of the time column.
- With the task inspector open, the timer covers the bottom right corner of the inspector. The Mac app does the same.
- The command palette is drawn over the timer here. In the Mac app the timer is over the palette.

Not verified: by hand in a running app.

## 10 · "Zoom In" and "Zoom Out" for the whole window

The request of the planner helper said the keys work only while the grid has the keyboard. On this branch that was not true any more: View ▸ "Zoom In" (`⌘=`) and "Zoom Out" (`⌘-`) were built in part 2, with `store.zoomPlanner(1.2)` and `store.zoomPlanner(1 / 1.2)`, as `GroveApp.swift`. Two new tests show it: 'the zoom keys work on a screen that has no time grid' and 'with the keyboard in the grid one press is one step'. Both passed before any change.

The small gap that was real: the grid also takes `+`, the `+` and `-` of the number pad, and the keys with Shift held. The window took only `=` and `-` with no Shift.

Built: `ShellEntry.moreKeys` and `ShellEntry.accepts` in `app/lib/ui/shell/app_menus.dart`. "Zoom In" takes `=`, `+` and the `+` of the number pad; "Zoom Out" takes `-` and the `-` of the number pad; with Shift or not, with Cmd on a Mac and Ctrl on the others, not with Alt. A held key zooms again and again. The menu shows `⌘=` and `⌘-` as before.

Tests: 6 new tests in `app/test/ui/shell/app_menus_test.dart` (25 in the file). Before the change 3 of them failed.

Not verified: a real number pad, and a keyboard where `+` is not on the key of `=`.

## CI

Workflow `flutter`, 4 jobs. Each job runs `./scripts/flutter_test.sh`, `./scripts/flutter_build.sh <system>` and `./scripts/flutter_integration.sh <system>`.

The last code commit is `3f9e8ae`. The head that the CI ran is `ae050b4`: it has that commit, the merge of the base at `ec73831` (`7ef1276`) and one commit of docs. Run 38180832602 (push), 2026-10-11 22:32 UTC: **success**. Run 38180834740 (pull request) for the same head: success.

| Job | Result | What it shows |
|---|---|---|
| android (Linux) | success | 2392 tests and 1 skipped, the release build, the device test of the planner: 13 passed, 3 skipped |
| windows | success | 2392 tests and 1 skipped, `grove.exe` built with the new "Product name", the device test of the planner: 15 passed, 1 skipped; the window test: `GROVE_WINDOW system=windows window=1008.0x681.0 screen=1024.0x768.0 paddingTop=0.0 dock=16.0,5.0` |
| macos | success | 2393 tests, `Release/Grove.app` built (59.4MB), the device test of the planner: 15 passed, 1 skipped; the window test: `GROVE_WINDOW system=macOS window=1100.0x674.0 screen=1024.0x768.0 paddingTop=0.0 dock=84.0,5.0` |
| ios | success | 2393 tests, the build, the device test of the planner: 13 passed, 3 skipped |

The skipped test on Linux and Windows is the picture 'day spread desktop futuristic' (parked before this branch). The skipped device tests are skipped by rule (`app/integration_test/planner_test.dart`): 3 tests with a mouse and keys are not for a phone, and the pinch test is not for a computer. In each job the 13 tests of the focus timer, the new zoom tests and the 10 name tests ran, and no test failed. No fix round was needed.

The CI does not run `scripts/flutter_release.sh` or `scripts/flutter_perf.sh`. Part 8 is proved on this Mac only.

Know this: the run of the base at `8d7e023` (38177019248) was red in the windows job, in one test of the store ('one block per task a strip drop is one undo step that brings back the block', `app/test/state/planner_store_test.dart`). The same test passed on Windows in the run above. It looks like a test that fails now and then on Windows. It is not a part of this branch.

Earlier runs of this branch: 38157187332 (`1c2f7c5`), 38157382838 (`f5a88fe`), 38157913112 (`dd3157c`), 38164051282 (`6baeeb2`) and 38179638196 (`77d4c31`, after the first merge of the base on 2026-10-12) were green. Run 38162697134 (`3c20f16`) and run 38163112481 (`2ac26a7`) were red in the windows job only: the window test asked for 1100 points of width on a screen of 1024 × 768, and Windows does not make a window bigger than the screen (it gave 1028 × 681). One fix round: `6baeeb2` (the window fills the free part of such a screen; the test allows it).

The screen of the CI machines is 1024 × 768. So the CI proves the smallest size on the Mac and the small-screen case on Windows. The first size 1280 × 800 is proved on this Mac only. On Windows the first size and the smallest size on a big screen are **not verified**.

## Questions and requests

- **Q-40** (`docs/questions.md`): answered B on 2026-10-12. The Windows "Product name" is "Grove" now, see part 5.
- No new question card. Q-41 to Q-44 are not used.
- `docs/tracks.md`, still open: the now line of the planner (idle CPU); the pictures of Track A that were made again. Done on 2026-10-12: `Grove.app` in the release scripts (part 8), the host of the focus card (part 9), the zoom commands (part 10).
- `docs/assumptions.md`: 19 lines that start with "2026-10-11 · Cross-platform port F12 shell gaps" and 5 lines that start with "2026-10-12 · Cross-platform port F12 shell gaps".
