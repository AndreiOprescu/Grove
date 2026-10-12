# F12 · Release builds (not signed) and speed check — proof

Plan: `docs/cross-platform-plan.md`, milestone F12: "perf check (startup, RAM, 60 fps scroll), signed builds per OS". This file is the part "release builds and speed check". The feature checklist is `docs/acceptance/F12-parity.md` (another branch).

Date: 2026-10-11. Branch: `feat/xp-release`. Flutter 3.47.7.
Machine: MacBook Pro (Mac17,2), Apple M5, 16 GB, macOS 27.0.1, built-in screen at 120 Hz.
Check: `./scripts/flutter_test.sh` → 1904 tests passed, analyze clean (before the change and after it).

**The numbers are noisy.** Other helpers built and tested on this Mac at the same time (load average 2 to 7), and the owner used it. Take them again on a quiet Mac: the commands are below.

## 1. Release builds

One command per system: `./scripts/flutter_release.sh <macos|windows|android|ios>`.
It calls `scripts/flutter_build.sh` (the build was a release build before; that did not change) and puts the files to hand out in `app/build/dist/`. Git ignores that folder.

| System | Command | File made | Size | Signed with | Checked here |
|---|---|---|---|---|---|
| macOS | `./scripts/flutter_release.sh macos` | `app/build/dist/grove-macos.zip` (inside: `Grove.app`; it was `grove.app` until 2026-10-12, see finding 4 in 2.4) | 23 801 741 bytes (the app: 55 MB, Intel + Apple chips) | "ad hoc" by Xcode: no name, no team | Built. Unzipped: `codesign --verify --deep --strict` is fine. Started once, see below |
| Android | `./scripts/flutter_release.sh android` | `app/build/dist/grove-android.apk` | 68 761 062 bytes | the debug key of the Android tools on this Mac (`CN=Android Debug`) | Built. `apksigner verify --print-certs` shows the debug key. Package `local.grove.grove`, version 1.0.0 (1), 3 chip types. Not installed on a phone |
| Android | (same command) | `app/build/dist/grove-android.aab` | 65 875 713 bytes | the same debug key | Built. Not sent to a store |
| iOS | `./scripts/flutter_release.sh ios` | `app/build/dist/grove-ios-unsigned.zip` (inside: `Runner.app`) | 10 635 189 bytes (the app: 24.8 MB) | nothing (`--no-codesign`); `codesign -dv` says "not signed at all" | Built. It cannot be put on a phone |
| Windows | `./scripts/flutter_release.sh windows` | `app/build/dist/grove-windows/` (with `grove.exe`) | not built | nothing | **Not built here**: a Mac cannot build for Windows. The same build line (`flutter build windows --release`) is green in the workflow `flutter`. The copy into `dist` did not run anywhere yet |

### What I started and saw (macOS)

- Command: `app/build/macos/Build/Products/Release/grove.app/Contents/MacOS/grove`, once, for about 40 seconds. Then I stopped it with `kill -TERM`. (The names of that day. Since 2026-10-12 it is `Grove.app/Contents/MacOS/Grove`.)
- The process stayed up. Its log had one line: "Using the Impeller rendering backend (MetalSDF)". No error.
- It made a new store in the data folder of the Flutter app, which was empty before: `~/Library/Containers/local.grove.grove/Data/Library/Application Support/local.grove.grove/` now has `grove.sqlite` and `Backups/grove-2026-10-11.sqlite`. I left them there.
- Memory after 14 seconds: 232.8 MB ("Physical footprint" of `vmmap`). CPU: 26 to 46 % of one core with nothing to do (see finding 3).
- **I did not look at the window.** A screenshot would show the owner's screen, so I took none. That the screens draw in a release build is shown by the start-up tool of part 2: it waits for the first frame on the screen and walks through all screens.

### What "no key" means

- **Android.** `app/android/app/build.gradle.kts` has `signingConfig = signingConfigs.getByName("debug")` for the release build. That is the Flutter template. So the APK and the bundle are signed with the debug key that the Android tools make by themselves on each machine (`~/.android/debug.keystore`). I made no key.
  - The APK installs on a phone by hand ("install unknown apps").
  - A build from another machine has another debug key. A CI machine makes a new one in each run. Android then refuses the update: the old app must be removed first, **and its data goes with it**.
  - The Play Store does not take a file signed with a debug key.
- **macOS.** The app runs on the Mac that built it. A copy that came by download is stopped by macOS on another Mac (`spctl --assess` on the unzipped app says "rejected"). The user can let it through in System Settings ▸ Privacy & Security ▸ "Open Anyway".
- **Windows.** The folder runs. For a downloaded copy Windows shows the blue "Windows protected your PC" box; "More info" ▸ "Run anyway" starts it. I did not check this on a Windows machine.
- **iOS.** Nothing works with no signing. `Runner.app` is only proof that the code builds.

### A build with your keys, on your Mac

A build with no key file has no sync. CI has no keys, and I did not add any.

1. `cp app/config/supabase.example.json app/config/supabase.json`
2. Put your `SUPABASE_URL` and `SUPABASE_ANON_KEY` in it (see `docs/acceptance/F11-login.md`). Git ignores the file. Never commit it.
3. `./scripts/flutter_release.sh macos` (or `android`, `ios`). The script finds the file by itself.
4. The files are in `app/build/dist/`.

### The workflow `release`

File: `.github/workflows/release.yml`. It starts by hand only (`workflow_dispatch`). 4 jobs, the same machines as the workflow `flutter`. Each job runs `./scripts/flutter_release.sh <target>` and keeps `app/build/dist/` as a file of the run for 30 days (`grove-<target>-<run number>`). No secret, no store, no GitHub Release, no tag. `actionlint` finds nothing in the file.

**Not verified on CI.** I tried once: `gh workflow run release.yml --ref feat/xp-release` → `HTTP 404: workflow release.yml not found on the default branch`. GitHub starts a workflow by hand only when its file is on the default branch (`main`). I did not push to `main`.

## 2. Speed check

Command: `./scripts/flutter_perf.sh macos` (both parts), or `... macos start`, `... macos frames`.
Data, the same in each run (`app/tool/perf_data.dart`): 1 000 tasks (580 done, 278 waiting in the Tasks panel), 407 events, 270 notes, 4 goals, 3 lists, 69 planner blocks in this week. It lives in the temporary folder of the app (`~/Library/Containers/local.grove.grove/Data/tmp/grove-perf` and `grove-perf-frames`), never in the data folder of Grove. No reminder goes to the system.

Pass lines from `PLAN.md`: §10 "App launches in < 1 s with 1 000 tasks", §10 "`tasks(for:)` < 50 ms" with 1 000 tasks, and "smooth 60 fps dragging" (the Day Planner) with "60 fps scroll" in the plan of F12. **Memory has no pass line in `PLAN.md`**; I made none.

### 2.1 Start-up — pass

- Command: `./scripts/flutter_perf.sh macos start`. Release build of `app/tool/perf_start.dart`: the same lines as `lib/main.dart`.
- What is timed: from just before the process starts (the clock of the shell) to the first frame on the screen. The start from the Finder adds the time of macOS itself; that is not in the number.

| Run (time) | 6 starts, ms | First start of the day (makes the backup), ms |
|---|---|---|
| 1 (about 14:20) | 193.6, 188.0, 188.3, 186.0, 184.4, 188.8 | 459.2 |
| 2 (15:30) | 323.2, 238.3, 259.1, 262.9, 285.0, 308.4 | 306.9 |
| 3 (15:42) | 208.7, 204.9, 186.1, 194.0, 179.6, 195.8 | 295.6 |
| 4 (15:44) | 179.0, 195.0, 198.0, 208.0, 187.9, 190.5 | 211.5 |
| Store of a new user (15:31, `GROVE_PERF_EMPTY=1`) | 246.8, 233.3, 300.4, 255.2, 240.4, 296.6 | 284.5 |

- **Pass line < 1 000 ms: pass.** All 24 starts with 1 000 tasks are between 179 and 323 ms. The slowest start of all is 459 ms. Noisy: run 2 is slower than the others for no reason in the app.
- The data costs no time that I can see: the store of a new user starts as fast (run 2 and the empty run were taken one after the other).

### 2.2 The tasks of a day — pass

- Same command and build. After the start the tool reads the tasks of today 20 times (`repos.tasks.forDay`) and prints the slowest read as `tasks_of_day_ms`.
- 14 lines in runs 3 and 4: 0.08 to 0.40 ms. **Pass line < 50 ms: pass.**

### 2.3 Memory — no pass line; numbers only

- Same command. "Footprint" is the "Physical footprint" of `vmmap --summary`, the number that Activity Monitor shows. "RSS" is what the app reads about itself.
- The walk: Planner, Calendar, Notes, Today, Planner, each left panel, 5 notes, back to Today. Window 800 x 600 points, 1600 x 1200 pixels.

| Run | After the start: RSS / footprint | After the walk: RSS (highest RSS) / footprint | State of the app |
|---|---|---|---|
| 1 | 168.0 MB / 222.8 MB | 203.8 MB (260.8) / 279.2 MB | not written down |
| 2 | 151.7 MB / 210.4 MB | 187.4 MB (231.2) / 272.1 MB | not written down |
| Store of a new user | 143.3 MB / 214.6 MB | 157.2 MB (164.2) / 236.9 MB | not written down |
| 3 | 167.5 MB / 129.0 MB | 181.2 MB (225.6) / 156.6 MB | not written down |
| 4 | 163.3 MB / 136.0 MB | 178.2 MB (224.6) / 149.4 MB | "inactive": another program was at the front |

What I found:

- The table of `docs/cross-platform-plan.md` describes Flutter as "~80–150 MB". With the window at the front Grove is above that: about 210 to 280 MB.
- **The data is not the cause.** The store of a new user has the same footprint after the start (214.6 MB against 210.4 MB). The 1 000 tasks and 270 notes add about 35 MB after the walk.
- **Most of it is the memory of the GPU.** One reading of `vmmap` at 209 MB: about 132 MB of graphics memory (IOSurface 29 MB, IOAccelerator 29 MB, "owned unmapped (graphics)" 74 MB), about 44 MB of malloc, about 17 MB of Dart.
- The footprint was 129 to 136 MB in the two runs where the app was not at the front, and 210 to 223 MB in the others. When Grove is not at the front, its background stops moving. I did not prove that this is the cause. The memory of the GPU also grows with the size of the window; I did not measure a large window.
- No fix made. The cause is in how the screens are drawn, not in a small safe file.

### 2.4 Frame times — Planner: pass · Tasks panel: not settled

- Command: `./scripts/flutter_perf.sh macos frames`. Profile build of `app/integration_test/perf_test.dart`. Motion is on. The times come from the engine (`FrameTiming`): "build" is the work of Dart for a frame, "raster" is the drawing.
- How I read "60 fps": 60 frames a second or more on average, and at most 1 frame in 100 "late" (build + raster longer than 16.7 ms).
- The window must stay in view. macOS gives few frames or none to a window that it does not show. Each line has `app_states`: it tells when the app was hidden. It does not tell when another window lay over the test window.

The best run (15:39; `app_states` empty for all 5 parts):

| Part | Frames | Per second | Build ms: mean / 99 % / max | Raster ms: mean / 99 % / max | Late frames | Result |
|---|---|---|---|---|---|---|
| Planner, week grid, scroll (900 points a second) | 676 | 120.0 | 1.09 / 1.61 / 4.16 | 1.26 / 1.86 / 9.89 | 0 | pass |
| Planner, a block dragged down, to the next day and back | 417 | 118.9 | 0.39 / 7.74 / 12.91 | 1.83 / 3.38 / 3.86 | 1 (16.77 ms) | pass |
| Tasks panel, 278 rows, scroll (2 500 points a second) | 2 881 | 119.9 | 3.03 / 3.79 / 11.66 | 1.05 / 1.24 / 8.77 | 0 | pass |
| Notes list, 270 notes, scroll (2 500 points a second) | 2 881 | 120.0 | 0.53 / 1.29 / 1.70 | 1.11 / 1.66 / 10.07 | 0 | pass |
| Today, timeline, scroll (900 points a second) | 650 | 120.0 | 0.38 / 0.51 / 1.16 | 0.68 / 0.90 / 3.30 | 0 | pass |

The test also checks that the dragged block lands one hour later, and it does.

**That table is the best run, not the whole story.** All the runs of the day, part by part:

| Part | Times measured | Frames a second in each | Late frames in each | Reading |
|---|---|---|---|---|
| Planner, week grid, scroll | 10 | 119.6 to 120.0 | 0 | pass, each time |
| Planner, block drag | 7 | 118.3 to 119.4 | 0 to 2 of about 420 | pass, each time |
| Tasks panel, scroll | 6 | 57.9 · 111.8 · 53.2 · 119.8 · 57.3 · 119.9 | 160 · 18 · 38 · 0 · 80 · 0 (of 1 300 to 2 900) | **3 of 6 under 60. Not settled** |
| Notes list, scroll | 5 | 106.8 · 6.4 · 120.0 · 12.5 · 120.0 | 1 · 0 · 0 · 2 · 0 | pass when frames came; see below |
| Today, timeline, scroll | 4 | 120.0 · 6.4 · 12.7 · 120.0 | 0 · 4 (of 36) · 0 · 0 | pass when frames came; see below |

(The Planner parts have more results: early runs stopped after them, and 2 later runs stopped when the app was hidden.)

What I can say about the slow results, and what I cannot:

- The Planner is the screen that `PLAN.md` names for 60 fps. It held 118 to 120 frames a second in every run, also under load.
- The Tasks panel fell under 60 in 3 of 6 runs (the first at 14:57, the last at 15:27). The run of 14:57 had one build of 551 ms.
- In each of those 3 runs the part right after it also lost frames in the same way: gaps of 108 to 208 ms between frames, and in 2 of the runs the Notes list and Today came down to 6 to 13 frames a second. Those two lists need 0.4 to 0.5 ms of work for a frame. A list like that cannot slow itself to 6 frames a second. So something outside the app held the frames back in those runs. Most likely another window lay over the test window: other helpers opened app windows at the same place, and the owner worked. macOS then slows the app down.
- **That is my reading, not a proof.** In the run of 15:27 `app_states` was empty, so the app was not hidden; the test cannot see a window on top of it. And the trouble started in the Tasks panel part in all 3 runs. That part is the longest (24 seconds) and comes third, so that can be chance. It can also be the app.
- In the 2 runs with no gaps (15:18 and 15:39) the Tasks panel ran at 119.8 and 119.9 frames a second with 0 late frames.
- So: do not take the Tasks panel as proven. It needs a run on a quiet Mac with the window left alone (the list "Needs the owner"). Finding 1 below is a real weak point of that panel either way.
- 2 runs stopped because the app was hidden (`app_states` says "hidden"). The test now ends with a clear line after 4 minutes when that happens.

### Findings (no fix made: the files are in `app/lib/ui/`, which another helper edits)

1. **Tasks panel: each scroll frame costs 3 times the work of the other lists** (build 3.0 ms against 0.4 to 1.1 ms, in the runs with no gaps). `app/lib/ui/tasks/tasks_pane.dart:249-256`: a `SingleChildScrollView` with one `Column` of all rows. All 278 rows are built and laid out at once, and most likely all are painted again for each scroll step (I read the code; I did not profile it). It passes here with 278 rows. The cost grows with the number of waiting tasks, and a phone is slower. Fix for later: a lazy list (`ListView.builder` or slivers), as the Notes list has (`app/lib/ui/notes/notes_view.dart:212`).
2. **Drag: one frame in each drag is long** (build 11.5 to 16.0 ms; build + raster 15.5 to 19.9 ms in 7 runs). It is 0 to 2 frames of about 420, so the line holds. I did not find which moment of the drag it is (the start, the change of column or the drop).
3. **With nothing to do, the app at the front uses 26 to 46 % of one core** (4 readings of `top` and `ps` on the release app). Most likely the moving background: `app/lib/ui/theme/ambient_background.dart:106-128` draws it 30 times a second, as `PLAN.md` §6.3 says, and stops when the window is not at the front or Motion is off. No pass line. I did not measure with Motion off.
4. **The Mac app is `grove.app`, with a small g** (`PRODUCT_NAME = grove` in `app/macos/Runner/Configs/AppInfo.xcconfig`). The Swift app is `Grove.app`. Not changed: a name is the owner's call. **Changed on 2026-10-12, with the shell gaps (PR #18):** `PRODUCT_NAME = Grove`, so the build is `Grove.app` and its program is `Contents/MacOS/Grove`. `scripts/flutter_release.sh` and `scripts/flutter_perf.sh` name the new app. The zip keeps its name, `grove-macos.zip`. Proof: `docs/acceptance/F12-shell-gaps.md`.

## 3. The app id (`local.grove.app`) — not changed; Q-30 answered: not now

**Answer of the owner (2026-10-11, Q-30: B):** the id stays `local.grove.grove` while the owner uses the Swift Mac app. It changes to `local.grove.app` on the day the owner retires the Swift app. No code was changed.

The owner answered Q-26: the Flutter app must have the id `local.grove.app`. Before the change I checked if the Flutter app could then touch a file of the Swift Mac app. Result: the database is safe; two other things are shared. So I did not change the id.

Where the Swift app keeps its things (code, and names seen in `~/Library`; I opened no file):

| Thing | Place | Code |
|---|---|---|
| Database | `~/Library/Application Support/Grove/grove.sqlite` (+ `-wal`, `-shm`) | `Sources/GroveCore/Database/Database.swift:64-74`: the folder name is the fixed word `Grove` |
| Backups | `~/Library/Application Support/Grove/Backups/grove-YYYY-MM-DD.sqlite` | `Sources/GroveCore/Services/Backup.swift` |
| Settings | `~/Library/Preferences/local.grove.app.plist` (theme, motion, work hours, reminders) | `UserDefaults.standard` and `@AppStorage`; the file has the name of the id |
| Reminders | the notification store of macOS, under the id `local.grove.app`; names start with `ev-` and `due-` | `Sources/Grove/Reminders/Notifier.swift:84-103` |

The Swift app is not sandboxed (`scripts/build_app.sh` signs it with no entitlements).

Where the Flutter app would keep its things with the id `local.grove.app`:

| Thing | Place | Code |
|---|---|---|
| Database, backups, `prefs.json` | `~/Library/Containers/local.grove.app/Data/Library/Application Support/local.grove.app/` | `app/lib/main.dart:16` (`getApplicationSupportDirectory()`: the folder has the name of the id); the app is sandboxed (`app/macos/Runner/Release.entitlements`) |
| Settings of macOS for the window | `~/Library/Containers/local.grove.app/Data/Library/Preferences/local.grove.app.plist` | written by macOS and Flutter, not by Grove's code. Today's container has `local.grove.grove.plist` there |
| Reminders | the notification store of macOS, under the id `local.grove.app`; names are numbers | `app/lib/services/system_notifier.dart:124-142` |

What that means:

- **Database and backups: the Flutter app cannot touch them.** Two reasons, each enough alone: (1) the folder names differ (`Grove` against `local.grove.app`), and no line in `app/lib` names the Swift folder; (2) the sandbox of macOS keeps the Flutter app out of `~/Library/Application Support/Grove/`. So the Flutter schema 7 can never be put on the Swift database (schema 6).
- **Settings file: not sure.** Both apps have a settings file with the same name, in two places. When macOS makes the container of a sandboxed app for the first time, it can move files of an older app with the same id into the container. I remember from Apple's old sandbox guide that it does this for the main settings file by itself. Apple's page of today does not say yes or no, and I could not test it without the owner's real file. If it happens, the Swift app loses its settings (theme, work hours, lead time of reminders), not its data.
- **Reminders: shared.** macOS keeps one list of reminders and one permission per id. By the code neither app removes the reminders of the other (the Swift app removes only `ev-`/`due-`, the Flutter app only its own numbers). But both show under one name, and a reminder of the Swift app can make the Flutter app's read of the list fail (the plugin wants numbers). Not tested.
- Also: macOS then knows two apps with one id (`~/Applications/Grove.app` and `grove.app`). The Swift app answers links that start with `grove://`; which app opens for them is then not sure.
- An app installed with the old id keeps its own data folder (`~/Library/Containers/local.grove.grove/`, it exists on this Mac). The new id starts with an empty folder. Nothing moves the data from the Swift app or from the old id.
- On Windows the id of the reminders is `local.grove.Grove` and must not change (`docs/assumptions.md`, F10-services). iOS and Android have no Swift app; only the Mac has the risk.

### On the day the Swift app is retired

The owner picks the day. These steps are a plan; none of them was run.

1. The owner keeps a copy of the Swift data: the folder `~/Library/Application Support/Grove/` and the file `~/Library/Preferences/local.grove.app.plist`.
2. The data that the Flutter app has under the old id must be safe before the change: it is in the account (sync is on and has run), or it was saved with Export in Settings.
3. The Swift app no longer runs on the Mac (`~/Applications/Grove.app`). Then the two apps cannot share the settings file or the reminders.
4. **Change the id to `local.grove.app`** in: `app/macos/Runner/Configs/AppInfo.xcconfig:11`, `app/ios/Runner.xcodeproj/project.pbxproj` (3 lines), `app/android/app/build.gradle.kts` (`namespace` and `applicationId`) with the folder of `MainActivity.kt`. The Windows id of the reminders (`local.grove.Grove`) stays. Then: `./scripts/flutter_test.sh`, the builds, and CI green on all 4 with the device tests.
5. **The Flutter store then starts empty** (a new folder: `~/Library/Containers/local.grove.app/` on the Mac; on a phone the app with the new id is a new app beside the old one). Sync, or Import in Settings, brings the data back.
6. The old folder `~/Library/Containers/local.grove.grove/` stays until the owner removes it.

Not checked by me: Export and Import (they are on the branch `feat/xp-screens`, not on this one) and a real sync. The database of the Swift app is schema 6; nothing in this plan reads it into the Flutter app.

## 4. Signing — Q-31 answered: none now

**Answer of the owner (2026-10-11, Q-31: A):** no signing now. No key, certificate or account is made.

I made no key, no certificate and no account. The table says what each system needs when the owner wants it later.

| System | What the owner must get | Cost that I know for sure | With no signing |
|---|---|---|---|
| macOS | Apple Developer Program; a "Developer ID Application" certificate; notarization of each build | 99 USD a year (one fee for macOS and iOS) | Runs on this Mac. Another Mac stops a downloaded copy until the user allows it |
| iOS | The same Apple Developer Program; a certificate and a provisioning profile for the id | in the same 99 USD a year | Cannot be put on a phone. (With a free Apple ID, Xcode can sign for your own phone; that app stops after 7 days) |
| Android | An upload key, made once with `keytool` and kept safe (if it is lost, updates stop). For the Play Store: a Google Play developer account | the key is free; the Play account is 25 USD, one time | The APK installs by hand. Updates from another machine need a removal first (data lost). No Play Store |
| Windows | A code signing certificate from a certificate seller | paid, each year; I do not know a sure price | Runs. Windows warns about a downloaded copy |

## 5. CI, workflow `flutter`

Last code commit of this branch: `f62e64f`. The commits of this branch after it change files in `docs/` only. The merge `0694489` brings the base `feat/cross-platform-flutter` (pull requests #11 and #13) into the branch.

| Run | For | android | windows | macos | ios |
|---|---|---|---|---|---|
| 38144548470, first try | push of `f62e64f` | **red** | green | green | green |
| 38144548470, second try (only the red job ran again) | the same commit | green | green | green | green |
| 38144952257 | the pull request #14, the same code | green | green | green | green |
| 38146308270 | the pull request #14, `9a2cd62` (tested merged with the old base `dbce123`) | **red** | green | green | green |
| 38147557696 | the pull request #14, `c8e846b` (tested merged with the old base `dbce123`) | **red** | green | green | green |
| 38157110084 | the pull request #14, `0694489` (tested merged with the new base `b7a20b9`) | green | green | green | green |

Why Android was red in the first try: the device test `calendar: the card of a new event saves the event` (`app/integration_test/planner_test.dart:328`, a file of Track B that this branch does not change). The tap on Save did not reach the button, because the keyboard of Android came up and moved it. Track B fixed that test in commit `654e3df` on the branch `feat/xp-screens` ("the device test taps Save when the button is in view"). For the first try I ran the red job again once and changed no code; it was green. That fix was not on this branch, and a pull request is tested merged with its base. The two red runs of the pull request (38146308270 and 38147557696) fail in the same test, at the same line, with the same tap point (`Offset(347.6, 567.0)`), and both merged with the old base `dbce123`, which still had the old test. Nothing in this branch changes `app/lib/` or that test. I merged `feat/cross-platform-flutter` (`b7a20b9`, with `654e3df`) into this branch in `0694489`; then the run 38157110084 merged with `b7a20b9` was green on all 4, and on Android the test `calendar: the card of a new event saves the event` passed (9 device tests passed). One green run is one try: the first red run of 38144548470 shows the failure comes and goes, so the base test is a fix, not a proof that it can never be red again.

The speed check is not in this workflow.

## Not verified

- The workflow `release` did not run on GitHub (see 1). Its upload step and the Windows copy step never ran.
- No Windows build and no Windows start on this Mac.
- The Android APK and bundle were not installed on a phone or an emulator. The iPhone build cannot be installed.
- I did not look at the window of the release app (no screenshot of the owner's screen).
- No speed numbers for Windows, Android or iOS. No simulator numbers: a simulator has no profile mode, and they are not device numbers.
- **60 fps in the Tasks panel**: 3 of 6 runs were under 60, and I could not prove that the cause was outside the app (see 2.4).
- All speed numbers were taken on a busy Mac. Memory with a large window, and CPU with Motion off, were not measured.
- If macOS moves the settings file of the Swift app into a new container (see 3).

## Needs the owner

1. Q-30 and Q-31 are answered (2026-10-11): the id stays, no signing now. Open point for later: the steps "On the day the Swift app is retired" in part 3.
2. To check the workflow: after this branch is on `main`, open Actions ▸ release ▸ "Run workflow" (or `gh workflow run release.yml`), then download the 4 files of the run.
3. For a build with sync: the 4 steps in "A build with your keys, on your Mac".
4. On a quiet Mac, with the window left alone and nothing over it: `./scripts/flutter_perf.sh macos`. About 4 minutes. Look at the line `tasks_panel_scroll`: `fps` must be 60 or more and `late_frames` at most 1 in 100 of `frames`. That settles the Tasks panel.
5. Look once at the Mac release app yourself: `open app/build/macos/Build/Products/Release/Grove.app` after `./scripts/flutter_release.sh macos`.
6. Decide about the findings in 2.4 (Tasks panel list, idle CPU; the name is settled, the app is `Grove.app` now) and about the memory in 2.3.
