# F12 — feature checklist of the Flutter app against PLAN.md

Checked on 2026-10-12. Branch `feat/xp-f12-close`, made from
`feat/cross-platform-flutter` at commit `3c75315`.

This file answers one question: for each feature and each rule of `PLAN.md`,
is it in the Flutter app (`app/`), and does a test or a picture really check
it? I opened the code and the tests for each row. I did not copy claims from
the other files in `docs/acceptance/`.

## What I ran

- `./scripts/flutter_test.sh` on this branch: exit 0. The format check says
  "Formatted 355 files (0 changed)". `flutter analyze` says "No issues found!".
  `flutter test` says "+2779: All tests passed!". The base
  (`feat/cross-platform-flutter`) had 2686 tests; this branch adds 93.
  No test failed.
- No golden picture changed. No new package was added.
- One test is skipped by its own code off macOS: the futuristic Day Spread
  picture (`_parked` in `app/test/ui/goldens/f9_golden_test.dart`, card Q-17).
- The device tests (`app/integration_test/planner_test.dart`, 19 tests) were
  not run on this Mac. I read them. CI for this branch has not run yet. The
  newest finished green `flutter` run on the base is run 38246026526 at commit
  `b9eeb19`. No green CI run is claimed for this branch.
- I made no call to a real Supabase project and I did not open the key file.
- The Swift app is retired in the branch `feat/xp-retire-swift` (draft PR #27,
  `docs/acceptance/retire-swift.md`). `Sources/` and `Tests/` still exist on
  this branch.

## How to read the table

- Code paths start at `app/lib/`. Test paths start at `app/test/`.
- Short names for the test files that come up often:

| Short name | File |
|---|---|
| DEV | `app/integration_test/planner_test.dart` (device tests, 19 tests, CI is set to run them on the 4 systems) |
| PC | `ui/planner/planner_close_test.dart` |
| PV | `ui/planner/planner_view_test.dart` |
| PR | `ui/planner/planner_rules_test.dart` |
| PM | `core/planner/planner_math_test.dart` |
| PS | `state/planner_store_test.dart` |
| PL | `data/database_place_test.dart` |
| TP | `ui/tasks/tasks_pane_test.dart` |
| TI | `ui/tasks/task_inspector_test.dart` |
| TM | `ui/tasks/task_motion_test.dart` |
| CB | `ui/theme/check_box_test.dart` |
| SP | `ui/tasks/store_panes_test.dart` |
| GP | `ui/goals/goals_pane_test.dart` |
| MV | `ui/calendar/month_view_test.dart` |
| EE | `ui/calendar/event_editor_test.dart` |
| NV | `ui/notes/notes_view_test.dart` |
| RT | `ui/editor/rich_text_field_test.dart` |
| DS | `ui/spread/day_spread_view_test.dart` |
| RV | `ui/shell/root_view_test.dart` |

- Pictures (golden files) are in `app/test/ui/goldens/`,
  `app/test/ui/tasks/goldens/`, `app/test/ui/goals/goldens/` and
  `app/test/ui/auth/goldens/`.

The states (only these states are used in the tables):

| State | What it means here |
|---|---|
| `proof` | A test or a picture really checks this behaviour. For a thing on the screen, the test goes through the screen (widget test, picture or device test). For a pure rule (maths, parser, data), a unit test is enough. |
| `built, no proof` | The code is there and is wired to the screen. No test goes through the screen for it. When a test checks only the rule under it, the proof cell names that test. |
| `partly` | A part is there. The row says what is missing. |
| `missing` | Not in the Flutter app, and not turned off by PLAN.md or the owner. |
| `missing (off by PLAN)` | PLAN.md itself turns it off (§0 CHOICES, or a later note in the text). |
| `missing (off by the owner)` | The owner decided it on a question card (`docs/questions.md`). |
| `not for this platform` | A rule for the Swift build of the Mac app, or a thing phones do not have. |

## The table

### §0 to §3 — choices, stack

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §0 | Layout B (Day Spread) is the one layout | `ui/spread/day_spread_view.dart` | DS "three columns: the tasks, the timeline, the note of today". DEV "today: the Day Spread opens, a tap on a task opens its panel". Pictures `spread_desktop_*.png`. | proof |
| §0 | The `AppLayout` list stays, so a layout can be added later | none | PLAN.md line 21 says there is no layout picker and no `AppLayout` list in the code. `app/lib` has no `AppLayout` list either. `ui/shell/shell_layout.dart` has `ShellLayout` (phone, desktop): that is the shape of the window, not the layouts A to D. The Mac source (`Sources/`) has no `AppLayout` either. | missing (off by PLAN) |
| §0 | Default theme is Grove | `state/store_appearance.dart` | `state/theme_store_test.dart` "the default is grove with motion on". | proof |
| §0 | App name "Grove" | `ui/app.dart` (`title: 'Grove'`), `app/macos/Runner/Configs/AppInfo.xcconfig`, `app/macos/Runner/Info.plist`, `app/ios/Runner/Info.plist`, `app/android/app/src/main/AndroidManifest.xml`, `app/windows/runner/main.cpp`, `app/windows/runner/Runner.rc` | `app_name_test.dart` group "the name on the screen is Grove": "macOS: the app in the Applications folder, the menu bar and the Dock", "iOS: the name under the icon and the name of the bundle", "Android: the name under the icon", "Windows: the title of the window and the name in Task Manager", "the app itself: the title of the window in the app switcher". The tests read the files of each system; no test starts the built app. The name on Windows: Q-40, answered B. | proof |
| §0 | Bundle id `local.grove.app` | `app/macos/Runner/Configs/AppInfo.xcconfig`, `app/android/app/build.gradle.kts`, `app/ios/Runner.xcodeproj/project.pbxproj` | The id is still `local.grove.grove`; it changes to `local.grove.app` in the branch `feat/xp-retire-swift` (cards Q-26 and Q-30, answered). Until then the Flutter app and the Mac app are two apps on a Mac, each with its own data. `app_name_test.dart` group "the id and the data folder stay" ("macOS and iOS: the bundle id", "Android: the application id") holds the id of today. | partly |
| §1 | Works with no account and no network | `data/database.dart`, `main.dart` (with no keys there is no sync) | `ui/auth/sync_card_test.dart` "a build with no keys says that there is no sync". `ui/settings/settings_sync_test.dart` "a copy with no sync: the card says so, and no mark". All store tests run on a local database only. | proof |
| §2 | Dates and times are local wall-clock text, with no time zone | `core/model/day_key.dart` | `core/model/day_key_test.dart` "wall time round trip", "adding days across a daylight saving change stays on whole days". `core/model/models_test.dart` "stamps are local seconds without a zone". | proof |
| §2 | Ids are UUID text, as in the Mac app | `core/model/ids.dart` | `core/model/models_test.dart` "new ids look like Swift UUID strings and differ". | proof |
| §2, §3, §13, §14 | Swift 6, SwiftUI, AppKit, no Xcode, no SwiftData, the Swift package layout, the Mac milestones and pitfalls | none | These are rules for the Swift build. The Flutter stack is in `docs/cross-platform-plan.md`. | not for this platform |

### §4 — data

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §4 | SQLite with WAL and foreign keys on; version number; migrations in order | `data/database.dart` (lines 58–59), `data/migrations.dart` | `data/database_test.dart` "migrations create the schema", "migrations are idempotent", "a transaction rolls back on error", "a version 1 database keeps its data", "deleting a task cascades to subtasks and blocks". No test reads the WAL setting. | proof |
| §4 | The database file is in the data folder of the app | `main.dart` (`getApplicationSupportDirectory`), `state/app_store.dart` (`AppStore.open`, the file is `grove.sqlite`) | PL "the database file is grove.sqlite in the data folder", "a data folder that is not there yet is made", "what is saved is in that file: a second launch reads it", "the backups and the settings are in the same folder". Differs: Flutter uses the app-support folder of each system. It is not the folder of the Mac app (`~/Library/Application Support/Grove/`). | proof |
| §4.1 | Tables and columns of the Mac app (lists, tasks, events, exdates, notes, links, tags, settings) | `data/migrations.dart`, `data/repos.dart` | `data/database_test.dart` "there are eight migrations: the seven of the Mac app, and one of this app only". `data/data_export_test.dart` "the file has the same rows and columns as a Mac export (schema $version)". Differs: Flutter is on schema 8 (7 is `block_subtasks`; 8 is `goal_subtasks`, of this app only, see `docs/acceptance/goal-subtasks.md`); the Mac `main` is on 6. Flutter also has sync columns ("the sync columns do not change the shared schema number"). | proof |
| §4.1 | One daily note for a day, one weekly note for a week | `data/repos.dart` | `data/database_test.dart` "a daily note is unique per day". `state/note_store_test.dart` "a weekly note uses the Monday". | proof |
| §4.1 | Full-text search, no accents | `data/search_index.dart` | `data/database_test.dart` "search finds words and prefixes", "search ignores accents and quotes". | proof |
| §4.1 (migration 2) | Images are rows in the database, so the backup and the export hold them | `data/attachment_repo.dart` | `data/attachment_repo_test.dart` "add and get round trip", "images survive the daily backup". `data/data_export_test.dart` "names its format and holds every table". | proof |
| §4.1 (migration 2) | An image is made smaller: at most 1600 px on the long side | `ui/editor/image_prepare.dart` (`imageMaxSide`, `prepareImage`, `pickedImage`), `ui/system/system_tools.dart` (`pickImageFiles`) | `ui/editor/image_prepare_test.dart` "the limit of the Mac app: 1600 pixels on the long side", "a wide PNG gets 1600 pixels of width, in the same shape", "a high PNG gets the limit as its height", "a large JPEG is made smaller too". Differs: a large picture is stored as a PNG (Q-28, answered A). The real file window (`pickImageFiles`) is in no test. | proof |
| §4.1 (migration 2) | An image in the text is `![alt](grove-image:ID)` | `core/parsing/markdown_spans.dart`, `ui/editor/` | RT "a new image goes in as markup and is stored". `core/parsing/markdown_spans_test.dart` "image hides its markup". | proof |
| §4.1 (migration 2) | An image that no text uses is deleted | `data/attachment_repo.dart` (`sweepOrphans`), `state/app_store.dart`, `state/store_data.dart` | `data/attachment_repo_test.dart` "sweep removes old unreferenced images only", "an image stays when another body still uses it". `state/daily_backup_test.dart` "a new copy also drops the old images that no text uses". Differs: the clean-up runs at launch and with the daily copy, and keeps fresh images. PLAN says at each save. | proof |
| §4.2 | `DayKey`, `WallTime`, `RecurrenceRule`; minutes since midnight | `core/model/` | `core/model/day_key_test.dart`, `core/model/models_test.dart`. | proof |
| §4.3 | Database wrapper, one repo per table, each write updates the search | `data/database.dart`, `data/repos.dart` | `data/database_test.dart` "task CRUD", "events in range and series", "tags are case-insensitive and replaceable", "links replace and backlink", "settings round trip". `data/reference_indexer_test.dart` "search sees words, not ids or markup". | proof |
| §4.4 | Daily backup at launch; the newest 14 stay | `data/backup.dart`, `services/backup_schedule.dart` | `data/database_test.dart` "the daily backup is made once and trimmed". `state/daily_backup_test.dart` "only the newest 14 copies stay". Differs: Flutter also checks while the app stays open (`services/backup_schedule_test.dart` "the timer checks while Grove stays open over midnight"). | proof |
| §4.4 | Settings ▸ Data: "Export JSON…" with all tables | `ui/settings/settings_tabs.dart` (`DataSettings`, key `settings-export`), `ui/system/system_tools.dart`, `data/data_export.dart`, `state/store_data.dart` | `ui/settings/settings_view_test.dart` "Export saves all data under the name of today", "Export: a closed window says nothing, an error says why", "a file window: Export and Import show", "a system with no save window: Import shows, Export does not". Rule: `data/data_export_test.dart` "names its format and holds every table"; `state/settings_test.dart` "a store exports and another one imports". Differs: no Export on Android and iOS (Q-27, answered B). The tests use a fake file window; the real save window is in no test. | proof |
| §4.4 | Settings ▸ Data: "Import JSON…" replaces all data after a question | `ui/settings/settings_tabs.dart` (`DataSettings`, key `settings-import-question`), `ui/system/system_tools.dart`, `data/data_export.dart`, `state/store_data.dart` | `ui/settings/settings_view_test.dart` "Import asks first, and "Cancel" changes nothing", "Import replaces the data and keeps a copy of the old", "Import: a wrong file changes nothing", "Import: no folder for the copy, so nothing changes", "Import: a closed file window does nothing". `ui/settings/settings_sync_test.dart` group "Import and the sync": "signed in: Import is blocked, and Grove says why". Rule: `data/data_export_test.dart` "import replaces what was there", group "JSON from the Mac app", group "bad files change nothing". Open card Q-22: sign out, import, sign in replaces the rows of the account with no question. | proof |
| §4.4 | Settings ▸ Data: "Show data folder" | `ui/settings/settings_tabs.dart` (`DataSettings`), `ui/system/system_tools.dart` | `ui/settings/settings_view_test.dart` ""Show data folder" asks the system for the folder", "the system does not open the folder: the window says so", "no "Show data folder" on a phone, with no file windows and with no folder", "the folder, and a copy of its path". The system is a fake in the tests. | proof |

### §5.1 — Day Planner

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.1 | Planner screen is a fixed week; Today is the timeline of today; no mode picker | `ui/planner/planner_kind.dart`, `ui/planner/planner_view.dart` | `ui/planner/planner_kind_test.dart` "the week has 7 days and starts on Monday", "today shows only today". PV "shows the week, the hours and the now line". DS "the screen keeps its own day: today, or tomorrow" (since 2026-10-12 a switch in the header of Today shows only tomorrow: `docs/acceptance/today-tomorrow.md`). | proof |
| §5.1 | Previous, Next and Today in the header | `ui/planner/planner_view.dart` (`_goToday`, key `planner-today`) | PC '"Previous" moves one week back'; '"Previous" moves one day back on a phone'. PV "Previous and Next move one week" taps Next and Today. | proof |
| §5.1.1 | Grid maths: minute to point and back; the grid is 00:00–24:00 | `ui/planner/planner_geometry.dart` | PR "minutes and points", "day columns start on whole points and fill the grid". | proof |
| §5.1.1 | Zoom stays between 36 and 160 points for an hour | `ui/planner/planner_geometry.dart` | PR "zoom stays in its range". `ui/planner/planner_paths_test.dart` "an hour is never lower than 36 or higher than 160". | proof |
| §5.1.1 | Pinch to zoom | `ui/planner/planner_grid.dart` (`_trackpadPinch`, and the scale gesture of two fingers) | `ui/planner/planner_pinch_test.dart` group "a pinch on a trackpad": "fingers apart make the hours taller", "the zoom stops at 36 and at 160"; group "a pinch with two fingers on a phone": "fingers apart make the hours taller". DEV "pinch: two fingers apart make the hours taller". | proof |
| §5.1.1 | On open and on "Today" the grid scrolls to now minus 1 hour | `ui/planner/planner_grid.dart` (`_nowTarget`, `scrollToNow`), `ui/planner/planner_view.dart` (`_goToday`) | PC "on open the grid starts one hour above now", "a later hour starts lower", '"Today" scrolls back to one hour above now'. | proof |
| §5.1.1 | Hour lines, half-hour lines, hour labels | `ui/planner/planner_grid.dart` | PV "shows the week, the hours and the now line". Pictures `planner_desktop_*.png`. | proof |
| §5.1.1 | Faint tint for working hours (09–18) | `ui/planner/planner_grid.dart` (line 1340: `ColoredBox`, alpha 0.045, 4.5 % of the accent) | PC "the tint covers 09:00 to 18:00 when nothing is set", "the tint covers the hours of the settings". The pictures cannot show the tint: the picture check allows 12 of 255 for each colour (`app/test/ui/support.dart`). | proof |
| §5.1.1 | Now line: 2 points, a dot, a slow pulse when motion is on | `ui/planner/planner_grid.dart` (`_NowLine`) | PV "shows the week, the hours and the now line". `ui/theme/theme_math_test.dart` "the now line pulses between 1 and 0.45 in 3.2 seconds". `ui/planner/planner_now_line_test.dart` "the pulse goes from 1 to 0.45 and back in 3.2 seconds", "$mode: the line is at the minute of the clock, and moves with it". Open card Q-37: keep the pulse or not. | proof |
| §5.1.1 | Past time of today is faded | `ui/planner/planner_grid.dart` (key `past-shade`) | `ui/planner/planner_now_line_test.dart` "$mode: the faded past ends at the line". | proof |
| §5.1.2 | A block shows its time, title and length; long text is cut; a short block has one line | `ui/planner/block_view.dart` | PR "a block gives lines to the title and to the summary". Pictures `planner_desktop_*.png`, `planner_phone_grove_light.png`. | proof |
| §5.1.2 | A task block has a check box; a click finishes the task | `ui/planner/block_view.dart` | PV "the check box marks the task done". | proof |
| §5.1.2 | A small ✎ icon when the block has linked notes | `ui/planner/block_view.dart` (`_noteIcon`), `state/store_planner.dart` (`hasNote`) | `ui/planner/planner_note_icon_test.dart` "a block with a linked note shows the note icon", "a block with no linked note shows no icon". `ui/planner/planner_linked_note_test.dart` "the pencil comes with the note and goes with it". Picture `ui/planner/goldens/planner_linked_note_grove_light.png`. The linked note is the note of the block (Q-35, answered A). Open card Q-36: a rename or a move loses the note. | proof |
| §5.1.2 | A done block is faded and struck through | `ui/planner/block_view.dart` (line 264 strikes the title, line 169 fades the block to 55 %) | PC "is faded and its title is struck", "a block fades when its check box is ticked". | proof |
| §5.1.2 | Event: fill at 16 % and a 3-point left border. Task block: fill at 10 %, dashed 1-point border and a 3-point left border | `ui/planner/block_view.dart` (line 111 `block.isTaskBlock ? 0.10 : 0.16`, line 151 the dashed border) | The fills: pictures. They match PLAN.md (corrected 2026-10-12). The borders: PC group "the border of a block": "a task block has dashes, an event has none", "a task block with a priority has a full border in the colour of the priority, and no dashes", "a done block with a priority has the dashes again". PLAN.md §5.1.2 says the priority border since 2026-10-12. The Mac source does the same (`Sources/Grove/Planner/BlockView.swift`). | proof |
| §5.1.2 | Subtasks in a task block: rows, "+3 more", "1/4 subtasks", "1/4" in the title row | `ui/planner/block_view.dart` | PV "a tall block shows subtasks, then "+N more"", "a short block shows a count of the subtasks". PR group "rows of a block with subtasks" (9 tests). | proof |
| §5.1.2 | All-day events are in a strip above the grid | `ui/planner/planner_view.dart` (`_allDayStrip`) | `ui/planner/planner_paths_test.dart` group "the all-day strip": "an all-day event is in the strip, not on the grid", "with no all-day event in the week there is no strip", "a click on the event opens its card", "a phone shows the all-day events of its one day". Store: `state/recurring_event_store_test.dart` "a repeating all-day event shows in the all-day row". | proof |
| §5.1.2 | A day of a repeating event has its own id | `state/store_events.dart` | `state/recurring_event_store_test.dart` "an occurrence can be found by id". `core/recurrence/recurrence_test.dart` group "occurrence ids and events". | proof |
| §5.1.3 | Overlaps are always allowed and both blocks are in view | `core/planner/planner_layers.dart` | PS "overlap is allowed". PV "two blocks at the same time are both in view". DEV "overlap: two blocks at the same time are both in view". | proof |
| §5.1.3 | Overlapping blocks are layers: one over the other, not side by side | `core/planner/planner_layers.dart` (class `Layer`), `core/planner/planner_math.dart` (`PlannerMath.layoutLayers`, line 148) | PM group "layout (overlaps cascade, they never share the width)". The Mac source does the same (`Sources/GroveCore/Planner/PlannerLayers.swift`). Differs: PLAN.md §5.1.3 also says `layoutColumns` stays in `PlannerMath`. That function is not in `app/lib`. | proof |
| §5.1.3 | A layout change moves with an animation; at once when motion is off | `ui/planner/planner_grid.dart` (`AnimatedPositioned`, duration 220 ms, `Curves.easeOutCubic`, lines 1458–1464) | PC "moves a block with an animation of 220 ms", "with motion off the block is at its new place at once", "both end at the same place". Differs: PLAN.md §5.1.3 (line 451) still says a spring of 0.28 s. The code is 220 ms ease-out. | proof |
| §5.1.4 | Drag on empty time makes a draft; on release a title field opens; a new task and block are made | `ui/planner/planner_grid.dart`, `state/store_planner.dart` | PV "a mouse drag on empty time makes a block", "a short drag makes 30 minutes; the start snaps to 15". DEV "create: a drag on empty time makes a block". PS "a draft creates a task and a block, and undo removes both". | proof |
| §5.1.4 | Esc cancels the draft | `ui/planner/inline_title_field.dart` | PV "Escape closes the draft and saves nothing". | proof |
| §5.1.4 | A typed title that matches an open task offers "Schedule existing task" | `ui/planner/planner_grid.dart` (line 1604) | `ui/planner/planner_paths_test.dart` group ""Schedule existing task"": "two letters show the open tasks with that name, three at most", "a click on a task gives it the time of the draft and makes no new task", "Return with the same letters makes a new task", "a task that has a time on this day is not in the list". | proof |
| §5.1.4 | ⌘ held at release makes a plain event | `ui/planner/planner_grid.dart` (`_createEnd`) | `ui/planner/planner_paths_test.dart` group "the command key": "held at the end of a drag on empty time, it makes an event", "let go before the end of the drag, it makes a task". DEV "the command key at the end of a drag on empty time makes an event". Store: PS "a draft as event makes a plain event". | proof |
| §5.1.4 | Double click on empty time makes a 30-minute draft | `ui/planner/planner_grid.dart` (`_columnTapped`) | `ui/planner/planner_menu_test.dart` group "clicks": "a double click on empty time starts a block of 30 minutes", "two slow clicks on empty time start nothing", "a double tap with a finger on empty time starts a block". DEV "double tap: two taps on empty time start a block of 30 minutes". | proof |
| §5.1.4 | A task dragged from a list onto the grid gets a block; the length is its estimate, at least 15 minutes | `ui/planner/payload_drag.dart`, `ui/planner/planner_grid.dart` | SP "a task dragged from the panel onto a day gets a block". PS "a task dropped from the tray uses its estimate", "a short estimate makes a block of at least fifteen minutes". | proof |
| §5.1.4 | A task dragged over the grid: the day under the pointer gets a tint. No ghost with the time (PLAN.md §5.1.4) | `ui/planner/payload_drag.dart` (`_Feedback`), `ui/planner/planner_grid.dart` (`_targetedDay`, lines 1314–1345, tint alpha 0.10) | PC "a task held over a day tints that day and no other, and the drop makes the block". The label that follows the pointer shows the task title (`ui/planner/sticky_strip.dart` line 503), not a time; no test reads that label. The block shows at the drop. | proof |
| §5.1.4 | A sticky note dragged onto the grid gets that time | `ui/planner/sticky_strip.dart` | PV "a note dragged onto the grid gets that time". | proof |
| §5.1.4 | Drag the body of a block to move it; the database is written only at the end | `ui/planner/planner_grid.dart` | PV "a mouse drag moves a block and snaps to 15 minutes", "the label shows the new time during the drag" (the store has the old time until the pointer goes up). DEV "drag: a block moves to a new time and to the next day". | proof |
| §5.1.4 | Live label `11:15 – 12:45 · 1h 30m` during a drag | `ui/planner/planner_grid.dart` (key `live-label`), `core/planner/planner_math.dart` | PC "shows the new times and the length during a move" (reads "11:15 – 12:45 · 1h 30m"), "shows the new end and the new length during a resize". PM group "label" checks the words. | proof |
| §5.1.4 | A drag to the side moves the block to another day | `ui/planner/planner_grid.dart` | PV "a drag to the side moves a block to the next day". DEV "drag: a block moves to a new time and to the next day". | proof |
| §5.1.4 | Drag the top edge: the start changes | `ui/planner/block_view.dart` | PV "the top edge changes the start; 15 minutes is the least". | proof |
| §5.1.4 | Drag the bottom edge: the end changes | `ui/planner/block_view.dart` | PV "the bottom edge changes the end". DEV "resize: the bottom edge changes the end". | proof |
| §5.1.4 | The pointer shows a resize arrow on an edge | `ui/planner/block_view.dart` (line 607, `SystemMouseCursors.resizeUpDown`) | PC "is the resize pointer over the top and the bottom edge of a block". | proof |
| §5.1.4 | Snap is 15 minutes, always | `core/planner/planner_math.dart` | PV "a mouse drag moves a block and snaps to 15 minutes". PM groups "snap" and "the 15 minute grid". | proof |
| §5.1.4 | At least 15 minutes; a block stays inside the day | `core/planner/planner_math.dart` | PM groups "clamp" and "resize". PV "the top edge changes the start; 15 minutes is the least". PS "a block that ends at midnight round trips". | proof |
| §5.1.4 | ⇧ held at release pushes the later blocks down (ripple), with a "pushed 2 blocks" message | `ui/planner/planner_grid.dart` (`_blockDragEnd`), `state/store_planner.dart` | `ui/planner/planner_paths_test.dart` group "Shift at the end of a drag": "a move pushes the blocks under it and says how many" (reads "Pushed 2 blocks"), "one pushed block: the message has no "s"", "with no Shift nothing is pushed and nothing is said". DEV "Shift at the end of a drag pushes the next block down". Store and maths: PS "ripple pushes later blocks"; PM group "ripple". | proof |
| §5.1.4 | A block released over the sticky strip loses its time; the task stays | `ui/planner/sticky_strip.dart` | PV "a task block dragged up to the strip loses its time". | proof |
| §5.1.4 | A block dragged onto a day of the week strip or the month moves to that day | none | Not built (PLAN.md §5.1.4, corrected 2026-10-12). A month day takes a task, not a block (`ui/calendar/month_view.dart` lines 251–256, `DragPayload.taskPrefix`). | missing (off by PLAN) |
| §5.1.4 | The grid scrolls by itself when a drag is near the top or the bottom | `ui/planner/planner_grid.dart` (`_startAutoScroll`) | `ui/planner/planner_paths_test.dart` group "auto-scroll": "a block held near the bottom edge scrolls the grid and goes with it", "the scroll is faster nearer to the edge", "a block held near the top edge scrolls the grid up", "the grid stops at the end of the day". | proof |
| §5.1.4 | A click selects a block | `ui/planner/planner_grid.dart` | PV "a press on a block does not start a new block" (the selection is that block). `ui/planner/planner_menu_test.dart` group "clicks": "a click on an event selects it and opens its card", "a click on empty time clears the selection". The look of the outline is in no test. | proof |
| §5.1.4 | A click on an event block opens its card | `ui/calendar/event_editor.dart` | EE "a click on an event of the planner opens its card, and the keys stay with the planner". | proof |
| §5.1.4 | A click on a task block opens the panel of the task | `ui/planner/planner_grid.dart`, `state/store_planner.dart`, `ui/tasks/task_inspector.dart` | `ui/planner/planner_menu_test.dart` group "clicks": "a click on a task block selects it and shows the task at the side". Store: `state/task_description_test.dart` "a click on a task block opens its panel". | proof |
| §5.1.4 | ⌘-click selects more blocks; a drag moves all of them | `ui/planner/planner_grid.dart` | `ui/planner/planner_paths_test.dart` group "more than one block": "a click with the command key adds a block to the selection and takes it out again", "a drag of one selected block moves all of them the same way". DEV "two blocks: a command-click adds a block, a drag moves both". Store: `state/task_description_test.dart` "an extending click builds a selection and leaves the panel alone". | proof |
| §5.1.4 | Right-click menu: Duration, Colour, Duplicate, Split in two, Mark done, Unschedule, Delete | `ui/planner/planner_grid.dart` (`_openMenu`) | `ui/planner/planner_menu_test.dart` group "the menu of a block": "a right click on a task block shows its lines", "a right click on an event shows its lines", ""Duration" gives the block a new length", ""Colour" gives the block a colour of the theme", ""Duplicate" puts a copy right after the block", ""Split in Two" cuts the block in the middle", ""Mark Done" checks the task off; "Mark Not Done" opens it again", ""Unschedule" takes the time away; the task stays as a sticky note", ""Delete Task" removes the block and the task", ""Delete Event" removes the event", "a long press with a finger opens the menu". DEV "menu: a long press or a right click opens the menu of a block". Store: PS "duplicate, split and duration", "a block shorter than half an hour cannot split", "unschedule keeps the task and returns it to the tray". | proof |
| §5.1.4 | Menu line "Open / create linked note" | `ui/planner/planner_grid.dart` (`_openMenu`: "Open Linked Note", "Create Linked Note") | `ui/planner/planner_linked_note_test.dart` group "the menu line of the linked note": "$kind: the line makes the note and shows it", "$kind: with a note, the block has the pencil and the line opens the same note", "the line is after "Split in Two", as in the plan". Store: `state/block_note_store_test.dart`. | proof |
| §5.1.4 | A day of a repeating event that is moved or resized asks "This event only / All events" | `ui/planner/planner_view.dart`, `ui/planner/planner_dialogs.dart` ("This event only", "All events") | `ui/planner/planner_paths_test.dart` group "a repeating event": "a drag asks: this day only, or all days", ""This event only" moves that day and keeps the others", ""All events" moves every day of the event", ""Cancel" puts the block back", "a new length asks with the word "Resize"". Store: `state/recurring_event_store_test.dart` group "move and resize". | proof |
| §5.1.4 | A small tick is felt each time the snap value changes | `ui/planner/planner_grid.dart` (`HapticFeedback.selectionClick`, lines 536 and 612) | PC "a phone ticks once at each snap of a move", "a phone ticks at each snap of a resize". | proof |
| §5.1.5 | `snap`, `clampMove`, `resizeTop`, `resizeBottom`, `ripple`, `firstFreeSlot`, `label` are unit-tested | `core/planner/planner_math.dart` | PM groups "snap", "clamp", "resize", "the 15 minute grid", "ripple", "free slot", "label". | proof |
| §5.1.6 | ↑ / ↓ move the block by 15 minutes | `ui/planner/planner_grid.dart` | PV "the arrows move the selected block". | proof |
| §5.1.6 | ⇧↑ / ⇧↓ change the length | `ui/planner/planner_grid.dart` | PV "Shift with an arrow changes the length". | proof |
| §5.1.6 | ← / → move the block to the day before or after | `ui/planner/planner_grid.dart` | PV "the arrows move the selected block". | proof |
| §5.1.6 | Return renames | `ui/planner/inline_title_field.dart` | PV "Enter renames a task block". | proof |
| §5.1.6 | Space marks the task done or not done | `ui/planner/planner_grid.dart` (line 990) | `ui/planner/planner_paths_test.dart` group "keys": "Space marks the selected task block done and open again". | proof |
| §5.1.6 | ⌘D makes a copy right after | `ui/planner/planner_grid.dart` (line 863) | `ui/planner/planner_paths_test.dart` group "keys": "the command key with D puts a copy after the block", "D with no command key copies nothing". Store: PS "duplicate, split and duration". | proof |
| §5.1.6 | Delete takes the block away, with undo | `ui/planner/planner_grid.dart` | PV "Delete removes the block; Escape clears the selection". `ui/planner/planner_paths_test.dart` "Delete removes all selected blocks in one step". | proof |
| §5.1.6 | ⌘T goes to today | `ui/shell/root_view.dart` | RV "Ctrl with a number opens a screen", "on a Mac the key is Command". `state/clock_store_test.dart` "View ▸ Today goes to the day of the clock". DS "the key of "Today" goes back to today". The scroll to "now" is in PC (see §5.1.1). | proof |
| §5.1.6 | ⌘+ / ⌘- zoom; "Zoom in" and "Zoom out" buttons in the header | `ui/planner/planner_grid.dart` (lines 865–869), `ui/planner/planner_view.dart` (lines 573–581) | `ui/planner/planner_paths_test.dart` group "zoom": "the command key with + and - changes the height of an hour", "the keys of the number pad zoom too", "the buttons "Zoom in" and "Zoom out" change the height of an hour". | proof |
| §5.1.6 | N starts a block in the next free time | `ui/planner/planner_grid.dart` | PV "N starts a new block in the next free time". `state/clock_store_test.dart` "the next gap starts at the minute of the clock on its day". | proof |
| §5.1.6, §1.1 | ⌘Z and ⇧⌘Z undo and redo a planner change | `ui/store_app.dart`, `state/mutation.dart` | PV "Undo puts a moved block back; Redo moves it again", "Undo removes a new block". DEV "undo: Undo puts a moved block back; Redo moves it again". | proof |
| §5.1.7 | Sticky strip under the day numbers: the tasks of the day with no time, each with its length | `ui/planner/sticky_strip.dart`, `ui/planner/sticky_rules.dart` | PV "the strip shows the task of the day as a sticky note". PS "timeless tasks are the day tasks with no block". PR group "StickyRules". | proof |
| §5.1.7 | The strip can fold | `ui/planner/sticky_strip.dart` | PV "the strip shows the task of the day as a sticky note" (folds, says "1 with no time", the choice is saved). | proof |
| §5.1.7 | A task from a list dropped on a day is planned for that day with no time | `ui/planner/sticky_strip.dart` (the drop target `sticky-cell-<day>`, line 318), `state/store_planner.dart` (`dropTask`) | PC "a task dropped on the strip of a day gets that day and no time", "a task from the list at the side can be dropped there too". PS "a drop on the day strip plans the day with no time and removes the old block", "a strip drop is one undo step that brings back the block". | proof |
| §5.1.7 | A click on a sticky note opens the task | `ui/planner/sticky_strip.dart` (line 506) | PC "a click on a sticky note opens the task". | proof |
| §5.1.7 | "Fit" puts the task in the next free time | `ui/planner/sticky_strip.dart`, `state/store_planner.dart` | PV "the fit button gives the task the next free time". PS "fit uses the first free gap", "fit replaces the old block". | proof |
| §5.1.7 | The new block grows in after "Fit" | `ui/planner/planner_grid.dart` (`_GrowIn`, 220 ms) | `ui/planner/planner_fit_test.dart` "the block of "Fit" grows in", "with motion off the block is there at once", "a block that is made by a drag does not grow in". | proof |
| §5.1.7 | "Plan my day": a list first, Apply or Cancel, one undo step | `ui/planner/planner_dialogs.dart`, `state/store_planner.dart` | PV "the list shows the plan; Apply makes the blocks", "with nothing to plan, a short message shows". PS "plan my day orders by priority". PC "Cancel closes the list and changes nothing". | proof |
| §5.1.7 | Day totals in the header: "4h 30m planned · 2h 10m free · 3/6 done" | `ui/planner/planner_view.dart` (line 374), `ui/planner/workload.dart` (`WorkloadBar`) | `ui/planner/planner_paths_test.dart` group "the day totals": "the header shows planned time against the daily limit", "the pointer over the bar shows the numbers of the day", "the totals follow a change on the grid". Differs: the header shows a bar with the planned time against the limit; the line of PLAN shows when the pointer is over the bar, and its words are "… free in working hours …". The Mac source does the same (`Sources/Grove/Planner/PlannerView.swift`). | proof |
| §5.1.7 | Card for yesterday: "Move to today / Leave" | `ui/tasks/notice_cards.dart`, `state/store_roll_over.dart` | TP "the card of yesterday moves the open tasks to today", ""Leave" closes the card of yesterday". `state/roll_over_store_test.dart` (9 tests). | proof |
| §5.1.7 | Focus: "Start focus" in the menu of a block | `ui/planner/planner_grid.dart` (`_openMenu`), `state/store_focus.dart` | `ui/planner/planner_focus_test.dart` ""Start Focus" in the menu of a block shows the timer", "the menu says "Stop Focus" while the session runs". DEV "focus: "Start Focus" shows the timer; the cross stops it". Store: `state/focus_store_test.dart` "starting focus counts down to the end of the block". Differs: the line is in the menu of a task block only, not of an event, as in the Mac source (`Sources/Grove/Planner/PlannerGrid.swift`). | proof |
| §5.1.7 | Focus: a floating small timer counts down | `ui/planner/focus_card.dart`, `ui/store_app.dart` | `ui/planner/planner_focus_test.dart` "the timer counts down each second", "the card is 230 wide, 16 from the bottom right corner". `ui/shell/focus_host_test.dart` group "the focus timer in the window". Pictures `ui/planner/goldens/focus_card_grove_light.png`, `ui/planner/goldens/focus_card_futuristic_dark.png`. | proof |
| §5.1.7 | Focus: "Mark done?" when the time is up | `ui/planner/focus_card.dart`, `state/store_focus.dart`, `services/system_notifier.dart` | `ui/planner/planner_focus_test.dart` "at the end of the block the card asks "Mark done?"", ""Mark done" checks the task off and closes the card", ""Not yet" closes the card and the task stays open". Picture `ui/planner/goldens/planner_focus_done_grove_light.png`. Store: `state/focus_store_test.dart` "starting focus sends the end notification", "when the time is up the session asks to mark done", "the notification button marks the task done" (the system is a fake). | proof |

### §5.2 — Tasks

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.2 | Buckets: inbox, day, week, someday | `core/model/`, `data/repos.dart` | `data/database_test.dart` "task queries by bucket". `state/task_store_test.dart` "moving to a week sets the Monday". | proof |
| §5.2 (2026-10-09) | The Today page lists the tasks of today only, with "1 of 2 done" | `ui/tasks/tasks_pane.dart` | TP "an empty day says so", "Return in the quick-add field adds a task to today", "a click on the check box marks the task as done" (reads "1 of 2 done"). | proof |
| §5.2 (2026-10-09) | Three left panels (Notes, Tasks, Goals) from a dock on Today and Planner; one is open at a time | `ui/shell/left_dock.dart` | RV "the dock is on Today and the Planner only", "a dock button opens its panel beside the screen". `ui/shell/shell_model_test.dart` "a click on another panel replaces the open one". | proof |
| §5.2 (2026-10-09) | The Tasks panel lists only late tasks and tasks with no day | `ui/tasks/tasks_pane.dart`, `state/rules/` | TP "late tasks come first, then the tasks with no day", "quick-add puts the task in the inbox", "the tasks checked off today can be opened again". | proof |
| §5.2 (2026-10-09) | A task dropped on the planner keeps one block, at the new time | `state/store_planner.dart` | PS group "one block per task" (11 tests). SP "a task dragged from the panel onto a day gets a block". | proof |
| §5.2 (2026-10-09) | A new task is kept when the user clicks away with no Enter | `ui/tasks/quick_add_field.dart` (`_focusChanged`) | TP "a new task is kept when the person clicks away" (checks the task is kept, the text is cleared and the row shows), "a click away from an empty field adds no task". | proof |
| §5.2 | Week view of tasks: 7 day columns and "Anytime this week" | none | Used by Layout C and the "This Week" item of Layout A. Both are off by §0. | missing (off by PLAN) |
| §5.2 | Row: check box, title, chips for list, time, due, length, repeat, note, tags | `ui/tasks/task_row.dart` | TP "the labels of a row" (reads the length, "due Fri 9 Oct", "Notes" and the tag "#work"), "the chips of a row: its list, its time block and "Repeats"" (checks the icons), "a click on the check box marks the task as done". Pictures in `app/test/ui/tasks/goldens/` (14). | proof |
| §5.2 | Priority is a coloured 3-point bar on the left | `ui/tasks/task_row.dart` | Pictures in `app/test/ui/tasks/goldens/`. Differs: a full coloured outline, not a bar. The Mac source does the same (`Sources/Grove/Tasks/TaskRow.swift`), and `docs/cross-platform-plan.md` F8 says "priority outline". | proof |
| §5.2 | Row menu and row drags (move, priority, rename, delete) | `ui/tasks/task_row.dart` | TP "the menu of a row moves the task", "the menu sets the priority", "the menu renames and deletes". | proof |
| §5.2 | Task panel: title, list, tags, priority, day, due, length, repeat | `ui/tasks/task_inspector.dart` | TI "the fields of the task", "Return in the title renames the task", "the row of buttons moves the task", "priority", "length", "due date: add and remove", "repeat", "list", "tags: add and remove". | proof |
| §5.2 | Task panel: subtasks with a name, a description, a length and a done box | `ui/tasks/task_inspector.dart` | TI group "subtasks" (6 tests). TP "subtasks: add, count, check and hide". | proof |
| §5.2 | Task panel: "Linked here" and "Created from note X" | `ui/tasks/task_inspector.dart` | TI "the note the task came from, and the items that link to it". | proof |
| §5.2 | Rich task body: the same editor as notes (lists, headings, bold, `[[` mentions, images) | `ui/tasks/task_inspector.dart`, `ui/editor/rich_text_field.dart` | TI "the description is the editor with its row of buttons", "a button of the row changes the description, and the change is saved", "[[ opens the list, with no row for the task itself, and a pick makes a link", "in the app, which gives the window to pick a picture, the description has "Add an image"", "the description is saved after a short stop". | proof |
| §5.2 | Lists in the editor: `-` bullets and `1.` numbered lists; Return goes on with the list; Tab and Shift+Tab indent | `core/parsing/markdown_edit.dart`, `ui/editor/rich_text_field.dart` | RT "Return continues a bullet list", "Return on an empty bullet ends the list", "Tab indents a list item, Shift-Tab takes it back", "the other buttons write their marks" (presses "Numbered list"). `core/parsing/markdown_edit_test.dart`. | proof |
| §5.2 | A task can be mentioned: `[[Title]]`, stored as `[[Title\|ID]]`; the id wins, then the exact title | `data/reference_indexer.dart`, `core/parsing/reference_parser.dart` | `data/reference_indexer_test.dart` group "resolving and canonical text" (11 tests). | proof |
| §5.2 | A mention hides its id; a click opens the task; a deleted target is struck out | `ui/editor/markdown_controller.dart` | RT "the id and the brackets of a mention are not seen", "a click on a mention opens it", "a mention of a thing that is gone is struck out". | proof |
| §5.2 | A rename rewrites the mention in every text | `data/reference_indexer.dart` | `data/reference_indexer_test.dart` "a rename rewrites every body that links". `state/task_store_test.dart` "body mentions become links and renames follow". | proof |
| §5.2 | A task dragged into a note puts a mention there | `ui/editor/rich_text_field.dart` | RT "a dropped task becomes a mention". The body of a task is the same editor now, so it takes the drop too. | proof |
| §5.2 | Quick-add field with chips that show what was understood | `ui/tasks/quick_add_field.dart` | TP "Return in the quick-add field adds a task to today", "a date in the text sends the task there and says so", "the field shows what the parser understood". | proof |
| §5.2 | Quick add with ⌘N from any place | `ui/shell/app_menus.dart` (line 168), `ui/store_app.dart`, `ui/tasks/quick_add_field.dart` (`_takeRequest`) | `ui/shell/app_menus_test.dart` group "the keys": "after Ctrl and N the quick-add field has the cursor" (the cursor is there; Return makes the task), "on the Planner Ctrl and N opens the Tasks panel, and its field has the cursor", "Ctrl and N a second time: the field has the cursor again", "on a Mac Command and N, and the line "New Task", put the cursor in the quick-add field". `state/left_dock_test.dart` "New Task on the Planner opens the Tasks panel". | proof |
| §5.2, §5.7 | Quick add in the menu bar | `services/tray_service.dart` | `services/tray_service_test.dart` ""New task" shows the window and asks for the quick-add box", 'after "New task" the quick-add field has the cursor' (checks the primary focus). Q-7, answer A: the tray is a system menu with a line "New task" and no text field; the line opens Grove with the cursor in the add box. PLAN.md §5.7 has a note about this since 2026-10-12. | proof |
| §5.2 | Parser: dates (`today`, `tmr`, `mon`, `next week`, `3 oct`, `3/10`, `in 3 days`) | `core/parsing/quick_add_parser.dart` | `core/parsing/quick_add_parser_test.dart` group "dates". | proof |
| §5.2 | Parser: a time makes a block (`6pm`, `18:00`, `at 9`) | `core/parsing/quick_add_parser.dart`, `state/store_tasks.dart` | `core/parsing/quick_add_parser_test.dart` group "times and lengths". `state/task_store_test.dart` "quick add makes task and block, and undo removes all". | proof |
| §5.2 | Parser: length (`for 45m`, `for 1h30`, `90m`) | `core/parsing/quick_add_parser.dart` | `core/parsing/quick_add_parser_test.dart` group "times and lengths". | proof |
| §5.2 | Parser: `#tag`, `!1` to `!3`, `/list` | `core/parsing/quick_add_parser.dart` | `core/parsing/quick_add_parser_test.dart` group "tags, priority, lists". | proof |
| §5.2 | Parser: repeats (`every day`, `every mon`, `every 2 weeks`) | `core/parsing/quick_add_parser.dart` | `core/parsing/quick_add_parser_test.dart` group "repeats". | proof |
| §5.2 | Parser: `due fri` is a deadline, not a plan day | `core/parsing/quick_add_parser.dart` | `core/parsing/quick_add_parser_test.dart` group "deadlines". | proof |
| §5.2 | Parser: the words it understood leave the title; other words stay | `core/parsing/quick_add_parser.dart` | `core/parsing/quick_add_parser_test.dart` groups "plan examples", "plain text", "everything together". | proof |
| §5.2 | A repeating task that is finished makes the next one | `state/store_tasks.dart` | `state/task_store_test.dart` "completing a repeating task makes the next one", "a late repeating task never gets a date in the past", "reopening a repeating task does not make another copy". | proof |
| §5.2 | Change the order by a drag in a list | `ui/tasks/tasks_pane.dart` | TP "a row dropped on a row goes in front of it", "a row dropped on the end of the list goes last", "a finger drags a row after a long press". | proof |
| §5.2 | Finishing a task stores the time | `state/store_tasks.dart` | `state/clock_store_test.dart` "a task checked off gets the time of the clock". | proof |

### §5.3 — Calendar

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.3 | Month: 6 weeks of 7 days, with the day number; Previous, Next, Today | `ui/calendar/month_view.dart` | MV "the month shows six weeks from Monday", "the week starts on Sunday when the setting says so", "Previous, Next and Today move by a month", "today has its number on the accent colour". Pictures `calendar_*.png` (6). | proof |
| §5.3 | A day shows its events and "+n" for the rest | `ui/calendar/month_view.dart` | MV "a day shows its events, with the time of a timed event", "events that do not fit are counted". | proof |
| §5.3 | Dots for open tasks (up to 3) and a leaf for a daily note | `ui/calendar/month_view.dart` | MV "a day shows a dot for each open task, up to three, and a leaf for a note". | proof |
| §5.3 | A click on a day opens that week in the Planner | `ui/calendar/month_view.dart` | MV "a click on a day opens the Planner on that week". | proof |
| §5.3 | A double click on a day starts an all-day event | `ui/calendar/month_view.dart` | MV "a double click on a day starts an all-day event". | proof |
| §5.3 | A task can be dropped on a day (a block and a note cannot, PLAN.md §5.3) | `ui/calendar/month_view.dart` (lines 251–256) | MV "a task can be dropped on a day" (also reads that a note is not taken). | proof |
| §5.3 | Week strip: Mon–Sun with dots, ‹ ›, today in the accent colour | none | Not built (PLAN.md §5.3, corrected 2026-10-12). The Mac source has no week strip either. | missing (off by PLAN) |
| §5.3 | The Calendar screen is the month only | `ui/store_app.dart` (line 161, `PlannerKind.month`), `ui/planner/planner_view.dart` | DEV "calendar: the card of a new event saves the event" (opens the Calendar screen and finds the month). RV "a click on a screen name opens that screen". Pictures `calendar_*.png` (6). | proof |
| §5.3 | Card of an event: title, all day, start, end, colour, place, notes, repeat | `ui/calendar/event_editor.dart` | EE "a new event is saved with its title", "an event can be changed, and Ctrl+Return saves", "the start time moves the end with it", ""All day" hides the times and gives them back", "an event can repeat on some weekdays, a number of times", "a repeat can end on a day, or never", "the notes of an event are kept". DEV "calendar: the card of a new event saves the event". Pictures `event_card_*.png` (3). | proof |
| §5.3 | Card of an event: linked notes and "Create meeting note" | `ui/calendar/event_editor.dart` | EE "the meeting note is made from a saved event only" (also reads "Linked here"). | proof |
| §5.3 | Repeat engine: daily, weekly on weekdays, monthly (31st), yearly, interval, until, count, left-out days, changed days | `core/recurrence/` | `core/recurrence/recurrence_test.dart` groups "occurrences", "occurrence ids and events", "next" (34 tests). | proof |
| §5.3 | A change to one day of a series: only this one, or all | `state/store_events.dart` | `state/recurring_event_store_test.dart` "only this event moves one day", "all events changes the time of the series". EE "a day of a series asks which events to change". | proof |

### §5.4 — Notes

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.4 | Notes screen: list (pinned first), search, filters All, Daily, Weekly, Pinned, tags; the editor at the right | `ui/notes/notes_view.dart`, `ui/notes/notes_pane.dart` | NV "a click on a row opens that note", "the search shows the notes that match, and can be cleared", "the filters: daily, weekly, pinned and a tag". `state/note_store_test.dart` "pinned notes come first". Pictures `notes_*.png` (8). | proof |
| §5.4 | Editor: headings, bold, italic, code, quote, bullets | `ui/editor/rich_text_field.dart`, `ui/editor/markdown_controller.dart` | RT "a heading has bigger, bold letters on a whole line", "a bullet is drawn as a dot", "Command or Ctrl with B, I and E format the selection". `core/parsing/markdown_spans_test.dart` "headings", "quotes", "bold, italic and code". | proof |
| §5.4 | Check boxes are drawn; a click ticks them | `ui/editor/rich_text_field.dart` | RT "a check box is drawn as a box, ticked or not", "a click on a check box ticks it". | proof |
| §5.4 | `[[Title]]` links can be clicked | `ui/editor/markdown_controller.dart`, `state/store_editor.dart` | RT "a click on a mention opens it". `state/editor_store_test.dart` "opening a task mention selects the task and its day". | proof |
| §5.4 | A link with no target: a click shows "That item is gone." and makes no note (PLAN.md §5.4) | `ui/editor/markdown_controller.dart` (lines 832–840), `state/store_editor.dart` (line 78, the toast) | RT "a mention of a thing that is gone is struck out". `state/editor_store_test.dart` "opening a gone mention shows a toast" (checks the toast is "That item is gone." and that there is no note). Differs: the link with no target has the muted colour and no dotted line. The Mac source does the same (`Sources/Grove/AppStore+Editor.swift`). | proof |
| §5.4, §11.3 | `grove://` links are handled | none | Not found. Inside the app a mention opens by its id, so nothing is lost there. A `grove://` link from outside the app does nothing. Owner, 2026-10-12: later (PLAN.md §15.1). | missing |
| §5.4 | `@date` words and `#tags` have their own colour | `core/parsing/markdown_spans.dart`, `ui/editor/markdown_controller.dart` (lines 853–864) | RT "bold, italic, code, a quote and a tag each have their look" (reads the colour of the tag), "a web link and an @date are underlined in the accent colour" (reads the colour and the dotted line of the `@date`). `core/parsing/markdown_spans_test.dart` "an @date is marked where it can go to the planner", "tags and links". The code gives an `@date` the accent colour with a dotted line, and a `#tag` the second accent colour. PLAN.md §5.4 says the same (corrected 2026-10-12). | proof |
| §5.4 | The text is saved 500 ms after typing stops, and when the note closes | `ui/notes/note_editor_pane.dart` | NV "typed text is saved after a short wait", "text that was not saved yet is saved when the note closes", "text that was not saved yet is saved when the app goes to the back", "text that was not saved yet is saved when the text loses the keyboard". DEV "notes: the text of a note is saved a moment after typing". | proof |
| §5.4 | `[[` opens a list of notes, tasks and events; ↑ ↓ Return pick; Esc closes | `ui/editor/rich_text_field.dart`, `state/store_editor.dart` | RT group "the [[ list" (9 tests). `state/editor_store_test.dart` group "the [[ list" (5 tests). | proof |
| §5.4 | Daily note: one for a day, made at the first open, title "Friday, 2 October 2026", made from the template | `state/store_notes.dart` | `state/note_store_test.dart` "a daily note is made once from the template". NV ""Today" opens the note of today with the card of the day". | proof |
| §5.4 | Weekly note: one for a week, title "Week 40 · 28 Sep – 4 Oct" | `state/store_notes.dart` | `state/note_store_test.dart` "a weekly note uses the Monday". NV ""This week" opens the note of the week; the summary goes in". | proof |
| §5.4, §5.8 | The templates of the daily and the weekly note can be changed in Settings | `ui/settings/settings_tabs.dart`, `state/store_data.dart` | `ui/settings/settings_view_test.dart` "a template saves as you type, and goes back", "the weekly template has its own field". Picture `settings_desktop_grove_light_notes.png`. `state/settings_test.dart` "a note template is kept in the settings table", "an empty template is allowed; reset brings back the default". | proof |
| §5.4 | Pin, duplicate, delete with undo | `ui/notes/note_editor_pane.dart` | NV "pin, duplicate and delete from the header of the note", "a right click on a row: pin and delete". `state/note_store_test.dart` "deleting a note can be undone". | proof |
| §5.4 | Tags come from `#tag` in the text | `state/store_notes.dart`, `core/parsing/note_parser.dart` | `state/note_store_test.dart` "a body makes links and tags". `core/parsing/note_parser_test.dart` group "tags". | proof |
| §5.2, §5.4 | Add an image: paste, drop or a button | `ui/editor/rich_text_field.dart`, `ui/system/system_tools.dart` (`pickImageFiles`), `main.dart` (line 34) | `ui/store_app_tools_test.dart` group ""Add an image"": "in a note: the picture is stored and goes in the text", "in the notes of an event", "on a phone too". RT "a new image goes in as markup and is stored", "the remove button takes the image out of the text", group "the picker of the app". Q-15, answer A: the button "Add an image" uses the package `file_selector`. Missing: no paste and no drop of an image file. Owner, 2026-10-12: later (PLAN.md §15.1). | partly |

### §5.5 — connections between the parts

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.5 (1) | A `- [ ]` line in a note makes a task; the two stay in step; deleting the line keeps the task | `state/store_note_tasks.dart` | `state/note_task_store_test.dart` "open boxes make tasks in order and get marks", "ticking the box finishes the task and clearing it reopens it", "finishing the task ticks the box and undo clears it", "deleting the line keeps the task". NV "a box in the text makes a task when the typing ends". | proof |
| §5.5 (1) | The hidden mark `⟦t:ID⟧` of a task line is not seen | `ui/editor/markdown_controller.dart` (`EditorStyle.hidden`, line 84) | RT "the mark of a task line is not shown" (the mark has size and alpha 0 and no width), "the mark of a task made with the key is not shown". | proof |
| §5.5 (2) | A line with `@date time` offers "Add to planner" | `ui/editor/rich_text_field.dart`, `state/store_at_date.dart` | RT ""Add to planner" shows on a line with an @date" (taps it, the line changes). `state/at_date_store_test.dart` (20 tests). | proof |
| §5.5 (3) | "Linked here" on a note, a task and an event | `data/reference_indexer.dart`, `ui/notes/note_editor_pane.dart`, `ui/tasks/task_inspector.dart`, `ui/calendar/event_editor.dart` | NV ""Linked here" lists what mentions the note". TI "the note the task came from, and the items that link to it". EE "the meeting note is made from a saved event only". `data/reference_indexer_test.dart` group "links table". | proof |
| §5.5 (4) | The daily note shows the events, blocks and tasks of its day | `ui/notes/day_panel.dart` | NV ""Today" opens the note of today with the card of the day". `state/day_store_test.dart` "the agenda holds events, blocks and loose tasks". | proof |
| §5.5 (4) | The planner header has a button for the note of the day | `ui/planner/planner_view.dart` (lines 406–413, "Note for the day") | PC '"Note for the day" opens the daily note of the day', '"Note for the day" opens the note of the day in view, not of today'. | proof |
| §5.5 (5) | "Done today" list under the daily note | `ui/notes/day_panel.dart` | NV ""Today" opens the note of today with the card of the day" (reads "Nothing finished yet."), "a finished task shows under "Done today" with its time". `state/day_store_test.dart` "completed tasks lists what was finished on the day". | proof |
| §5.5 (6) | "Create meeting note": title "<Event> — 2 Oct", three sections, linked to the event; action items become tasks | `state/store_meeting.dart` | EE "the meeting note is made from a saved event only". `state/meeting_note_test.dart` "the title has the event name and the short date", "the body starts with the link and has the three sections", "an action item becomes a task linked to the note". | proof |
| §5.5 (7) | Selected text becomes a task with ⇧⌘T or a menu line "Make task" | `ui/editor/rich_text_field.dart` (line 228 for the key, line 521 for the menu line), `state/store_note_tasks.dart` | RT "on a Mac the key is Shift, Command and T", "Shift, Ctrl and T makes a task of the line" (Ctrl on the other systems), "the key makes a task of the selected words only", "the key without Shift, or with Alt, makes no task", "the menu of the text has "Make task", and a tap makes the task". RT "a line with words becomes a task line" calls the code, not the key. `state/note_task_store_test.dart` group "make task". | proof |
| §5.5 (8) | A note dragged onto the planner makes a 30-minute block "📝 title" | `ui/notes/notes_pane.dart`, `state/store_planner.dart` | NV "a note dragged from the left panel onto the planner gets a time". `state/note_drop_test.dart` "a note makes a half-hour event linked to it". | proof |
| §5.5 (9) | The notes field of a task and of an event is the rich editor | `ui/calendar/event_editor.dart`, `ui/tasks/task_inspector.dart` | TI "the description is the editor with its row of buttons". EE "the notes of an event are kept" (types in the editor). `ui/store_app_tools_test.dart` "in the notes of an event". `state/meeting_note_test.dart` "a mention in event notes becomes a link". | proof |
| §5.5 (10) | Weekly note: numbers of the week and "Insert summary" under `## Review` | `ui/notes/day_panel.dart`, `state/store_daily.dart` | NV ""This week" opens the note of the week; the summary goes in". `state/day_store_test.dart` "the review shows done, open, hours and the busiest day", "inserting the summary writes it under Review and undo takes it back". | proof |
| §5.5 (11) | Command palette (⌘K): tasks, events, notes, commands, `>` for commands, "Go to Friday" | `ui/shell/command_palette.dart`, `ui/shell/app_menus.dart` (line 271), `ui/shell/top_buttons.dart`, `state/store_palette.dart`, `core/parsing/palette_rules.dart` | `ui/shell/command_palette_test.dart` "Ctrl and K opens it, and closes it", "typing keeps the rows that match" (also `>` for commands), ""Go to date…" keeps the box open and waits for a day", "down and up choose a row, and Return runs it", "a tap on "Search" opens the box with the cursor in it", "each button of the box has a label for a screen reader". Pictures `palette_*.png` (8). `state/palette_store_test.dart` (24 tests), `core/parsing/palette_rules_test.dart` (16 tests). | proof |
| §5.5 (12) | Three mood icons in the header of the daily note | `ui/notes/note_editor_pane.dart` | NV "the mood: each of the three, and a second click clears it", ""Today" opens the note of today with the card of the day". `state/day_store_test.dart` "a mood is set, changed and cleared by the same click". | proof |
| §5.5 (12) | The month can tint days by mood | `ui/calendar/month_view.dart` | MV "the mood switch tints the days by the mood of their note". | proof |

### §5.6 and §5.7 — reminders, menu bar

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.6 | Ask for the permission after the welcome card, not at once | `state/store_welcome.dart` | `state/welcome_store_test.dart` ""Got it" asks for notifications once", "it does not ask again when the system already answered". | proof |
| §5.6 | A reminder for the start of an event or block (0, 5, 10 or 15 minutes before; 5 at first) and for a due time. Title is the item; the text is the time | `core/services/reminder_planner.dart`, `state/store_reminders.dart` | `core/services/reminder_planner_test.dart` "an event reminds on the lead time before it starts" (reads "Stand-up" and "09:30 – 10:00"), "a task due at a time reminds", "the lead choices are the four in the plan". `ui/settings/settings_view_test.dart` "the switch turns reminders off, and the time goes grey" (picks "10 minutes before"). | proof |
| §5.6 | At most the next 60; the id is `ev-<id>-<start>` | `core/services/reminder_planner.dart` | `core/services/reminder_planner_test.dart` "the default limit is sixty because the system keeps sixty-four", "the id has the event and its start". | proof |
| §5.6 | Reminders are made again after each change (one time for many changes) and at launch | `state/store_reminders.dart`, `services/app_services.dart` | `state/reminder_store_test.dart` "many changes in a row make one refresh", "a saved change makes the reminders again". `services/app_services_test.dart` "sends the reminders, shows the tray, gives the launch click", "when the app comes back: backup check and new reminders". | proof |
| §5.6 | A click on a reminder opens the app on that day or item | `state/store_reminders.dart`, `services/system_notifier.dart` | `state/reminder_store_test.dart` "a click on a block reminder opens its task on its day" (the system is a fake). | proof |
| §5.6 | The reminder is really shown by macOS, Windows, Android and iOS | `services/local_notifications_gateway.dart` | `services/system_notifier_test.dart` (36 tests) and `services/local_notifications_gateway_test.dart` (8 tests) check the calls to the plugin with a fake channel. No machine sees a real reminder. | built, no proof |
| §5.6 | When the permission is refused: a quiet note in Settings | `ui/settings/settings_tabs.dart` (line 559 for the note, line 575 for the button), `state/rules/settings_rules.dart`, `state/store_reminders.dart` | `ui/settings/settings_view_test.dart` ""Allow notifications" asks" (reads "Problem: Notifications are off for Grove."), "the switch asks for permission the first time". `state/reminder_store_test.dart` "each status has a quiet note", "nothing is sent when the user said no or was never asked". | proof |
| §5.7 | Menu bar icon with "Now: …" and "Next: … in 25 min" | `services/tray_service.dart`, `state/store_menu_bar.dart` | `services/tray_service_test.dart` "the menu shows now, next, the growth and the commands" (the tray is a fake). `state/menu_bar_test.dart` group "the Now and Next lines" (9 tests). | proof |
| §5.7 | A bar for how much of today is done | `services/tray_service.dart` | `services/tray_service_test.dart` "the menu shows now, next, the growth and the commands" (reads the line; the tray is a fake). Differs: a line of text, not a bar. Q-7, answer A: the tray is a normal system menu, with a line for how much of today is done. | proof |
| §5.7 | "Open Grove" | `services/tray_service.dart` | `services/tray_service_test.dart` ""Open Grove" shows the window". | proof |
| §5.7 | Menu bar item on Android and iOS | none | Phones have no menu bar and no tray (`services/tray_service_test.dart` "a system with no tray: the service does nothing"). | not for this platform |

### §5.8 — window, commands, settings

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.8 | Window: at least 960×620, 1280×800 at first, no title bar | `app/macos/Runner/MainFlutterWindow.swift`, `app/windows/runner/main.cpp`, `app/windows/runner/win32_window.cpp`, `ui/shell/window_drag.dart` | `app/integration_test/window_test.dart` "the window opens at the size of the Mac app" (macOS and Windows, run by `scripts/flutter_integration.sh`). `ui/shell/window_drag_test.dart` "on a Mac a drag on an empty part of the top strip moves the window". Differs: the smallest size is 1100 × 620, as in the code of the Mac app, not 960 × 620 (PLAN.md §5.8 corrected 2026-10-12; `docs/assumptions.md`). Windows keeps its title bar. The Mac window does not remember its last size. | proof |
| §5.8 | File ▸ New Task ⌘N, New Note ⌥⌘N, New Event ⇧⌘N | `ui/shell/app_menus.dart` | `ui/shell/app_menus_test.dart` "Ctrl and N puts the cursor in the field of a new task", "Ctrl, Alt and N makes a note and opens it", "Ctrl, Shift and N makes an event and opens its card", "a Mac gets the menus of the Mac app". On a Mac the key is Command. | proof |
| §5.8 | View ▸ Today ⌘T, and ⌘1 to ⌘4 for the screens | `ui/shell/app_menus.dart`, `ui/shell/root_view.dart` | RV "Ctrl with a number opens a screen", "on a Mac the key is Command". `ui/shell/app_menus_test.dart` "a Mac gets the menus of the Mac app". More than PLAN: 5 opens the Garden. | proof |
| §5.8 | View ▸ Day / 3-Day / Week ⌥⌘1/2/3 | none | PLAN §5.1 (2026-10-09) took the day modes away. `ui/planner/planner_kind.dart` has today, week and month. | missing (off by PLAN) |
| §5.8 | Theme ▸ and Appearance ▸ (System, Light, Dark) | `ui/shell/appearance_button.dart`, `ui/shell/app_menus.dart` | RV "the menu at the top right switches the theme live", "the menu sets light or dark and the motion switch", "System follows the device". `ui/shell/app_menus_test.dart` "Theme and Appearance list each choice and mark the one in use", "a line of the theme changes the mark". It is a button in the window on each system, and two menus of the menu bar on a Mac. | proof |
| §5.8 | A menu bar with File, View, Go and Edit | `ui/shell/app_menus.dart` | `ui/shell/app_menus_test.dart` (25 tests) "a Mac gets the menus of the Mac app", "a line that is picked does its work", "the other systems have no menu bar of the system". Differs: only a Mac has the menu bar (`PlatformMenuBar`). Windows has none; the keys work on each system. | proof |
| §5.8 | Edit ▸ Undo / Redo | `ui/shell/app_menus.dart`, `ui/store_app.dart` | `ui/shell/app_menus_test.dart` "Ctrl and Z takes a step back, with Shift or Y it comes again", "in a text field the key takes back the step of the store", "Undo is grey with nothing to undo, then names the step". PV "Undo puts a moved block back; Redo moves it again". Differs: the store has its own undo list; it is not the undo of the system. | proof |
| §5.8 | "Search ⌘K" pill and a gear button at the top right; ⌘, | `ui/shell/top_buttons.dart`, `ui/shell/command_palette.dart`, `ui/shell/app_menus.dart` | `ui/shell/command_palette_test.dart` "a desktop window has "Search" with its key, and a gear", "a tap on the gear opens Settings", "a phone has the search picture and no gear". `ui/shell/app_menus_test.dart` "Ctrl and comma opens Settings, one window only". On a phone Settings is in the Appearance menu (`ui/settings/settings_view_test.dart` "the Appearance menu has "Settings…""). | proof |
| §5.8 | Settings ▸ Appearance: theme with previews, light/dark/system, motion, accent strength | `ui/settings/settings_view.dart`, `ui/settings/settings_tabs.dart`, `state/store_appearance.dart` | `ui/settings/settings_view_test.dart` (41 tests) "a theme card picks the theme", "light or dark", "the motion switch", "the accent intensity". Each theme card has a small preview. Pictures `settings_*_appearance.png`. | proof |
| §5.8 | Settings ▸ Planner: working hours, busy-day limit, first length, hour height, week starts Monday or Sunday, mood tint | `ui/settings/settings_tabs.dart`, `state/store_data.dart`, `state/rules/` | `ui/settings/settings_view_test.dart` "the length of a new event", "the hour height, and the planner follows", "working hours stay one hour long at least", "the busy day limit", "tint days by mood", "the first day of the week". Rules: `state/settings_test.dart` "the busy day limit is whole hours from six to twelve", "the week starts on Monday or Sunday". | proof |
| §5.8 | Settings ▸ Notifications: on or off, minutes before | `ui/settings/settings_tabs.dart`, `state/store_reminders.dart` | `ui/settings/settings_view_test.dart` "the switch turns reminders off, and the time goes grey" (it also picks "10 minutes before"), "the switch asks for permission the first time". Rules: `state/reminder_store_test.dart` "the switch and the lead are saved". | proof |
| §5.8 | Settings ▸ Data: the list of backups | `ui/settings/settings_tabs.dart`, `data/backup.dart` | `ui/settings/settings_view_test.dart` "the daily backups". Rules: `state/settings_test.dart` "a backup name becomes a day"; `data/database_test.dart` "the list of a missing folder is empty". | proof |
| §0, §5.8 | Layout picker in Settings and in the View menu | none | Needed only with more than one layout. §0 lists B only. | missing (off by PLAN) |
| §5.8 | Settings are kept in the `settings` table | `data/repos.dart`, `state/prefs.dart` | `data/database_test.dart` "settings round trip". `state/settings_test.dart` "a note template is kept in the settings table". In the table: the note templates, the wake-up and sleep lines, the keys of the first launch. Differs: the theme, light/dark, motion, the accent strength, the hour height, the working hours, the first length, the busy-day limit, the first day of the week, the mood tint, the reminders switch and its minutes, the fold of the strip, the width of the task column and the left panel are in a `Prefs` file on the device, as the Mac app keeps them in UserDefaults. They are not in an export and they do not sync. Owner, 2026-10-12: later (PLAN.md §15.1). | partly |

### §5.9 — Goals

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.9 | Table `goals`; events have `goal_id` and `done_at` | `data/migrations.dart`, `data/repos.dart` | `data/goal_repo_test.dart`. `data/database_test.dart` "there are eight migrations: the seven of the Mac app, and one of this app only". | proof |
| §5.9 | Goals panel: "2.5 / 5 h done" or "3 / 5 sessions done", a bar, "4 h planned", for the week of the chosen day | `ui/goals/goals_pane.dart`, `ui/goals/goal_row.dart` | GP "a row shows the done and the planned time of the week", "the header names the week of the selected day", "a goal with no blocks says so". Pictures in `app/test/ui/goals/goldens/` (7). | proof |
| §5.9 | Add a goal: name, Hours or Sessions, target (0.5 h steps, 5 h at first; sessions 3 at first) | `ui/goals/goals_pane.dart` | GP "Return adds a goal of 5 hours a week", "the stepper sets the hours", "a goal of sessions". | proof |
| §5.9 | The editor in place; Esc, a click on the goal or another goal closes it; right-click ▸ Edit… | `ui/goals/goals_pane.dart`, `ui/goals/goal_row.dart` | GP ""Edit goal…" in the open goal opens it, a click on the goal closes it", "one goal is open at a time", "Esc drops the typed name and closes the editor", ""Edit…" opens the editor". Differs since 2026-10-12 (Q-48): a click on a goal opens its subtasks; the editor is one click more, under "Edit goal…" in the open goal. | proof |
| §5.9 | A goal dragged onto a day makes a 1-hour block | `ui/planner/planner_grid.dart`, `state/store_goals.dart` | SP "a goal dragged from the panel onto a day gets a block". The length: `state/goal_store_test.dart` "the default block length is one hour". | proof |
| §5.9 | The length of a goal block from its menu (15 minutes to 4 hours) | `ui/planner/planner_grid.dart` (`_openMenu`, `_openDurations`), `PlannerLimits.durationChoices` | PC '"Duration" in the menu gives a goal block a new length'. `ui/planner/planner_menu_test.dart` ""Duration" gives the block a new length", "a goal block has its own lines". No test picks "4h". | proof |
| §5.9 | Planned and done come from the blocks of the week; never stored; can go over the target | `state/store_goals.dart` | `state/goal_store_test.dart` (45 tests), `state/goal_pane_test.dart` (21 tests). On the screen: GP "a row shows the done and the planned time of the week". | proof |
| §5.9 | Tick a goal block done: check box, menu ▸ Mark Done, or Space | `ui/planner/block_view.dart`, `ui/planner/planner_grid.dart` | PC "a tap on the check box marks the goal block done". The menu: `ui/planner/planner_menu_test.dart` "a goal block has its own lines" (Mark Done, Mark Not Done). Space: `ui/planner/planner_paths_test.dart` "Space marks the selected goal block done". Store: `state/clock_store_test.dart` "a goal block ticked done gets the time of the clock". | proof |
| §5.9 | A deleted goal leaves its blocks | `state/store_goals.dart` | GP ""Delete Goal…" asks first", "a deleted goal leaves its blocks, and undo puts it back". | proof |
| §5.9 | Goals are in the export, the import and the backup | `data/data_export.dart` | `data/data_export_test.dart` group "goals in the file" (5 tests). | proof |
| §5.9 (Swift PR #4, `docs/tracks.md` F7) | Subtasks on a goal block: rows in the block, menu lines, a small window to edit them | `ui/planner/block_view.dart`, `ui/planner/block_subtask_editor.dart`, `state/store_block_subtasks.dart` | `ui/planner/planner_subtasks_test.dart` (22 tests) "a tall goal block shows its subtasks, then "+N more"", "a goal block with no subtasks has "Add Subtasks…"", "the check box ticks a subtask and opens it again". Picture: `ui/planner/planner_gaps_golden_test.dart` "a goal block with subtasks and their window". Store, data and sync: `state/block_subtask_store_test.dart`, `data/block_subtask_test.dart`, `sync/block_subtask_sync_test.dart`. Differs: the small subtask marks have no burst (see the Gaps). | proof |

### §6 — themes and motion

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §6 | Four themes; the switch is live | `ui/theme/grove_theme.dart`, `ui/shell/appearance_button.dart` | RV "the menu at the top right switches the theme live", "every theme draws on both sizes with no error". Pictures `desktop_*.png` and `phone_*.png` (16). | proof |
| §6 | The change is a 0.35 s cross-fade | `ui/theme/grove_theme.dart` (line 387) | `ui/theme/grove_theme_test.dart` group "the cross-fade" (4 tests), with "the animated theme takes 0.35 s". | proof |
| §6 | Light or dark is its own setting; each theme has both looks | `ui/theme/theme_spec.dart` | `ui/theme/theme_spec_test.dart` "every theme has a light and a dark look", "a theme does not choose light or dark". RV "System follows the device". | proof |
| §6.1 | Colour tokens of the 8 looks | `ui/theme/theme_spec.dart` | `ui/theme/theme_spec_test.dart` "Grove tokens match the plan", "Minimal tokens match the plan", "Futuristic tokens match the plan", "Vintage tokens match the plan". | proof |
| §6.1 | Fonts of each theme | `ui/theme/fonts.dart`, `app/fonts/` | `ui/theme/fonts_test.dart` (6 tests). `ui/theme/grove_theme_test.dart` group "fonts" (11 tests). Differs: PLAN uses the fonts of macOS. Flutter has 7 free fonts inside the app, so all 4 systems show the same letters (Q-1 and Q-2, answered A). | proof |
| §6.2 | Grove: soft shadow, round corners | `ui/theme/panel.dart` | `ui/theme/grove_theme_test.dart` "Grove: surface, line, round corners, a soft shadow", "personality follows the plan". | proof |
| §6.2 | Minimal: no shadow, hairlines, fainter blobs | `ui/theme/panel.dart` | `ui/theme/grove_theme_test.dart` "Minimal: a hairline and no shadow". `ui/theme/theme_spec_test.dart` "blobs are fainter in Minimal and Futuristic". | proof |
| §6.2 | Futuristic: glass panels, a 32-point grid, glow on titles | `ui/theme/panel.dart`, `ui/theme/ambient_background.dart` | `ui/theme/grove_theme_test.dart` "Futuristic: glass, a blur of what is behind", "Futuristic: capitals, wide spacing and a glow". RV "Futuristic has the grid, Vintage the paper". The pulse of the now line: `ui/planner/planner_now_line_test.dart`. The glow on check boxes is in no test. | proof |
| §6.2 | Vintage: paper with noise, ruled lines of 28 points in the editor, dashed chips | `ui/theme/ambient_background.dart`, `ui/editor/` | RV "Futuristic has the grid, Vintage the paper". RT "Vintage: every line is 28 points high, a heading too". `ui/theme/grove_theme_test.dart` "Vintage chips have a dashed border". `ui/theme/theme_math_test.dart` "the noise is the SplitMix64 of the Mac app". | proof |
| §6.3 | Background: three blobs, 46 % of the window, slow paths of 22, 28 and 34 s; it stops when the window is not in front | `ui/theme/ambient_background.dart`, `ui/theme/theme_math.dart` | `ui/theme/theme_math_test.dart` group "ambient background (PLAN §6.3)" (8 tests). RV "with motion on the blobs move, and stop when the window is not in front". | proof |
| §6.3 | Motion off and the system setting "reduce motion" stop all motion | `state/store_appearance.dart`, `ui/shell/root_view.dart` | RV "with motion off nothing moves", "the device setting "reduce motion" stops the blobs". | proof |
| §6.3, §6.2 | Growing plant: 0 to 6 leaves, sways 3° in 5 s; in the header of Layout B | `ui/theme/growing_plant.dart`, `state/rules/plant_math.dart`, `ui/spread/day_spread_view.dart` | `ui/theme/growing_plant_test.dart` (5 tests) "the picture gets the leaves and the flower of the rules", "with motion on the plant sways; "reduce motion" stops it". `ui/garden/garden_view_test.dart` "the Day Spread has the small plant of the day in its header". Rules: `state/theme_motion_test.dart` group "the plant" (10 tests). | proof |
| §6.3, §6.2 | Check-burst on completion (leaves, fade, ring, "DONE" stamp); the check box fills with a spring | `ui/theme/check_box.dart` (`CheckBox`, `CheckBurst`, spring with response 0.3 and damping 0.6, lines 36–37 and 219) | CB group "the burst" (13 tests): "a box that turns on throws six leaves, and they fly out 18 points in half a second", "the leaves fade while they fly", "Minimal: a fade and no flying parts", "Futuristic: a ring and six sparks", "Vintage: the stamp "DONE"", "with Motion off there is no burst", "a box that turns off plays no burst", "a second check while the burst plays starts it again". CB group "the box": "with motion the box fills with a spring" (checks the fill animates and ends at full size; the spring numbers are not checked by eye), "with Motion off the box is full at once". Rules: `state/theme_motion_test.dart` group "the check-off burst". Differs: the small subtask marks have no burst (see the Gaps). | proof |
| §6.3 | Rows of a list move in and out with a slide and a fade | `ui/tasks/task_section.dart` (`TaskRows`, `RowSlide`, line 179) | TM group "rows come and go" (10 tests): "a new row slides in and fades in, in a quarter of a second", "a row that goes away slides out and fades, and the rows under it move up", "a finished task waits for its burst, then slides out", "with Motion off rows come and go at once". Look by eye is not checked (see "Not verified by a machine"). | proof |
| §6.3 | The greeting follows the time of day | `ui/spread/spread_rules.dart` | DS "the greeting follows the hour, the growth follows the tasks". | proof |

### §7 to §12 — state, layouts, first launch, quality, packaging, tests

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §7 | One store with the chosen day, the screen, the selection, the theme and the settings; the screens follow each change | `state/app_store.dart` | `state/clock_store_test.dart` "coming to the Today screen picks the day of the clock". NV "a change from outside shows in the open note". TI "a change from another place shows in the panel". | proof |
| §7 | Reads: blocks of a range (with repeats), tasks of a day and a week, tasks with no time, the daily note, backlinks, search | `state/` | `state/recurring_event_store_test.dart` "a weekly event shows on every week". PS "timeless tasks are the day tasks with no block". `state/note_store_test.dart` "the list searches titles and text". | proof |
| §7 | Each change is one named undo step; a change of many blocks is one step | `state/mutation.dart` | PS "move and resize are undoable", "ripple pushes later blocks" (one undo for the resize and the push). PV "a mouse drag moves a block and snaps to 15 minutes" (the step is named "Move Block"). GP "each change of the editor is one undo step". Differs: the store has its own undo list; it is not the undo of the system. | proof |
| §8 B | Header: big date, greeting and "% of today grown" | `ui/spread/day_spread_view.dart` | DS "the greeting follows the hour, the growth follows the tasks". | proof |
| §8 B | Three columns; the task column is 300 to 420 points wide and can be dragged; the planner takes the rest; the note of today | `ui/spread/day_spread_view.dart` | DS "three columns: the tasks, the timeline, the note of today", "a drag of the edge changes the width of the task list, and the width is kept", "the smallest desktop window keeps the three columns", "text typed in the note of today is saved". | proof |
| §8 B | The left place can show the Notes, Tasks or Goals panel | `ui/spread/day_spread_view.dart` | DS "an open left panel stands in the place of the task list". | proof |
| §8 B | The switch at the top goes to Planner, Calendar and Notes | `ui/shell/screen_switch.dart` | RV "the screen switch sits at the top with five words", "a click on a screen name opens that screen". | proof |
| §8 | Every layout can reach Planner, Tasks, Calendar, Notes, the command palette and Settings | `ui/shell/root_view.dart`, `ui/shell/top_buttons.dart`, `ui/shell/command_palette.dart` | RV "a click on a screen name opens that screen". `ui/shell/command_palette_test.dart` "Ctrl and K opens it, and closes it", "a tap on the gear opens Settings". On a phone: `ui/settings/settings_view_test.dart` "the Appearance menu has "Settings…"". | proof |
| §8 A | Layout A · Garden (sidebar, inspector) | none | Off by §0 (B only). | missing (off by PLAN) |
| §8 C | Layout C · Week Board | none | Off by §0 (B only). | missing (off by PLAN) |
| §8 D | Layout D · Journal | none | Off by §0 (B only). | missing (off by PLAN) |
| §9 | First launch: lists "Home 🌿", "Work 💼", "Personal ✨" and 3 sample tasks | `data/first_run.dart` | `data/first_run_test.dart` "a new database gets three lists and three sample tasks", "the sample tasks explain drag to plan, links and the palette". | proof |
| §9 | First launch: the daily note of today | `ui/spread/day_spread_view.dart` (lines 433–436) | DS "three columns: the tasks, the timeline, the note of today" (it checks that the note of today is made when the column opens). The app starts on Today. Differs: the note is made when the Today screen opens, not by the first-run code. A phone or a narrow window has no note column, so no note is made there. | proof |
| §9 | Welcome card with "Got it" and "Remove samples" | `ui/tasks/notice_cards.dart`, `state/store_welcome.dart` | TP "the welcome card is a card of today only", "the welcome card: "Got it" closes it and keeps the samples", "the welcome card: "Remove samples" closes it and deletes the samples, and undo brings them back". Store: `state/welcome_store_test.dart` (9 tests). | proof |
| §9 | Empty planner: "Drag a task here, or drag on the grid to plan time." | `ui/planner/planner_grid.dart` | PV "shows the week, the hours and the now line". | proof |
| §9 | Empty notes: "Your thoughts grow here. ⌥⌘N for a new note." | `ui/notes/notes_view.dart` (line ~110, `KeyNames.of(_Empty.newNoteKey)`) | NV "no notes: the screen names the key of a new note, and the key makes one", "on a Mac the hint names the key ⌥⌘N". Differs: on the other systems the hint names Ctrl+Alt+N. The hint also names the key on a tablet with no keyboard (known; not fixed). | proof |
| §9 | Empty lists of tasks and goals say so | `ui/tasks/tasks_pane.dart`, `ui/goals/goals_pane.dart` | TP "an empty day says so", "an empty list says so". GP "an empty panel says what a goal is". | proof |
| §10 | All buttons have labels | `ui/shell/`, `ui/planner/planner_view.dart`, each screen | RV "the buttons say what they are". PV finds "Next" by its label. The tests of Settings, the Garden, the focus card, the editor, the month, the inspector, the goal subtasks and the day lines find buttons by their labels. TP "each button of the panel has a label for a screen reader", "the buttons of the unscheduled list have labels too". `ui/shell/command_palette_test.dart` "each button of the box has a label for a screen reader". Missing: one test that walks all buttons of all screens. | partly |
| §10 | A block says "Title, 11:15 to 12:45" to a screen reader | `ui/planner/block_view.dart` (`_helpText`, line 94; the semantics label, line 197) | PC "a block says its title and its times" (reads "Lunch · 11:15 – 12:45 · 1h 30m"), "a goal block says that it is one" (reads "Goal block · Read · 11:00 – 12:30 · 1h 30m"). Real screen readers are not checked (see "Not verified by a machine"). | proof |
| §10 | Ink on surface has a contrast of 4.5 to 1 or more | `ui/theme/theme_spec.dart` | `ui/theme/theme_spec_test.dart` "ink reads on every layer in every variant". | proof |
| §10 | No database call during a drag | `ui/planner/planner_grid.dart` | PV "the label shows the new time during the drag" (the store has the old time until the pointer goes up). | proof |
| §10 | An error shows a small message; the app never crashes | `ui/shell/error_alert.dart`, `state/app_store.dart` | `ui/shell/error_alert_test.dart` (10 tests) "an error of the store opens the window with its text", ""OK" closes the window and takes the message away". Pictures `error_desktop_grove_light.png`, `error_desktop_grove_dark.png`, `error_phone_grove_light.png`. Rule: `data/data_export_test.dart` group "bad files change nothing". Differs: a small window with "OK", not a toast. | proof |
| §10 | A list of 1 000 tasks is read in under 50 ms | `data/repos.dart` | `data/database_test.dart` "a thousand tasks query is fast". | proof |
| §10, §1 | Launch in under 1 s; a drag at 60 pictures a second | `app/integration_test/perf_test.dart`, `app/tool/perf_start.dart`, `scripts/flutter_perf.sh` | `scripts/flutter_perf.sh macos` runs "frame times with a full store" and prints `GROVE_PERF` lines. It runs by hand, on macOS only, not on CI, and no limit makes it fail. Missing: limits that fail the check, and a run on CI. Owner, 2026-10-12: later (PLAN.md §15.1). | built, no proof |
| §11.1 | The app has its own icon | `scripts/make_flutter_icons.swift`, `app/macos/Runner/Assets.xcassets/AppIcon.appiconset/`, the icon folders of iOS, Android and Windows | `app_icons_test.dart` (4 tests) "macOS: each icon is the Grove logo at the size its slot needs", "Android: each launcher icon is the Grove logo", "Windows: the icon file holds the Grove logo at each size", and one for iOS. | proof |
| §11.2, §11.3 | `scripts/make_icon.swift`, `scripts/build_app.sh`, `scripts/install.sh` | none | Scripts of the Mac app. Flutter has `scripts/make_flutter_icons.swift`, `scripts/flutter_build.sh`, `scripts/flutter_release.sh`, `scripts/flutter_test.sh`, `scripts/flutter_integration.sh`. | not for this platform |
| §11.3 | One command builds, installs and puts an icon on the Desktop | `scripts/flutter_release.sh`, `.github/workflows/release.yml` | `scripts/flutter_release.sh` with `macos`, `windows`, `android` or `ios` makes the files in `app/build/dist/`. The `release` workflow runs by hand only. No test. Missing: the install step and the Desktop icon. Nothing is signed (Q-31, answered A). A Mac install script comes in the branch `feat/xp-retire-swift`. | partly |
| §12 | PlannerMath tests | `core/planner/planner_math.dart` | PM, 8 groups. The layout cases are for the cascade (see §5.1.3). | proof |
| §12 | QuickAddParser tests: 25 phrases or more, with a fixed "today" | `core/parsing/quick_add_parser.dart` | `core/parsing/quick_add_parser_test.dart` (34 tests). | proof |
| §12 | NoteParser tests: links, check boxes, `@date`, `#tags` | `core/parsing/` | `core/parsing/note_parser_test.dart` groups "tags" and "check boxes". `core/parsing/reference_parser_test.dart`. `core/parsing/at_date_test.dart`. | proof |
| §12 | Recurrence tests | `core/recurrence/` | `core/recurrence/recurrence_test.dart` (34 tests). | proof |
| §12 | Database tests: migrations, each repo, cascade, search, 1 000 tasks | `data/` | `data/database_test.dart` (27 tests). | proof |
| §12 | LinkIndexer tests | `data/reference_indexer.dart` | `data/reference_indexer_test.dart` "reindex writes and clears backlinks", "reindex keeps manual links". | proof |
| §12, §1.1 | The test script passes | `scripts/flutter_test.sh` | `./scripts/flutter_test.sh` on 2026-10-12 on branch `feat/xp-f12-close`: exit 0; "Formatted 355 files (0 changed)"; `flutter analyze` "No issues found!"; `flutter test` "+2779: All tests passed!". | proof |

## Things the port added (not in PLAN.md)

These rows are not in the counts of the PLAN.md table. They are things the
port adds, and two things the Mac app does that PLAN.md does not state (web
links, the window that closes to the tray). PLAN.md §15 says "no sync, no
iPhone app". The owner changed that on 2026-10-09
(`docs/cross-platform-plan.md`).

| Feature | Flutter code | Proof | State |
|---|---|---|---|
| Touch: press, hold and drag to make, move and resize a block | `ui/planner/planner_grid.dart`, `ui/planner/block_view.dart` | PV "a finger makes a block with press, hold and drag", "a finger moves a block with press, hold and drag", "a finger changes the end at the bottom edge", "a finger drags the $edge edge on a device with a small touch slop (Android)". DEV runs on iOS and Android on CI. | proof |
| Phone layouts: one day column, a bar at the bottom, panels on the whole screen | `ui/shell/shell_layout.dart` | PV "a phone shows one day column". RV group "on a phone" (4 tests). DS "a phone shows one day column". NV "a phone shows the list, then the note with a way back". MV "the month fits a phone". TI "the panel fits a phone". | proof |
| Busy-day alert when a day goes over 9 hours | `ui/planner/planner_view.dart`, `ui/planner/planner_dialogs.dart` (`showBusyDay`) | `ui/planner/planner_paths_test.dart` "a change that takes the day over the limit opens "Busy day"". Store: PS group "busy-day alert" (6 tests). The limit is a setting (see §5.8, Settings ▸ Planner). | proof |
| Bar of planned time against the daily limit | `ui/planner/workload.dart`, `ui/planner/planner_view.dart` | `ui/planner/planner_paths_test.dart` "the header shows planned time against the daily limit", "a day over the limit says so". Rules: PR group "Workload" (3 tests). | proof |
| Sync engine: outbox, push, pull, last write wins | `sync/`, `state/store_sync.dart`, `services/supabase_backend.dart` | `sync/sync_engine_test.dart`, `sync/outbox_test.dart`, `sync/store_sync_test.dart`, `state/sync_store_test.dart`, with a fake server. The SQL ran on a plain Postgres on CI. A real two-device sync was never run. | proof |
| Login with the code of an email, the question of the first sync, the Sync tab of Settings and the sync mark | `ui/auth/sync_card.dart`, `ui/auth/first_sync_dialog.dart`, `ui/settings/settings_tabs.dart`, `ui/settings/sync_mark.dart` | `ui/settings/settings_sync_test.dart` (9 tests) "the login in Settings works, and the mark follows", "the question of the first login opens over the screens". `ui/auth/sync_card_test.dart` (13 tests) "the email, the code, then signed in". Pictures in `app/test/ui/auth/goldens/` (16). The server is a fake. No machine tried a real login. | proof |
| Garden screen | `ui/garden/garden_view.dart`, `ui/garden/garden_painter.dart`, `core/services/garden.dart` | `ui/garden/garden_view_test.dart` (11 tests). Pictures `garden_*.png` (8). DEV "garden and settings: the plant shows, a theme card works". Rules: `core/services/garden_test.dart`. | proof |
| A web link in a note opens the browser | `ui/system/system_tools.dart` (`url_launcher`), `main.dart` | `ui/store_app_tools_test.dart` group "a web link in a note": "a click opens the browser", "a browser that cannot open it: a message". Q-16 answered A. The browser is a fake in the test. | proof |
| Closing the window keeps Grove in the tray, as the Mac app does | `services/app_window.dart` | Q-8 answered A: closing the window quits Grove. No code change. | missing (off by the owner) |
| The futuristic Day Spread picture on Linux and Windows | `app/test/ui/goldens/f9_golden_test.dart` (`_parked`) | Q-17 answered B: stays macOS only. The picture is checked on macOS and skipped on Linux and Windows. | partly |
| Subtasks of a goal (the owner asked on 2026-10-12): 3 under the closed goal, a click shows all and a line to add one; tick, rename, delete; one list for all blocks of the goal, apart from the list of one block | `ui/goals/goal_subtasks.dart`, `state/store_goal_subtasks.dart`, `data/migrations.dart` (migration 8) | `ui/goals/goal_subtasks_test.dart`, `state/goal_subtask_store_test.dart`, `data/goal_subtask_test.dart`, `sync/goal_subtask_sync_test.dart`. DEV "goals: a tap opens a goal, a typed line is a subtask of the goal, a tap ticks it". Q-48 and Q-49 answered A. The rows for each check of the owner are in `docs/acceptance/goal-subtasks.md`. | proof |
| The Today screen can show tomorrow, to plan the next day | `ui/spread/day_spread_view.dart`, `state/store_navigation.dart` | DS group "the tomorrow view" (15 tests) "a click on Tomorrow shows only tomorrow", "a block drawn on the timeline lands on tomorrow". `state/today_screen_day_test.dart` (20 tests). DEV "today: the switch of the header shows only tomorrow, and a new block lands there". The rows of the owner are in `docs/acceptance/today-tomorrow.md`. | proof |
| Wake-up and sleep lines on a day of the planner; each day has its own (Q-52, answered A) | `ui/planner/day_markers.dart`, `state/store_day_markers.dart`, `state/rules/day_marker.dart` | `ui/planner/day_marker_test.dart` (34 tests) "adds the wake-up line: a line with its time, in view", "with the mouse moves it in steps of 15 minutes, and the time on the label follows". `ui/planner/day_marker_golden_test.dart`, `ui/planner/day_marker_header_test.dart`, `state/day_marker_store_test.dart` (23 tests). DEV "day lines: "+" adds the wake-up line, a drag moves it, a tap takes it away". The rows of the owner are in `docs/acceptance/wake-sleep-lines.md`. | proof |
| Import is blocked while signed in, and Grove says why | `ui/settings/settings_tabs.dart`, `state/store_data.dart` | `ui/settings/settings_sync_test.dart` group "Import and the sync": "signed in: Import is blocked, and Grove says why". `state/import_sync_test.dart` (14 tests). Open card: Q-22 (what a sign-out, an import and a sign-in do). | proof |
| The name on the screen is "Grove" on the 4 systems; the app id stays `local.grove.grove` | `app/macos/`, `app/windows/`, `app/android/`, `app/ios/` | `app_name_test.dart` (10 tests) groups "the name on the screen is Grove", "the id and the data folder stay". Q-26, Q-30 and Q-40 answered B. | proof |
| An idle window draws few frames | `ui/theme/slow_clock.dart` | `ui/theme/slow_clock_test.dart` (10 tests). RV "an idle window asks for a frame only when the circles move, not at every refresh of the screen", "an idle window with motion off asks for no frame". `ui/planner/planner_now_line_test.dart`. `scripts/flutter_idle.sh` measures it by hand. Open card: Q-37 (the pulse of the now line). | proof |
| Release files for the 4 systems, not signed, and the `release` workflow | `scripts/flutter_release.sh`, `.github/workflows/release.yml` | No test. The workflow starts by hand only (`workflow_dispatch`). `docs/acceptance/F12-release.md` says it has no run yet, because GitHub starts it only when its file is on `main`. See also the row of §11.3. | built, no proof |

## PLAN.md §1.1 — the 27 lines

These lines are a short form of the rows above. They are not in the counts.
The first column is the short form of the line in PLAN.md §1.1.

| # | Line of §1.1 | State | Why |
|---|---|---|---|
| 1 | `scripts/install.sh` builds, installs, Desktop icon | not for this platform | A Mac script. A Flutter install is part of the release builds. |
| 2 | Own app icon | proof | `app_icons_test.dart`. |
| 3 | Planner: create by drag, by double click, by a task from the list | proof | Drag, double click and task drop have proof (PV, planner_menu_test, SP). |
| 4 | Planner: move, snap to 15 minutes | proof | PV, DEV. |
| 5 | Planner: resize top and bottom, 15 minutes at least | proof | PV, DEV. |
| 6 | Planner: overlaps shown, as layers (PLAN.md §5.1.3) | proof | Overlaps have proof (PM, PV). They cascade in layers, not in columns. |
| 7 | Planner: drag a block to another day | proof | PV, DEV. |
| 8 | Planner: live label during a drag | proof | PC reads the words of the label. |
| 9 | Planner: undo and redo | proof | PV, DEV. |
| 10 | Planner: keys for the selected block | proof | Arrows, Shift+arrows, Return, Delete, N, Space, ⌘D and the zoom keys have proof (PV, planner_paths_test). |
| 11 | Planner: ⇧ at the drop pushes later blocks | proof | `planner_paths_test.dart` group "Shift at the end of a drag"; PS and PM. |
| 12 | Planner: "Fit" | proof | PV, planner_fit_test. |
| 13 | Tasks: quick add in plain words | proof | TP and the parser tests. |
| 14 | Tasks: buckets, lists, tags, subtasks, repeats | proof | TI, TP, store tests. |
| 15 | Calendar: day, 3-day, week, month; repeating events | proof | Week (Planner), month and repeats have proof. Day and 3-day modes are off by PLAN §5.1 (2026-10-09). |
| 16 | Notes: editor, check lists, `[[links]]`, backlinks | proof | RT, NV. |
| 17 | Notes: `- [ ] text` makes a task | proof | NV and the store tests. |
| 18 | Notes: `@fri 9am` offers an event or block | proof | RT. |
| 19 | Daily and weekly note | proof | NV and the store tests. |
| 20 | Every connection of §5.5 | proof | Every row of §5.5 has proof. |
| 21 | Four themes, live; light and dark | proof | RV and the pictures. |
| 22 | Motion switch; Reduce Motion | proof | RV. |
| 23 | ⌘K command palette | proof | `command_palette_test.dart` (the box, the rows, the labels) and the store tests. |
| 24 | Notifications | partly | The list and the calls have proof with a fake system. No real reminder was seen. |
| 25 | Menu bar item with the next block and a quick-add field | partly | The Now and Next lines and the "New task" line have proof. Q-7 (answer A) chose a line, not a text field, so the menu bar has no quick-add field. PLAN.md §5.7 has a note about this. |
| 26 | Data stays; daily backup; JSON export and import | proof | Backup, export and import have proof, with buttons in Settings ▸ Data. |
| 27 | The test script passes | proof | `./scripts/flutter_test.sh` on 2026-10-12: "+2779: All tests passed!". |

## Gaps

Only the rows that have no full proof: 8 rows of 256. Layouts A, C, D, the week
view of tasks, the layout picker, the 3-day view, the week strip and a block
dropped on a month day are not gaps: PLAN.md turns them off.

### Day Planner

No row of §5.1 is open. Two small things are not rows:

- The small subtask marks in a block and in the subtask editor play no
  check-burst (`ui/planner/block_view.dart`, `ui/planner/block_subtask_editor.dart`,
  `ui/goals/goal_subtasks.dart`). The Mac app had none there.
- A change of layout takes 220 ms with an ease-out curve. The Mac app used a
  spring. PLAN.md §5.1.3 has a note.

### The rest of the app

On the "later" list of the owner (PLAN.md §15.1):

1. **`grove://` links are not handled** (`missing`).
2. **Images: no paste and no drop** (`partly`). The button "Add an image" works.
3. **The settings that are not in the `settings` table** (`partly`). The theme,
   motion, accent, hour height, working hours, first length, busy-day limit, week
   start, mood tint, reminder switch and its minutes, strip fold and panel widths
   are in a `Prefs` file on the device. They are not in an export and they do not
   sync.
4. **Launch time and frame times have no limit** (`built, no proof`). The perf
   script (`app/integration_test/perf_test.dart`) runs by hand on macOS only and
   no limit fails it.

Done in the branch `feat/xp-retire-swift` (draft PR #27), not on this branch:

5. **Bundle id** (`partly`). It is `local.grove.grove` here and `local.grove.app`
   there (Q-26, Q-30).
6. **Install on the Mac with one command** (`partly`). `scripts/flutter_install.sh`
   is there. Nothing is signed (Q-31, answer A).

Open:

7. **Labels** (`partly`). No test walks all buttons of all screens. Some inner
   tap targets have no screen-reader name (`ui/tasks/subtask_row.dart`,
   `ui/tasks/task_inspector.dart`, inner nodes of the planner). This was not
   audited in full.
8. **A reminder that the system really shows** (`built, no proof`). Only a
   person with the 4 devices can check it.

### Differences between PLAN.md and the app

The check of 2026-10-12 found six. Each one now has a correction or a note in
PLAN.md, and a line in `docs/assumptions.md`:

- §5.7 (and the lines of §1.1 and §5.2 that name the menu bar): the tray has a
  line "New task", not a text field (Q-7, answer A).
- §5.1.3: the function `layoutColumns` is in no code; the grid uses layers.
- §5.1.3: 220 ms ease-out, not the spring.
- §5.1.2: the full border of a task block with a priority.
- §5.1.4: no ghost with the time, also in the build notes.
- The Swift API list of §5.1 still shows `layoutColumns`. It is a part of the
  old Swift text and it is not changed.

### Things that wait for the owner

- Q-22: what a sign-out, an import and a sign-in do. Open, asked. Blocks nothing now.
- Q-36: a rename or a move of a block loses its linked note. Open, default. Blocks nothing now.
- Q-37: keep the pulse of the now line or not. Open, default. Blocks nothing now.

Answered cards that the rows depend on: Q-7 (tray: a line, no field), Q-8
(closing the window quits Grove), Q-15 (`file_selector`), Q-16 (`url_launcher`),
Q-17 (one picture checked on macOS only), Q-26 and Q-30 (the bundle id).

## Not verified by a machine

Only a person with real devices can check these.

- A reminder that really shows on macOS, Windows, Android and iOS, and the
  permission question of each system.
- The "Mark done?" notification at the end of a focus session, and its button.
- A click on a real reminder that opens Grove on the right day.
- The tray icon and its menu on macOS and on Windows.
- A real sync between two devices with a real Supabase project. The SQL ran
  only on a plain Postgres on CI. The engine ran only against a fake server.
  No keys were used.
- The login email with its code.
- Signed installs and installers for each system, and the app icon in the
  Dock, the task bar and the home screen.
- A file from the Mac app's "Export JSON…" chosen in a real file window by a
  user. The import rule and the Settings button are tested with a fake file
  window and a Mac-shaped file.
- The feel of a drag: 60 pictures a second, the small tick at each snap on a
  phone, the scroll near an edge.
- The look and the feel of the check-burst (the spring) and of the slide of a
  row. The tests check the states and the timing, not the picture.
- Launch time under 1 s and memory use on each system.
- The look of the real fonts. The tests draw text with a box font, so the
  pictures do not show letter shapes.
- Screen readers (VoiceOver, TalkBack, Narrator).
- The device tests (`app/integration_test/planner_test.dart`, 19 tests): not run
  on this Mac, and CI for this branch has not run yet. The newest green
  `flutter` run on the base is run 38246026526 at commit `b9eeb19`. No device
  run is claimed for this branch.

## Counts

Counted by a script from the State cells of the tables above, on 2026-10-12.

PLAN.md table (the tables §0 to §12):

| Part | Rows | `proof` | `partly` | `built, no proof` | `missing` | `missing (off by PLAN)` | `missing (off by the owner)` | `not for this platform` |
|---|---|---|---|---|---|---|---|---|
| §0 to §3 | 9 | 6 | 1 | 0 | 0 | 1 | 0 | 1 |
| §4 | 15 | 15 | 0 | 0 | 0 | 0 | 0 | 0 |
| §5.1 | 73 | 72 | 0 | 0 | 0 | 1 | 0 | 0 |
| §5.2 | 32 | 31 | 0 | 0 | 0 | 1 | 0 | 0 |
| §5.3 | 12 | 11 | 0 | 0 | 0 | 1 | 0 | 0 |
| §5.4 | 15 | 13 | 1 | 0 | 1 | 0 | 0 | 0 |
| §5.5 | 15 | 15 | 0 | 0 | 0 | 0 | 0 | 0 |
| §5.6 and §5.7 | 11 | 9 | 0 | 1 | 0 | 0 | 0 | 1 |
| §5.8 | 14 | 11 | 1 | 0 | 0 | 2 | 0 | 0 |
| §5.9 | 11 | 11 | 0 | 0 | 0 | 0 | 0 | 0 |
| §6 | 15 | 15 | 0 | 0 | 0 | 0 | 0 | 0 |
| §7 to §12 | 34 | 27 | 2 | 1 | 0 | 3 | 0 | 1 |
| **All** | **256** | **236** | **5** | **2** | **1** | **9** | **0** | **3** |

236 of 256 rows have proof. 12 rows are turned off by PLAN.md or are not for this platform. 8 rows are open; the part "Gaps" lists them.

"Things the port added" (not in the count above): 17 rows. 14 `proof`, 1 `partly`, 1 `built, no proof`, 1 `missing (off by the owner)`.
