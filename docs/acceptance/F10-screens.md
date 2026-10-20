# F10-screens · Garden, growing plant, Settings — proof

Plan: `docs/cross-platform-plan.md` (milestone F10), `docs/tracks.md` (Track B, F10-screens). Check: `./scripts/flutter_test.sh` (2026-10-11: 2077 tests passed, analyze clean, format clean; 80 of them are new for F10-screens and 46 more came with the owner's answers of 2026-10-11; on Linux and Windows 1 test is skipped, see "CI"). Device check: `./scripts/flutter_integration.sh <macos|windows|ios|android>` (9 tests; 1 is new for F10-screens). CI run: see "CI" below.

The Settings tests were written first. They did not build before the code was there (`cd app && flutter test test/ui/settings`: 2 files failed to load). The Garden tests were written first too. The test of the small plant was written in one step with its code, not before it.

Acceptance: "Feature tests + goldens green."

| Swift source | Dart port | Tests | Status |
|---|---|---|---|
| `Garden/GardenView.swift` | `app/lib/ui/garden/garden_view.dart` | `test/ui/garden/garden_view_test.dart` (11) | Green |
| `Garden/GardenPainter.swift` | `app/lib/ui/garden/garden_painter.dart` | in the Garden tests and the golden pictures | Green |
| `Theme/GrowingPlant.swift` | `app/lib/ui/theme/growing_plant.dart`, `sway_clock.dart`; the header of `app/lib/ui/spread/day_spread_view.dart` | `test/ui/theme/growing_plant_test.dart` (5) | Green |
| `Settings/SettingsView.swift` | `app/lib/ui/settings/settings_view.dart`, `settings_tabs.dart`, `settings_parts.dart` | `test/ui/settings/settings_view_test.dart` (37) | Green |
| — (new, asked by Track A) | `app/lib/ui/settings/sync_mark.dart`, the Sync tab, `FirstSyncGate` in `app/lib/ui/store_app.dart` | `test/ui/settings/settings_sync_test.dart` (9) | Green |
| `GroveApp.swift` (the Settings window, Cmd+comma) | `app/lib/ui/store_app.dart`, `app/lib/ui/shell/root_view.dart`, `appearance_button.dart`, `app/lib/ui/app.dart` (shared, 3 new optional parameters) | in the Settings tests | Green |
| `Tests/GroveTests/CheckBoxClickTests.swift` | — (tests only) | `test/ui/spread/day_spread_view_test.dart` (5 new) | Green |
| — (new) | `app/test/ui/goldens/` (19 new pictures, 7 made again) | `f10_golden_test.dart` (19) | Green |
| — (new) | `app/integration_test/planner_test.dart` (1 new test) | on the real app | See "CI" |
| `Services/ImageTools.swift` (`prepare`) | `app/lib/ui/editor/image_prepare.dart` | `test/ui/editor/image_prepare_test.dart` (14) | Green |
| `Editor/RichTextEditor.swift` (`addImage`, a click on a link) | `app/lib/ui/editor/rich_text_field.dart`, `editor_tools.dart` | `test/ui/editor/rich_text_field_test.dart` (15 new), `editor_tools_test.dart` (3) | Green |
| — (the real windows of the system) | `app/lib/ui/system/system_tools.dart`, `app/lib/main.dart`, `app/lib/ui/store_app.dart` | `test/ui/store_app_tools_test.dart` (8, with fakes) | Green with fakes. The real windows: not tried |

The rules under these screens (`Garden`, `GardenStage`, `DayRules.plantLeaves`, `SettingsRules`, the settings, backups, import and reminder calls of the store) are Track A's. They were ported and tested before, with the engine and with F10-services. The sync card, the question of the first login and their tests are Track A's (F11-login).

## What each part does

### The Garden

- One plant for all finished tasks. The title "Garden", one line of text, the plant card, and the ladder "Stages".
- The plant card shows the plant, 360 points high, for the growth number of the rules (0 to 11), the name of the stage, and the count of finished tasks.
- Under the plant: how many tasks the next stage needs, and a bar. The bar is never shorter than 8 points. A full tree says "Fully grown. Keep going. It likes company." and has no bar.
- The plant grows to a new size in 0.9 s when a task is finished. With motion on it sways; a big tree sways less than a sprout. With motion off, or with "reduce motion" of the device, nothing moves.
- The ladder shows the 12 stages as cards: a small picture, the name, the count of tasks where it starts, and "Reached", "Now" or "Not yet". The stage of now has a ring.
- The cards are 118 to 160 points wide, on whole points. They fill the row and go on to the next row.
- A screen reader hears "Garden plant, <stage>" and each stage with its state.

### The growing plant of the day

- A small plant, 40 points high, in the header of the Day Spread, at the right, as on the Mac.
- It has up to six leaves for the share of today that is done, and a flower when all is done (`DayRules.plantLeaves`).
- A new leaf grows in 0.5 s with a small bounce. With motion on the plant sways 3 degrees over 5 seconds.
- A screen reader hears the growth of the day.

### Settings

- A window over the screens. 600 by 540 points on a desktop (the size of the Mac window), smaller in a small window, the whole screen on a phone.
- It opens from the new last line "Settings…" of the Appearance menu and with Cmd or Ctrl and comma. The close button and Escape close it.
- Six tabs: Appearance, Planner, Notes, Notifications, Sync, Data. The Mac app has five; "Sync" is new. The row of tabs scrolls sideways when it does not fit.
- Appearance: four theme cards, System / Light / Dark, the motion switch, the accent intensity (0 % to 150 %).
- Planner: the length of a new event, the hour height (the planner follows at once), the working hours (always one hour long at least), the busy day limit, "Tint days by mood", the first day of the week.
- Notes: the template of the daily note and of the weekly note. A template saves as you type. "Use the default" goes back to the first text.
- Notifications: the switch for reminders, how long before a task, the state of the permission, and "Allow notifications". The switch asks for the permission the first time it goes on. The window reads the permission when it opens.
- Sync: Track A's `SyncCard`. A copy of Grove with no sync says so.
- Data: the path of the data folder with "Copy the path", and the daily backups. A store with no folder (a store in memory) says "Grove cannot find its data folder."
- Export and Import: see "Images, links, Export and Import" below. Export saves all data under the name of today. Import asks first, saves a copy of the old data, then replaces the data. A wrong file changes nothing. With no folder for the copy nothing changes.

### Images, links, Export and Import (the owner's answers of 2026-10-11)

The owner answered Q-15, Q-16 and Q-18 with A, and said for Import with sync: block it while signed in. Two packages came in: `file_selector` and `url_launcher`.

- "Add an image" is in the row of buttons of a note and of the notes of an event. It opens the file window of the system. The user picks one picture or more. Each picture goes in the text at the caret, with the name of the file as its name.
- A PNG or a JPEG of at most 1600 pixels on the long side is kept byte for byte, as on the Mac. Any other picture (larger, or a GIF, WebP or BMP) is written again as a PNG of at most 1600 pixels. A file that is not a picture gives "<name> is not an image Grove can read." and changes nothing. A file window that fails gives "Grove could not open the file window."
- A click or a tap on a web link opens the browser of the system. Only an `http` or `https` address with a host opens. The editor makes a link only from text that starts with `http://` or `https://`, and the rule is checked again before the browser (`webLink`). The second click of a double click opens nothing. A drag opens nothing. When the system cannot open the link: "Grove could not open the link."
- "Export JSON…" shows on macOS and Windows. Android and iOS have no save window in `file_selector`, so there the tab says "Export is not on this device yet." (Q-27).
- "Import JSON…" shows on the 4 systems. While you are signed in to sync it is grey, a screen reader hears that it is off, and a line says: "Import is off while you are signed in to sync. Sign out first (Settings, Sync), then import." After a sign-out it works again.
- Import checks the login three times: before the file window, after the pick, and after "Replace everything?". A login in the middle stops it with "You are signed in to sync. Sign out first, then import. Nothing was changed."
- The block is in the screen only. `store.importData` itself does not refuse; a request to Track A is in `docs/tracks.md`.
- Each real window is behind a parameter of `StoreApp` (`files`, `pickImages`, `openLink`). `main.dart` gives the real ones. A test gives fakes or none. No test opens a real file window or a real browser.

Platform set-up, all in shared files (each one is in `docs/assumptions.md`):

- `app/pubspec.yaml`, `app/pubspec.lock`: the two packages. The generated plugin lists of macOS and Windows changed with them.
- `app/macos/Runner/DebugProfile.entitlements`, `Release.entitlements`: `com.apple.security.files.user-selected.read-write`. The Mac build is sandboxed; this lets it read and write only a file the user picks.
- `app/android/app/src/main/AndroidManifest.xml`: two `<queries>` entries, to view an `https` and an `http` address. No new permission.
- iOS and Windows need no set-up for these two packages.

Order of work: the tests of the editor, of `StoreApp` and of Settings were written first and were red (they did not build, or 4 Settings tests failed). The two small pure rules, `webLink` and `prepareImage`, were written just before their tests.

### The sync parts in the shell

- `SyncMark`: a small cloud in front of the Appearance button. Only a copy of Grove with sync shows it. The icon follows `store.syncStatus`. A tap opens Settings on the Sync tab. An error is in the second accent colour, and the tooltip says "The last sync did not work. Open Settings to see why."
- `FirstSyncGate` is around the screens, under the navigator. The question of the first login opens with and without the Settings window.

## Phone vs desktop

| | Wide window | Phone (narrower than 700 pt) |
|---|---|---|
| Garden | a page 980 pt wide at most, the title 28 pt | the same page, the title 22 pt, fewer cards in a row |
| Settings | a window of 600 × 540 in the middle | the whole screen, inside the safe area |
| Theme cards | 4 in a row | 2 by 2 when the row is narrower than 400 pt |
| Tabs of Settings | all six in the row | the row scrolls sideways |
| Small plant | in the header of the Day Spread | the same |

## Golden pictures

19 new files in `app/test/ui/goldens/`. I looked at each one after `--update-goldens`.

- `garden_desktop_<theme>_light.png` for the 4 themes, `garden_desktop_grove_dark.png`, `garden_phone_grove_light.png`: a plant in the middle of its growth, with the ladder.
- `garden_desktop_grove_light_seed.png` (no finished task) and `garden_desktop_grove_light_full.png` (a full tree, no next step).
- `settings_desktop_<theme>_light_appearance.png` for the 4 themes, `settings_phone_grove_light_appearance.png`.
- `settings_desktop_grove_light_<tab>.png` for planner, notes, notifications, sync and data; `settings_desktop_grove_dark_planner.png`.

Each Settings picture also checks that no text sits on a part of a pixel (`textOffPixels(tester)` is empty).

7 old files were made again: `spread_desktop_<theme>_light.png` for the 4 themes, `spread_desktop_grove_dark.png`, `spread_narrow_grove_light.png` and `spread_phone_grove_light.png`. The header of the Day Spread has the small plant now. Nothing else changed in them.

`spread_desktop_futuristic_light.png` is still checked on macOS only (Q-17). The compare and its 0.2 % limit did not change. See "Q-17" below.

The plants in the pictures stand still: the tests run with motion off.

## Q-17

The job was to find the cause before any change to the compare. I listed each text of the futuristic Day Spread with its place, and I looked at the failure pictures of the CI. The cause is not the one of F7 and F8: no layout slip is in the red pixels. The red pixels are seams of the bold test font: the theme asks for 1.5 points between the letters of a heading, and the engine grows each bold box by about half a pixel. No number for the gap puts these edges on whole pixels, so I see no layout fix. The test stays parked on Linux and Windows. The compare and the limit did not change. The proof, with the numbers, is in the Q-17 card of `docs/questions.md` (commit `69e60e0`). The owner decides.

The owner answered Q-17 with B on 2026-10-11: the compare and the limit stay, and the picture stays skipped on Linux and Windows. Nothing was changed after the answer.

## Device test

`./scripts/flutter_integration.sh macos` on this Mac, 2026-10-11: 9 of 9 tests pass. The new test "garden and settings: the plant shows, a theme card works" opens the Garden, opens Settings from the Appearance menu, picks the Minimal theme and closes the window. The test uses a store in memory with no sync. It calls no server.

## CI

Workflow `flutter`, 4 jobs (Android emulator, Windows, macOS, iPhone simulator). Each job runs Test, Build and Integration test (9 device tests). Each push starts 2 runs: one for the push, one for the pull request.

| Commit | What | Runs | Result |
|---|---|---|---|
| `b13d99b` | F10-screens (the code is `29c9137`) and its docs | 38142084173 (push), 38142086528 (pull request) | red: the Android job only, in both runs. Windows, macOS and iOS were green |
| `18c127e` | the fix of the device test (`654e3df`) and the answer cards | 38143843863 (push), 38143846849 (pull request) | green, 4 jobs in each |
| `06e6aeb` (the last code commit) | "Add an image", web links, Export and Import | 38144801403 (push), 38144804466 (pull request) | green, 4 jobs in each: 2077 tests on macOS and iOS, 2076 and 1 skipped on Linux and Windows, 9 device tests in each |

The red runs: the step "Integration test" of the Android job failed in the test "calendar: the card of a new event saves the event". The tap on "Save" did not reach the button, because the keyboard of the emulator had made the screen shorter and the button was out of view. The unit tests and the build of that job were green. The fix is in the test only (`_tapInView` in `app/integration_test/planner_test.dart`, commit `654e3df`): it brings the button into view and then taps. The app did not change for it. Why the test passed on Android before F10-screens is not known; the timing of the keyboard is my guess. After the fix the Android job is green in 4 runs of 4.

The 1 skipped test on Linux and Windows is the picture of Q-17.

## Not done, or not sure

- No real file window and no real browser was opened: not by a test, and not by hand. "Add an image", "Export JSON…", "Import JSON…" and a click on a link must be tried on each of the 4 systems.
- Not tried: that the sandboxed Mac build can write the export file after the save window; that Android opens the browser with the new `<queries>` entries; a photo with a rotation tag; a HEIC photo from an iPhone.
- Export is not on Android and iOS (Q-27).
- A large photo is stored as a PNG. It can be 2 to 4 MB, where the Mac app stores a JPEG of some hundred KB (Q-28).
- The Import block is in the Settings screen only. The store does not refuse `importData` while signed in. The request to Track A is in `docs/tracks.md`.
- "Show data folder" and "Open System Settings" are not there. Both open an address that is not `http` or `https`, and the owner's rule for Q-16 opens no other kind. The path is shown as text with "Copy the path".
- The real permission question for notifications was not seen on any system. The tests use a fake of the reminder service.
- Real sync and a real login were not tried. The owner has not yet run the Supabase SQL file and has not yet changed the email templates. The tests of the sync card, the mark and the question use Track A's fake world. No test calls a Supabase project. I did not read `app/config/supabase.json` and did not run the app against the real project.
- The Planner tab saves a setting with `store.prefs.set` and then calls `store.setIntensity(store.intensity)` to tell the screens. The store has no call for that; a request to Track A is in `docs/tracks.md`.
- The springs of the Mac app are `Curves.easeOutBack` here (0.9 s for the Garden, 0.5 s for a leaf). The move looks alike but is not the same curve. Not compared side by side.
- No picture was compared with the Mac app side by side. The look follows the Swift sources and the theme of F6.
- Nobody looked at these screens on a real phone or on Windows. The pictures use the test font. That the six tabs fit in the 600 pt window with the real fonts is an estimate; the row scrolls when they do not.
- The device test ran on this Mac before the last change to it (`_tapInView`, commit `654e3df`). After that change it ran on the CI only: the Mac was in use, the app window could not come to the front, and I stopped the local run.
- One golden picture, the futuristic Day Spread, is not checked on Linux and Windows. The owner answered Q-17 with B on 2026-10-11: it stays so.
- The text for refused notifications says "System Settings" on each system. That string is Track A's.
- The Settings window has no licence page for the fonts yet. The licence texts are in Flutter's licence list since F6.
- The test of the small plant was written together with its code, not before it.
- New packages: `file_selector` and `url_launcher`, both with the owner's yes of 2026-10-11. No other package.
