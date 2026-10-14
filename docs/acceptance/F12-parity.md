# F12 — feature checklist of the Flutter app against PLAN.md

Checked on 2026-10-11. Branch `feat/xp-parity`, made from
`feat/cross-platform-flutter` at commit `dbce123`.

This file answers one question: for each feature and each rule of `PLAN.md`,
is it in the Flutter app (`app/`), and does a test or a picture really check
it? I opened the code and the tests for each row. I did not copy claims from
the other files in `docs/acceptance/`.

## What I ran

- `./scripts/flutter_test.sh` on this Mac: exit 0. The format check is ok.
  `flutter analyze` says "No issues found!". `flutter test` says
  "+1904: All tests passed!". No test failed and none was flaky.
- One test is skipped by its own code off macOS: the futuristic Day Spread
  picture (`_parked` in `app/test/ui/goldens/f9_golden_test.dart`, card Q-17).
- I did not run the device tests (`app/integration_test/planner_test.dart`).
  I read them. CI run 38136166701 (commit `dbce123`) is green on the 4 jobs:
  macOS, Windows, iOS, Android. Each job runs the tests, a build and the
  device tests.
- I made no call to a real Supabase project and I did not open the key file.

## How to read the table

- Code paths start at `app/lib/`. Test paths start at `app/test/`.
- Short names for the test files that come up often:

| Short name | File |
|---|---|
| DEV | `app/integration_test/planner_test.dart` (device tests, 8 steps, run on CI on the 4 systems) |
| PV | `ui/planner/planner_view_test.dart` |
| PR | `ui/planner/planner_rules_test.dart` |
| PM | `core/planner/planner_math_test.dart` |
| PS | `state/planner_store_test.dart` |
| TP | `ui/tasks/tasks_pane_test.dart` |
| TI | `ui/tasks/task_inspector_test.dart` |
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

The states:

| State | What it means here |
|---|---|
| `proof` | A test or a picture really checks this behaviour. For a thing on the screen, the test goes through the screen (widget test, picture or device test). For a pure rule (maths, parser, data), a unit test is enough. |
| `built, no proof` | The code is there and is wired to the screen. No test goes through the screen for it. When a test checks only the rule under it, the proof cell names that test. |
| `partly` | A part is there. The row says what is missing. |
| `missing` | Not in the Flutter app. `missing (off by PLAN)` means PLAN.md itself turns it off (§0 CHOICES, or a later owner note in the text). |
| `in work (F10-screens)` | The rule or the store is ready. The screen comes with F10-screens (Settings, Garden, plant, sync card). It is not on this branch. |
| `not for this platform` | A rule for the Swift build of the Mac app, or a thing phones do not have. |
| `waits for the owner` | An open question card in `docs/questions.md` decides it. |

## The table

### §0 to §3 — choices, stack

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §0 | Layout B (Day Spread) is the one layout | `ui/spread/day_spread_view.dart` | DS "three columns: the tasks, the timeline, the note of today". DEV "today: the Day Spread opens, a tap on a task opens its panel". Pictures `spread_desktop_*.png`. | proof |
| §0 | The `AppLayout` list stays, so a layout can be added later | none | `app/lib` has no layout enum. The shell knows one layout. | missing |
| §0 | Default theme is Grove | `state/store_appearance.dart` | `state/theme_store_test.dart` "the default is grove with motion on". | proof |
| §0 | App name "Grove" | `app/macos/Runner/Configs/AppInfo.xcconfig`, `app/android/app/src/main/AndroidManifest.xml` | No test. The product name on macOS and the label on Android are `grove`, with a small g. | partly |
| §0 | Bundle id `local.grove.app` | the same files, `app/android/app/build.gradle.kts`, `app/ios/Runner.xcodeproj/project.pbxproj` | The id is `local.grove.grove`. So the Flutter app and the Mac app are two apps on a Mac, each with its own data. | waits for the owner (Q-26) |
| §1 | Works with no account and no network | `data/database.dart` | `ui/auth/sync_card_test.dart` "a build with no keys says that there is no sync". All store tests run on a local database only. | proof |
| §2, §3, §13, §14 | Swift 6, SwiftUI, AppKit, no Xcode, no SwiftData, the Swift package layout, the Mac milestones and pitfalls | none | These are rules for the Swift build. The Flutter stack is in `docs/cross-platform-plan.md`. | not for this platform |

### §4 — data

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §4 | SQLite with WAL and foreign keys on; version number; migrations in order | `data/database.dart` (lines 58–59), `data/migrations.dart` | `data/database_test.dart` "migrations create the schema", "migrations are idempotent", "a transaction rolls back on error", "a version 1 database keeps its data", "deleting a task cascades to subtasks and blocks". No test reads the WAL setting. | proof |
| §4 | The database file is in the data folder of the app | `main.dart` | No test of the place. Flutter uses the app-support folder of each system. It is not the folder of the Mac app. | built, no proof |
| §4.1 | Tables and columns of the Mac app (lists, tasks, events, exdates, notes, links, tags, settings) | `data/migrations.dart`, `data/repos.dart` | `data/database_test.dart` "there are eight migrations: the seven of the Mac app, and one of this app only". `data/data_export_test.dart` "the file has the same rows and columns as a Mac export (schema $version)". Differs: Flutter is on schema 8 (7 is `block_subtasks`; 8 is `goal_subtasks`, of this app only, see `docs/acceptance/goal-subtasks.md`); the Mac `main` is on 6. Flutter also has sync columns ("the sync columns do not change the shared schema number"). | proof |
| §4.1 | One daily note for a day, one weekly note for a week | `data/repos.dart` | `data/database_test.dart` "a daily note is unique per day". | proof |
| §4.1 | Full-text search, no accents | `data/search_index.dart` | `data/database_test.dart` "search finds words and prefixes", "search ignores accents and quotes". | proof |
| §4.1 (migration 2) | Images are rows in the database, so the backup and the export hold them | `data/attachment_repo.dart` | `data/attachment_repo_test.dart` "add and get round trip", "images survive the daily backup". `data/data_export_test.dart` "names its format and holds every table". | proof |
| §4.1 (migration 2) | An image is made smaller: at most 1600 px on the long side | none | Not found in `app/lib`. | missing |
| §4.1 (migration 2) | An image in the text is `![alt](grove-image:ID)` | `core/parsing/markdown_spans.dart`, `ui/editor/` | RT "a new image goes in as markup and is stored". `core/parsing/markdown_spans_test.dart` "image hides its markup". | proof |
| §4.1 (migration 2) | An image that no text uses is deleted | `data/attachment_repo.dart` | `data/attachment_repo_test.dart` "sweep removes old unreferenced images only", "an image stays when another body still uses it". `state/daily_backup_test.dart` "a new copy also drops the old images that no text uses". Differs: the clean-up runs with the daily copy and keeps fresh images. PLAN says at each save. | proof |
| §4.2 | `DayKey`, `WallTime`, `RecurrenceRule`; minutes since midnight | `core/model/` | `core/model/day_key_test.dart`, `core/model/models_test.dart`. | proof |
| §4.3 | Database wrapper, one repo per table, each write updates the search | `data/database.dart`, `data/repos.dart` | `data/database_test.dart` "task CRUD", "events in range and series", "tags are case-insensitive and replaceable", "links replace and backlink", "settings round trip". `data/reference_indexer_test.dart` "search sees words, not ids or markup". | proof |
| §4.4 | Daily backup at launch; the newest 14 stay | `data/backup.dart`, `services/backup_schedule.dart` | `data/database_test.dart` "the daily backup is made once and trimmed". `state/daily_backup_test.dart` "only the newest 14 copies stay". Differs: Flutter also checks while the app stays open (`services/backup_schedule_test.dart` "the timer checks while Grove stays open over midnight"). | proof |
| §4.4 | Settings ▸ Data: "Export JSON…" with all tables | `data/data_export.dart`, `state/store_data.dart` | Rule only: `data/data_export_test.dart` "names its format and holds every table"; `state/settings_test.dart` "a store exports and another one imports". No button and no save window: a user cannot export. | in work (F10-screens) |
| §4.4 | Settings ▸ Data: "Import JSON…" replaces all data after a question | `data/data_export.dart`, `state/store_data.dart` | Rule only: `data/data_export_test.dart` "import replaces what was there", group "JSON from the Mac app", group "bad files change nothing" (13 tests). No button, no question window. | in work (F10-screens) |
| §4.4 | Settings ▸ Data: "Show data folder" | none | Nothing found. | in work (F10-screens) |

### §5.1 — Day Planner

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.1 | Planner screen is a fixed week; Today is the timeline of today; no mode picker | `ui/planner/planner_kind.dart`, `ui/planner/planner_view.dart` | `ui/planner/planner_kind_test.dart` "the week has 7 days and starts on Monday", "today shows only today". PV "shows the week, the hours and the now line". DS "the screen keeps its own day: today, or tomorrow" (since 2026-10-12 a switch in the header of Today shows only tomorrow: `docs/acceptance/today-tomorrow.md`). | proof |
| §5.1 | Previous, Next and Today in the header | `ui/planner/planner_view.dart` | PV "Previous and Next move one week". | proof |
| §5.1.1 | Grid maths: minute to point and back; the grid is 00:00–24:00 | `ui/planner/planner_geometry.dart` | PR "minutes and points", "day columns start on whole points and fill the grid". | proof |
| §5.1.1 | Zoom stays between 36 and 160 points for an hour | `ui/planner/planner_geometry.dart` | PR "zoom stays in its range". | proof |
| §5.1.1 | Pinch to zoom | none | Not found. | missing |
| §5.1.1 | On open and on "Today" the grid scrolls to now minus 1 hour | `ui/planner/planner_grid.dart` | No test. | built, no proof |
| §5.1.1 | Hour lines, half-hour lines, hour labels | `ui/planner/planner_grid.dart` | PV "shows the week, the hours and the now line". Pictures `planner_desktop_*.png`. | proof |
| §5.1.1 | Faint tint for working hours (09–18) | `ui/planner/planner_grid.dart` (line 1170) | No test names it. It is in the pictures only. | built, no proof |
| §5.1.1 | Now line: 2 points, a dot, a slow pulse when motion is on | `ui/planner/planner_grid.dart` (`_NowLine`) | PV "shows the week, the hours and the now line". `ui/theme/theme_math_test.dart` "the now line pulses between 1 and 0.45 in 3.2 seconds". | proof |
| §5.1.1 | Past time of today is faded | `ui/planner/planner_grid.dart` | No test. | built, no proof |
| §5.1.2 | A block shows its time, title and length; long text is cut; a short block has one line | `ui/planner/block_view.dart` | PR "a block gives lines to the title and to the summary". Pictures `planner_desktop_*.png`, `planner_phone_grove_light.png`. | proof |
| §5.1.2 | A task block has a check box; a click finishes the task | `ui/planner/block_view.dart` | PV "the check box marks the task done". | proof |
| §5.1.2 | A small ✎ icon when the block has linked notes | none | `PlannerBlock.hasNote` is not used by `block_view.dart`. | missing |
| §5.1.2 | A done block is faded and struck through | `ui/planner/block_view.dart` (line 258) | No test. | built, no proof |
| §5.1.2 | Event: fill at 14 % and a 3-point left border. Task block: dashed 1-point border and a 3-point left border | `ui/planner/block_view.dart` | Pictures only. Differs: the event fill is 16 % and the task fill is 10 %. A block with a priority has a full coloured border, not the dashed one. | partly |
| §5.1.2 | Subtasks in a task block: rows, "+3 more", "1/4 subtasks", "1/4" in the title row | `ui/planner/block_view.dart` | PV "a tall block shows subtasks, then "+N more"", "a short block shows a count of the subtasks". PR group "rows of a block with subtasks" (9 tests). | proof |
| §5.1.2 | All-day events are in a strip above the grid | `ui/planner/planner_view.dart` (`_allDayStrip`) | Store only: `state/recurring_event_store_test.dart` "a repeating all-day event shows in the all-day row". | built, no proof |
| §5.1.2 | A day of a repeating event has its own id | `state/store_events.dart` | `state/recurring_event_store_test.dart` "an occurrence can be found by id". `core/recurrence/recurrence_test.dart` group "occurrence ids and events". | proof |
| §5.1.3 | Overlaps are always allowed and both blocks are in view | `core/planner/planner_layers.dart` | PS "overlap is allowed". PV "two blocks at the same time are both in view". DEV "overlap: two blocks at the same time are both in view". | proof |
| §5.1.3 | Overlapping blocks stand side by side in equal columns | `core/planner/planner_layers.dart`, `core/planner/planner_math.dart` | PM group "layout (overlaps cascade, they never share the width)". Differs: the blocks cascade in layers, one over the other. The Mac source does the same (`Sources/GroveCore/Planner/PlannerLayers.swift`). The text of PLAN.md is older. | partly |
| §5.1.3 | A layout change moves with a spring (0.28 s); at once when motion is off | `ui/planner/planner_grid.dart` | No test. Differs: 220 ms with an ease-out curve, not a spring. | built, no proof |
| §5.1.4 | Drag on empty time makes a draft; on release a title field opens; a new task and block are made | `ui/planner/planner_grid.dart`, `state/store_planner.dart` | PV "a mouse drag on empty time makes a block", "a short drag makes 30 minutes; the start snaps to 15". DEV "create: a drag on empty time makes a block". PS "a draft creates a task and a block, and undo removes both". | proof |
| §5.1.4 | Esc cancels the draft | `ui/planner/inline_title_field.dart` | PV "Escape closes the draft and saves nothing". | proof |
| §5.1.4 | A typed title that matches an open task offers "Schedule existing task" | `ui/planner/planner_grid.dart` (line 1427) | No test. | built, no proof |
| §5.1.4 | ⌘ held at release makes a plain event | `ui/planner/planner_grid.dart` (`_createEnd`) | Store only: PS "a draft as event makes a plain event". | built, no proof |
| §5.1.4 | Double click on empty time makes a 30-minute draft | `ui/planner/planner_grid.dart` (`_columnTapped`) | No test. | built, no proof |
| §5.1.4 | A task dragged from a list onto the grid gets a block; the length is its estimate, at least 15 minutes | `ui/planner/payload_drag.dart`, `ui/planner/planner_grid.dart` | SP "a task dragged from the panel onto a day gets a block". PS "a task dropped from the tray uses its estimate", "a short estimate makes a block of at least fifteen minutes". | proof |
| §5.1.4 | A ghost with the time follows the pointer while a task is dragged over the grid | none | The dragged row shows a small label; the block shows at the drop. PLAN says this is acceptable when the place is not known. | partly |
| §5.1.4 | A sticky note dragged onto the grid gets that time | `ui/planner/sticky_strip.dart` | PV "a note dragged onto the grid gets that time". | proof |
| §5.1.4 | Drag the body of a block to move it; the database is written only at the end | `ui/planner/planner_grid.dart` | PV "a mouse drag moves a block and snaps to 15 minutes", "the label shows the new time during the drag" (the store has the old time until the pointer goes up). DEV "drag: a block moves to a new time and to the next day". | proof |
| §5.1.4 | Live label `11:15 – 12:45 · 1h 30m` during a drag | `ui/planner/planner_grid.dart`, `core/planner/planner_math.dart` | PV "the label shows the new time during the drag" checks that the label is there. PM group "label" checks the words. Missing: no test reads the words on the screen. | partly |
| §5.1.4 | A drag to the side moves the block to another day | `ui/planner/planner_grid.dart` | PV "a drag to the side moves a block to the next day". DEV "drag: a block moves to a new time and to the next day". | proof |
| §5.1.4 | Drag the top edge: the start changes | `ui/planner/block_view.dart` | PV "the top edge changes the start; 15 minutes is the least". | proof |
| §5.1.4 | Drag the bottom edge: the end changes | `ui/planner/block_view.dart` | PV "the bottom edge changes the end". DEV "resize: the bottom edge changes the end". | proof |
| §5.1.4 | The pointer shows a resize arrow on an edge | `ui/planner/block_view.dart` (line 584) | No test. | built, no proof |
| §5.1.4 | Snap is 15 minutes, always | `core/planner/planner_math.dart` | PV "a mouse drag moves a block and snaps to 15 minutes". PM groups "snap" and "the 15 minute grid". | proof |
| §5.1.4 | At least 15 minutes; a block stays inside the day | `core/planner/planner_math.dart` | PM groups "clamp" and "resize". PV "the top edge changes the start; 15 minutes is the least". PS "a block that ends at midnight round trips". | proof |
| §5.1.4 | ⇧ held at release pushes the later blocks down (ripple), with a "pushed 2 blocks" message | `ui/planner/planner_grid.dart` (`_blockDragEnd`), `state/store_planner.dart` | Store and maths only: PS "ripple pushes later blocks"; PM group "ripple". No test holds Shift at a drop. No test reads the message. | built, no proof |
| §5.1.4 | A block released over the sticky strip loses its time; the task stays | `ui/planner/sticky_strip.dart` | PV "a task block dragged up to the strip loses its time". | proof |
| §5.1.4 | A block dragged onto a day of the week strip or the month moves to that day | none | There is no week strip. A month day takes a task, not a block (`ui/calendar/month_view.dart` line 232). | missing |
| §5.1.4 | The grid scrolls by itself when a drag is near the top or the bottom | `ui/planner/planner_grid.dart` | No test. | built, no proof |
| §5.1.4 | A click selects a block | `ui/planner/planner_grid.dart` | PV "a press on a block does not start a new block" (the selection is that block). The look of the outline is in no test. | proof |
| §5.1.4 | A click on an event block opens its card | `ui/calendar/event_editor.dart` | EE "a click on an event of the planner opens its card, and the keys stay with the planner". | proof |
| §5.1.4 | A click on a task block opens the panel of the task | `state/store_planner.dart`, `ui/tasks/task_inspector.dart` | Store only: `state/task_description_test.dart` "a click on a task block opens its panel". | built, no proof |
| §5.1.4 | ⌘-click selects more blocks; a drag moves all of them | `ui/planner/planner_grid.dart` | Store only: `state/task_description_test.dart` "an extending click builds a selection and leaves the panel alone". | built, no proof |
| §5.1.4 | Right-click menu: Duration, Colour, Duplicate, Split in two, Mark done, Unschedule, Delete | `ui/planner/planner_grid.dart` | Store only: PS "duplicate, split and duration", "a block shorter than half an hour cannot split", "unschedule keeps the task and returns it to the tray". No test opens the menu. | built, no proof |
| §5.1.4 | Menu line "Open / create linked note" | none | Not found. The Mac source has no such line either. | missing |
| §5.1.4 | A day of a repeating event that is moved or resized asks "This event only / All events" | `ui/planner/planner_view.dart` (line 113), `ui/planner/planner_dialogs.dart` | Store only: `state/recurring_event_store_test.dart` group "move and resize" (9 tests). The same question from the card of the event has a screen test (EE "a day of a series asks which events to change"). No test drags such a block on the grid. | built, no proof |
| §5.1.4 | A small tick is felt each time the snap value changes | `ui/planner/planner_grid.dart` | No test. | built, no proof |
| §5.1.5 | `snap`, `clampMove`, `resizeTop`, `resizeBottom`, `ripple`, `firstFreeSlot`, `label` are unit-tested | `core/planner/planner_math.dart` | PM groups "snap", "clamp", "resize", "the 15 minute grid", "ripple", "free slot", "label". | proof |
| §5.1.6 | ↑ / ↓ move the block by 15 minutes | `ui/planner/planner_grid.dart` | PV "the arrows move the selected block". | proof |
| §5.1.6 | ⇧↑ / ⇧↓ change the length | `ui/planner/planner_grid.dart` | PV "Shift with an arrow changes the length". | proof |
| §5.1.6 | ← / → move the block to the day before or after | `ui/planner/planner_grid.dart` | PV "the arrows move the selected block". | proof |
| §5.1.6 | Return renames | `ui/planner/inline_title_field.dart` | PV "Enter renames a task block". | proof |
| §5.1.6 | Space marks the task done or not done | `ui/planner/planner_grid.dart` (line 861) | No test presses Space. | built, no proof |
| §5.1.6 | ⌘D makes a copy right after | `ui/planner/planner_grid.dart` (line 734) | Store only: PS "duplicate, split and duration". | built, no proof |
| §5.1.6 | Delete takes the block away, with undo | `ui/planner/planner_grid.dart` | PV "Delete removes the block; Escape clears the selection". | proof |
| §5.1.6 | ⌘T goes to today | `ui/shell/root_view.dart` | RV "Ctrl with a number opens a screen", "on a Mac the key is Command". `state/clock_store_test.dart` "View ▸ Today goes to the day of the clock". The scroll to "now" is not checked. | proof |
| §5.1.6 | ⌘+ / ⌘- zoom; "Zoom in" and "Zoom out" buttons in the header | `ui/planner/planner_grid.dart` (lines 736–742), `ui/planner/planner_view.dart` (lines 497–505) | No test presses the keys or the buttons. | built, no proof |
| §5.1.6 | N starts a block in the next free time | `ui/planner/planner_grid.dart` | PV "N starts a new block in the next free time". `state/clock_store_test.dart` "the next gap starts at the minute of the clock on its day". | proof |
| §5.1.6, §1.1 | ⌘Z and ⇧⌘Z undo and redo a planner change | `ui/store_app.dart`, `state/mutation.dart` | PV "Undo puts a moved block back; Redo moves it again", "Undo removes a new block". DEV "undo: Undo puts a moved block back; Redo moves it again". | proof |
| §5.1.7 | Sticky strip under the day numbers: the tasks of the day with no time, each with its length | `ui/planner/sticky_strip.dart`, `ui/planner/sticky_rules.dart` | PV "the strip shows the task of the day as a sticky note". PS "timeless tasks are the day tasks with no block". PR group "StickyRules". | proof |
| §5.1.7 | The strip can fold | `ui/planner/sticky_strip.dart` | PV "the strip shows the task of the day as a sticky note" (folds, says "1 with no time", the choice is saved). | proof |
| §5.1.7 | A task from a list dropped on a day is planned for that day with no time | `ui/planner/sticky_strip.dart`, `state/store_planner.dart` | Store only: PS "a drop on the day strip plans the day with no time and removes the old block", "a strip drop is one undo step that brings back the block". | built, no proof |
| §5.1.7 | A click on a sticky note opens the task | `ui/planner/sticky_strip.dart` | No test. | built, no proof |
| §5.1.7 | "Fit" puts the task in the next free time | `ui/planner/sticky_strip.dart`, `state/store_planner.dart` | PV "the fit button gives the task the next free time". PS "fit uses the first free gap", "fit replaces the old block". | proof |
| §5.1.7 | The new block grows in after "Fit" | none | I found no grow-in animation in `app/lib/ui`. | missing |
| §5.1.7 | "Plan my day": a list first, Apply or Cancel, one undo step | `ui/planner/planner_dialogs.dart`, `state/store_planner.dart` | PV "the list shows the plan; Apply makes the blocks", "with nothing to plan, a short message shows". PS "plan my day orders by priority". Cancel is in no test. | proof |
| §5.1.7 | Day totals in the header: "4h 30m planned · 2h 10m free · 3/6 done" | `ui/planner/planner_view.dart` (lines 338–340) | No test reads the line. Differs: the words are "… free in working hours …". | built, no proof |
| §5.1.7 | Card for yesterday: "Move to today / Leave" | `ui/tasks/notice_cards.dart`, `state/store_roll_over.dart` | TP "the card of yesterday moves the open tasks to today", ""Leave" closes the card of yesterday". `state/roll_over_store_test.dart` (9 tests). | proof |
| §5.1.7 | Focus: "Start focus" in the menu of a block | `ui/planner/planner_grid.dart`, `state/store_focus.dart` | Store only: `state/focus_store_test.dart` "starting focus counts down to the end of the block". No test opens the menu. | built, no proof |
| §5.1.7 | Focus: a floating small timer counts down | none | Not found. Only the menu lines "Start Focus" and "Stop Focus" are on the screen. | missing |
| §5.1.7 | Focus: "Mark done?" when the time is up | `state/store_focus.dart`, `services/system_notifier.dart` | `state/focus_store_test.dart` "starting focus sends the end notification", "when the time is up the session asks to mark done", "the notification button marks the task done" (the system is a fake). Missing: nothing on the screen asks. | partly |

### §5.2 — Tasks

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.2 | Buckets: inbox, day, week, someday | `core/model/`, `data/repos.dart` | `data/database_test.dart` "task queries by bucket". `state/task_store_test.dart` "moving to a week sets the Monday". | proof |
| §5.2 (2026-10-09) | The Today page lists the tasks of today only, with "1 of 2 done" | `ui/tasks/tasks_pane.dart` | TP "an empty day says so", "Return in the quick-add field adds a task to today", "a click on the check box marks the task as done" (reads "1 of 2 done"). | proof |
| §5.2 (2026-10-09) | Three left panels (Notes, Tasks, Goals) from a dock on Today and Planner; one is open at a time | `ui/shell/left_dock.dart` | RV "the dock is on Today and the Planner only", "a dock button opens its panel beside the screen". `ui/shell/shell_model_test.dart` "a click on another panel replaces the open one". | proof |
| §5.2 (2026-10-09) | The Tasks panel lists only late tasks and tasks with no day | `ui/tasks/tasks_pane.dart`, `state/rules/` | TP "late tasks come first, then the tasks with no day", "quick-add puts the task in the inbox", "the tasks checked off today can be opened again". | proof |
| §5.2 (2026-10-09) | A task dropped on the planner keeps one block, at the new time | `state/store_planner.dart` | PS group "one block per task" (11 tests). SP "a task dragged from the panel onto a day gets a block". | proof |
| §5.2 (2026-10-09) | A new task is kept when the user clicks away with no Enter | `ui/tasks/quick_add_field.dart` (`_focusChanged`) | No test for the task field. | built, no proof |
| §5.2 | Week view of tasks: 7 day columns and "Anytime this week" | none | Used by Layout C and the "This Week" item of Layout A. Both are off by §0. | missing (off by PLAN) |
| §5.2 | Row: check box, title, chips for list, time, due, length, repeat, note, tags | `ui/tasks/task_row.dart` | TP "the labels of a row" (reads the length and the due day), "a click on the check box marks the task as done". Pictures in `app/test/ui/tasks/goldens/` (14). Missing: no test reads the list, time, "Repeats", "Notes" and tag chips. | partly |
| §5.2 | Priority is a coloured 3-point bar on the left | `ui/tasks/task_row.dart` | Pictures in `app/test/ui/tasks/goldens/`. Differs: a full coloured outline, not a bar. The Mac source does the same (`Sources/Grove/Tasks/TaskRow.swift`), and `docs/cross-platform-plan.md` F8 says "priority outline". | proof |
| §5.2 | Row menu and row drags (move, priority, rename, delete) | `ui/tasks/task_row.dart` | TP "the menu of a row moves the task", "the menu sets the priority", "the menu renames and deletes". | proof |
| §5.2 | Task panel: title, list, tags, priority, day, due, length, repeat | `ui/tasks/task_inspector.dart` | TI "the fields of the task", "Return in the title renames the task", "the row of buttons moves the task", "priority", "length", "due date: add and remove", "repeat", "list", "tags: add and remove". | proof |
| §5.2 | Task panel: subtasks with a name, a description, a length and a done box | `ui/tasks/task_inspector.dart` | TI group "subtasks" (6 tests). TP "subtasks: add, count, check and hide". | proof |
| §5.2 | Task panel: "Linked here" and "Created from note X" | `ui/tasks/task_inspector.dart` | TI "the note the task came from, and the items that link to it". | proof |
| §5.2 | Rich task body: the same editor as notes (lists, headings, bold, `[[` mentions, images) | `ui/tasks/task_inspector.dart` | TI "the description is saved after a short stop". Missing: the description is a plain text field. No lists, no formatting, no `[[` list, no images in a task body. | partly |
| §5.2 | A task can be mentioned: `[[Title]]`, stored as `[[Title\|ID]]`; the id wins, then the exact title | `data/reference_indexer.dart`, `core/parsing/reference_parser.dart` | `data/reference_indexer_test.dart` group "resolving and canonical text" (11 tests). | proof |
| §5.2 | A mention hides its id; a click opens the task; a deleted target is struck out | `ui/editor/markdown_controller.dart` | RT "the id and the brackets of a mention are not seen", "a click on a mention opens it", "a mention of a thing that is gone is struck out". | proof |
| §5.2 | A rename rewrites the mention in every text | `data/reference_indexer.dart` | `data/reference_indexer_test.dart` "a rename rewrites every body that links". `state/task_store_test.dart` "body mentions become links and renames follow". | proof |
| §5.2 | A task dragged into a note puts a mention there | `ui/editor/rich_text_field.dart` | RT "a dropped task becomes a mention". A task body takes no drop (plain field). | proof |
| §5.2 | Quick-add field with chips that show what was understood | `ui/tasks/quick_add_field.dart` | TP "Return in the quick-add field adds a task to today", "a date in the text sends the task there and says so", "the field shows what the parser understood". | proof |
| §5.2 | Quick add with ⌘N from any place | none | No such shortcut in `app/lib/ui`. | missing |
| §5.2, §5.7 | Quick add in the menu bar | `services/tray_service.dart` | `services/tray_service_test.dart` ""New task" shows the window and asks for the quick-add box". The tray is a system menu; it has no text field. | waits for the owner (Q-7) |
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
| §5.3 | Tasks, blocks and notes can be dropped on a day | `ui/calendar/month_view.dart` (lines 232–234) | MV "a task can be dropped on a day". Missing: a block and a note cannot be dropped on a day. | partly |
| §5.3 | Week strip: Mon–Sun with dots, ‹ ›, today in the accent colour | none | Not found. The Mac source has no week strip either. | missing |
| §5.3 | The Calendar screen is the month only | `ui/shell/root_view.dart` | RV "a click on a screen name opens that screen". | proof |
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
| §5.4 | A link with no target is dotted; a click makes the note | `ui/editor/markdown_controller.dart` (line 833), `state/store_editor.dart` (lines 75–82) | `state/editor_store_test.dart` "opening a gone mention shows a toast". Differs: a click shows "That item is gone." and makes no note. The Mac source does the same (`Sources/Grove/AppStore+Editor.swift`). | partly |
| §5.4, §11.3 | `grove://` links are handled | none | Not found. Inside the app a mention opens by its id, so nothing is lost there. A `grove://` link from outside the app does nothing. | missing |
| §5.4 | `@date` words and `#tags` have their own colour | `core/parsing/markdown_spans.dart`, `ui/editor/markdown_controller.dart` | Rule only: `core/parsing/markdown_spans_test.dart` "an @date is marked where it can go to the planner", "tags and links". No test reads the colour on the screen. | built, no proof |
| §5.4 | The text is saved 500 ms after typing stops, and when the note closes | `ui/notes/note_editor_pane.dart` | NV "typed text is saved after a short wait", "text that was not saved yet is saved when the note closes". DEV "notes: the text of a note is saved a moment after typing". | proof |
| §5.4 | `[[` opens a list of notes, tasks and events; ↑ ↓ Return pick; Esc closes | `ui/editor/rich_text_field.dart`, `state/store_editor.dart` | RT group "the [[ list" (9 tests). `state/editor_store_test.dart` group "the [[ list" (5 tests). | proof |
| §5.4 | Daily note: one for a day, made at the first open, title "Friday, 2 October 2026", made from the template | `state/store_notes.dart` | `state/note_store_test.dart` "a daily note is made once from the template". NV ""Today" opens the note of today with the card of the day". | proof |
| §5.4 | Weekly note: one for a week, title "Week 40 · 28 Sep – 4 Oct" | `state/store_notes.dart` | `state/note_store_test.dart` "a weekly note uses the Monday". NV ""This week" opens the note of the week; the summary goes in". | proof |
| §5.4, §5.8 | The templates of the daily and the weekly note can be changed in Settings | `state/store_data.dart` | Rule only: `state/settings_test.dart` "a note template is kept in the settings table", "an empty template is allowed; reset brings back the default". No screen. | in work (F10-screens) |
| §5.4 | Pin, duplicate, delete with undo | `ui/notes/note_editor_pane.dart` | NV "pin, duplicate and delete from the header of the note", "a right click on a row: pin and delete". `state/note_store_test.dart` "deleting a note can be undone". | proof |
| §5.4 | Tags come from `#tag` in the text | `state/store_notes.dart`, `core/parsing/note_parser.dart` | `state/note_store_test.dart` "a body makes links and tags". `core/parsing/note_parser_test.dart` group "tags". | proof |
| §5.2, §5.4 | Add an image: paste, drop or a button | `ui/editor/rich_text_field.dart` | RT "there is no image button when the app cannot pick one", "a new image goes in as markup and is stored" (with a test picker), "the remove button takes the image out of the text". The button is hidden in the app, because Flutter has no file window of its own. I found no paste or drop of an image file. | waits for the owner (Q-15) |

### §5.5 — connections between the parts

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.5 (1) | A `- [ ]` line in a note makes a task; the two stay in step; deleting the line keeps the task | `state/store_note_tasks.dart` | `state/note_task_store_test.dart` "open boxes make tasks in order and get marks", "ticking the box finishes the task and clearing it reopens it", "finishing the task ticks the box and undo clears it", "deleting the line keeps the task". NV "a box in the text makes a task when the typing ends". | proof |
| §5.5 (2) | A line with `@date time` offers "Add to planner" | `ui/editor/rich_text_field.dart`, `state/store_at_date.dart` | RT ""Add to planner" shows on a line with an @date" (taps it, the line changes). `state/at_date_store_test.dart` (20 tests). | proof |
| §5.5 (3) | "Linked here" on a note, a task and an event | `data/reference_indexer.dart`, `ui/notes/note_editor_pane.dart`, `ui/tasks/task_inspector.dart`, `ui/calendar/event_editor.dart` | NV ""Linked here" lists what mentions the note". TI "the note the task came from, and the items that link to it". EE "the meeting note is made from a saved event only". `data/reference_indexer_test.dart` group "links table". | proof |
| §5.5 (4) | The daily note shows the events, blocks and tasks of its day | `ui/notes/day_panel.dart` | NV ""Today" opens the note of today with the card of the day". `state/day_store_test.dart` "the agenda holds events, blocks and loose tasks". | proof |
| §5.5 (4) | The planner header has a button for the note of the day | `ui/planner/planner_view.dart` (line 367, "Note for the day") | No test. | built, no proof |
| §5.5 (5) | "Done today" list under the daily note | `ui/notes/day_panel.dart` | NV ""Today" opens the note of today with the card of the day" (reads "Nothing finished yet."). `state/day_store_test.dart` "completed tasks lists what was finished on the day". | proof |
| §5.5 (6) | "Create meeting note": title "<Event> — 2 Oct", three sections, linked to the event; action items become tasks | `state/store_meeting.dart` | EE "the meeting note is made from a saved event only". `state/meeting_note_test.dart` "the title has the event name and the short date", "the body starts with the link and has the three sections", "an action item becomes a task linked to the note". | proof |
| §5.5 (7) | Selected text becomes a task with ⇧⌘T or a menu line "Make task" | `ui/editor/rich_text_field.dart` (lines 212 and 466), `state/store_note_tasks.dart` | RT "a line with words becomes a task line" calls the editor code, not the key. `state/note_task_store_test.dart` group "make task". Missing: no test presses Shift+Command/Ctrl+T or the button; there is a button in the bar of the editor and no right-click line. | partly |
| §5.5 (8) | A note dragged onto the planner makes a 30-minute block "📝 title" | `ui/notes/notes_pane.dart`, `state/store_planner.dart` | NV "a note dragged from the left panel onto the planner gets a time". `state/note_drop_test.dart` "a note makes a half-hour event linked to it". | proof |
| §5.5 (9) | The notes field of a task and of an event is the rich editor | `ui/calendar/event_editor.dart`, `ui/tasks/task_inspector.dart` | EE "the notes of an event are kept". `state/meeting_note_test.dart` "a mention in event notes becomes a link". Missing: the description of a task is a plain field. | partly |
| §5.5 (10) | Weekly note: numbers of the week and "Insert summary" under `## Review` | `ui/notes/day_panel.dart`, `state/store_daily.dart` | NV ""This week" opens the note of the week; the summary goes in". `state/day_store_test.dart` "the review shows done, open, hours and the busiest day", "inserting the summary writes it under Review and undo takes it back". | proof |
| §5.5 (11) | Command palette (⌘K): tasks, events, notes, commands, `>` for commands, "Go to Friday" | `state/store_palette.dart`, `core/parsing/palette_rules.dart` | Rules and store only: `state/palette_store_test.dart` (24 tests), `core/parsing/palette_rules_test.dart` (16 tests). Missing: no window, no shortcut, no button. A user cannot open it. | partly |
| §5.5 (12) | Three mood icons in the header of the daily note | `ui/notes/note_editor_pane.dart` | NV ""Today" opens the note of today with the card of the day". `state/day_store_test.dart` "a mood is set, changed and cleared by the same click". | proof |
| §5.5 (12) | The month can tint days by mood | `ui/calendar/month_view.dart` | MV "the mood switch tints the days by the mood of their note". | proof |

### §5.6 and §5.7 — reminders, menu bar

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.6 | Ask for the permission after the welcome card, not at once | `state/store_welcome.dart` | `state/welcome_store_test.dart` ""Got it" asks for notifications once", "it does not ask again when the system already answered". | proof |
| §5.6 | A reminder for the start of an event or block (0, 5, 10 or 15 minutes before; 5 at first) and for a due time. Title is the item; the text is the time | `core/services/reminder_planner.dart`, `state/store_reminders.dart` | `core/services/reminder_planner_test.dart` "an event reminds on the lead time before it starts" (reads "Stand-up" and "09:30 – 10:00"), "a task due at a time reminds", "the lead choices are the four in the plan". | proof |
| §5.6 | At most the next 60; the id is `ev-<id>-<start>` | `core/services/reminder_planner.dart` | `core/services/reminder_planner_test.dart` "the default limit is sixty because the system keeps sixty-four", "the id has the event and its start". | proof |
| §5.6 | Reminders are made again after each change (one time for many changes) and at launch | `state/store_reminders.dart`, `services/app_services.dart` | `state/reminder_store_test.dart` "many changes in a row make one refresh", "a saved change makes the reminders again". | proof |
| §5.6 | A click on a reminder opens the app on that day or item | `state/store_reminders.dart`, `services/system_notifier.dart` | `state/reminder_store_test.dart` "a click on a block reminder opens its task on its day" (the system is a fake). | proof |
| §5.6 | The reminder is really shown by macOS, Windows, Android and iOS | `services/local_notifications_gateway.dart` | `services/system_notifier_test.dart` (36 tests) and `services/local_notifications_gateway_test.dart` (8 tests) check the calls to the plugin with a fake channel. No machine sees a real reminder. | built, no proof |
| §5.6 | When the permission is refused: a quiet note in Settings | `state/store_reminders.dart` | Rule only: `state/reminder_store_test.dart` "each status has a quiet note", "nothing is sent when the user said no or was never asked". No Settings screen. | in work (F10-screens) |
| §5.7 | Menu bar icon with "Now: …" and "Next: … in 25 min" | `services/tray_service.dart`, `state/store_menu_bar.dart` | `services/tray_service_test.dart` "the menu shows now, next, the growth and the commands" (the tray is a fake). `state/menu_bar_test.dart` group "the Now and Next lines" (9 tests). | proof |
| §5.7 | A bar for how much of today is done | `services/tray_service.dart` | `services/tray_service_test.dart` "the menu shows now, next, the growth and the commands". Differs: a line of text, not a bar, because the tray is a system menu. | partly |
| §5.7 | "Open Grove" | `services/tray_service.dart` | `services/tray_service_test.dart` ""Open Grove" shows the window". | proof |
| §5.7 | Menu bar item on Android and iOS | none | Phones have no menu bar and no tray (`services/tray_service_test.dart` "a system with no tray: the service does nothing"). | not for this platform |

### §5.8 — window, commands, settings

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.8 | Window: at least 960×620, 1280×800 at first, no title bar | `app/windows/runner/main.cpp`, `app/macos/Runner/` | No smallest size and no hidden title bar found. On Windows the first size is 1280×720. | missing |
| §5.8 | File ▸ New Task ⌘N, New Note ⌥⌘N, New Event ⇧⌘N | none | Not found. | missing |
| §5.8 | View ▸ Today ⌘T, and ⌘1 to ⌘4 for the screens | `ui/shell/root_view.dart` | RV "Ctrl with a number opens a screen", "on a Mac the key is Command". | proof |
| §5.8 | View ▸ Day / 3-Day / Week ⌥⌘1/2/3 | none | PLAN §5.1 (2026-10-09) took the day modes away. `ui/planner/planner_kind.dart` has today, week and month. | missing (off by PLAN) |
| §5.8 | Theme ▸ and Appearance ▸ (System, Light, Dark) | `ui/shell/appearance_button.dart` | RV "the menu at the top right switches the theme live", "the menu sets light or dark and the motion switch", "System follows the device". It is a button in the window. | proof |
| §5.8 | A menu bar with File, View, Go and Edit | none | Flutter's `PlatformMenuBar` is not used. The Mac gets the default menu. | missing |
| §5.8 | Edit ▸ Undo / Redo | `ui/store_app.dart` (line 48) | PV "Undo puts a moved block back; Redo moves it again". Missing: no test presses the keys on another screen; there is no Edit menu line. | partly |
| §5.8 | "Search ⌘K" pill and a gear button at the top right; ⌘, | none | Not found. | missing |
| §5.8 | Settings ▸ Appearance: theme with previews, light/dark/system, motion, accent strength | `state/store_appearance.dart` | Theme, light/dark and motion work now from the Appearance button (see the row above). The accent strength has a rule test only (`ui/theme/theme_math_test.dart` "the strength is the theme times the setting, from 0 to 1"). No Settings screen. | in work (F10-screens) |
| §5.8 | Settings ▸ Planner: working hours, busy-day limit, first length, hour height, week starts Monday or Sunday, mood tint | `state/store_data.dart`, `state/rules/` | Rules only: `state/settings_test.dart` "the busy day limit is whole hours from six to twelve", "work hours stay at least one hour long", "the week starts on Monday or Sunday". No Settings screen. | in work (F10-screens) |
| §5.8 | Settings ▸ Notifications: on or off, minutes before | `state/store_reminders.dart` | Rules only: `state/reminder_store_test.dart` "the switch and the lead are saved", "lead choices read in plain words". No Settings screen. | in work (F10-screens) |
| §5.8 | Settings ▸ Data: the list of backups | `data/backup.dart` | Rules only: `state/settings_test.dart` "a backup name becomes a day"; `data/database_test.dart` "the list of a missing folder is empty". No Settings screen. | in work (F10-screens) |
| §0, §5.8 | Layout picker in Settings and in the View menu | none | Needed only with more than one layout. §0 lists B only. | missing (off by PLAN) |
| §5.8 | Settings are kept in the `settings` table | `data/repos.dart`, `state/prefs.dart` | `data/database_test.dart` "settings round trip". `state/settings_test.dart` "a note template is kept in the settings table". Differs: the theme, light/dark, motion, the fold of the strip and the width of the task column are in a `Prefs` file on the device, not in the table. They do not travel in an export. | partly |

### §5.9 — Goals

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §5.9 | Table `goals`; events have `goal_id` and `done_at` | `data/migrations.dart`, `data/repos.dart` | `data/goal_repo_test.dart`. `data/database_test.dart` "there are eight migrations: the seven of the Mac app, and one of this app only". | proof |
| §5.9 | Goals panel: "2.5 / 5 h done" or "3 / 5 sessions done", a bar, "4 h planned", for the week of the chosen day | `ui/goals/goals_pane.dart`, `ui/goals/goal_row.dart` | GP "a row shows the done and the planned time of the week", "the header names the week of the selected day", "a goal with no blocks says so". Pictures in `app/test/ui/goals/goldens/` (7). | proof |
| §5.9 | Add a goal: name, Hours or Sessions, target (0.5 h steps, 5 h at first; sessions 3 at first) | `ui/goals/goals_pane.dart` | GP "Return adds a goal of 5 hours a week", "the stepper sets the hours", "a goal of sessions". | proof |
| §5.9 | The editor in place; Esc, a click on the goal or another goal closes it; right-click ▸ Edit… | `ui/goals/goals_pane.dart`, `ui/goals/goal_row.dart` | GP ""Edit goal…" in the open goal opens it, a click on the goal closes it", "one goal is open at a time", "Esc drops the typed name and closes the editor", ""Edit…" opens the editor". Differs since 2026-10-12 (Q-48): a click on a goal opens its subtasks; the editor is one click more, under "Edit goal…" in the open goal. | proof |
| §5.9 | A goal dragged onto a day makes a 1-hour block | `ui/planner/planner_grid.dart`, `state/store_goals.dart` | SP "a goal dragged from the panel onto a day gets a block". | proof |
| §5.9 | The length of a goal block from its menu (15 minutes to 4 hours) | `ui/planner/planner_grid.dart` | Store only: `state/goal_store_test.dart`. No test opens the menu of a goal block. A resize by the edge is the same code as for any block. | built, no proof |
| §5.9 | Planned and done come from the blocks of the week; never stored; can go over the target | `state/store_goals.dart` | `state/goal_store_test.dart` (45 tests), `state/goal_pane_test.dart`. | proof |
| §5.9 | Tick a goal block done: check box, menu ▸ Mark Done, or Space | `ui/planner/block_view.dart`, `ui/planner/planner_grid.dart` | Store only: `state/clock_store_test.dart` "a goal block ticked done gets the time of the clock". No screen test on a goal block. | built, no proof |
| §5.9 | A deleted goal leaves its blocks | `state/store_goals.dart` | GP ""Delete Goal…" asks first", "a deleted goal leaves its blocks, and undo puts it back". | proof |
| §5.9 | Goals are in the export, the import and the backup | `data/data_export.dart` | `data/data_export_test.dart` group "goals in the file" (5 tests). | proof |
| §5.9 (Swift PR #4, `docs/tracks.md` F7) | Subtasks on a goal block: rows in the block, menu lines, a small window to edit them | `state/store_block_subtasks.dart` | Store, data and sync only: `state/block_subtask_store_test.dart` (28 tests), `data/block_subtask_test.dart`, `sync/block_subtask_sync_test.dart`. Missing: nothing on the screen. No rows in a goal block, no menu line, no window. | partly |
| Not in `PLAN.md` (the owner asked on 2026-10-12) | Subtasks of a goal: 3 under the closed goal, a click shows all and a line to add one; tick, rename, delete; one list for all blocks of the goal, apart from the list of one block | `ui/goals/goal_subtasks.dart`, `state/store_goal_subtasks.dart`, `data/migrations.dart` (migration 8) | `ui/goals/goal_subtasks_test.dart` (26 tests), `state/goal_subtask_store_test.dart` (27), `data/goal_subtask_test.dart` (22), `sync/goal_subtask_sync_test.dart` (29). The rows for each check of the owner are in `docs/acceptance/goal-subtasks.md`. | proof |
| Not in `PLAN.md` (the owner asked on 2026-10-14) | The goal panel: a tap on a goal block opens it at the right (over the screen on a phone); the subtasks of the goal planned in the block, "Add from goal", unplan; a drop of a subtask on empty time makes a 1-hour block; goal blocks hold only goal subtasks (ADR 0002) | `ui/goals/goal_panel.dart`, `state/store_goal_panel.dart` | `ui/goals/goal_panel_test.dart` (18 tests), `state/goal_panel_store_test.dart` (26). The rows for each choice of the owner are in `docs/acceptance/goal-panel.md`. | proof |

### §6 — themes and motion

| PLAN.md | Feature | Flutter code | Proof | State |
|---|---|---|---|---|
| §6 | Four themes; the switch is live | `ui/theme/grove_theme.dart`, `ui/shell/appearance_button.dart` | RV "the menu at the top right switches the theme live", "every theme draws on both sizes with no error". Pictures `desktop_*.png` and `phone_*.png` (16). | proof |
| §6 | The change is a 0.35 s cross-fade | `ui/theme/grove_theme.dart` (line 387) | `ui/theme/grove_theme_test.dart` group "the cross-fade" (4 tests). | proof |
| §6 | Light or dark is its own setting; each theme has both looks | `ui/theme/theme_spec.dart` | `ui/theme/theme_spec_test.dart` "every theme has a light and a dark look", "a theme does not choose light or dark". RV "System follows the device". | proof |
| §6.1 | Colour tokens of the 8 looks | `ui/theme/theme_spec.dart` | `ui/theme/theme_spec_test.dart` "Grove tokens match the plan", "Minimal tokens match the plan", "Futuristic tokens match the plan", "Vintage tokens match the plan". | proof |
| §6.1 | Fonts of each theme | `ui/theme/fonts.dart`, `app/fonts/` | `ui/theme/fonts_test.dart` (6 tests). `ui/theme/grove_theme_test.dart` group "fonts" (11 tests). Differs: PLAN uses the fonts of macOS. Flutter has 7 free fonts inside the app, so all 4 systems show the same letters (Q-1 and Q-2, answered A). | proof |
| §6.2 | Grove: soft shadow, round corners | `ui/theme/panel.dart` | `ui/theme/grove_theme_test.dart` "Grove: surface, line, round corners, a soft shadow", "personality follows the plan". | proof |
| §6.2 | Minimal: no shadow, hairlines, fainter blobs | `ui/theme/panel.dart` | `ui/theme/grove_theme_test.dart` "Minimal: a hairline and no shadow". `ui/theme/theme_spec_test.dart` "blobs are fainter in Minimal and Futuristic". | proof |
| §6.2 | Futuristic: glass panels, a 32-point grid, glow on titles | `ui/theme/panel.dart`, `ui/theme/ambient_background.dart` | `ui/theme/grove_theme_test.dart` "Futuristic: glass, a blur of what is behind", "Futuristic: capitals, wide spacing and a glow". RV "Futuristic has the grid, Vintage the paper". The glow on the now line and on check boxes is in no test. | proof |
| §6.2 | Vintage: paper with noise, ruled lines of 28 points in the editor, dashed chips | `ui/theme/ambient_background.dart`, `ui/editor/` | RV "Futuristic has the grid, Vintage the paper". RT "Vintage: every line is 28 points high, a heading too". `ui/theme/grove_theme_test.dart` "Vintage chips have a dashed border". `ui/theme/theme_math_test.dart` "the noise is the SplitMix64 of the Mac app". | proof |
| §6.3 | Background: three blobs, 46 % of the window, slow paths of 22, 28 and 34 s; it stops when the window is not in front | `ui/theme/ambient_background.dart`, `ui/theme/theme_math.dart` | `ui/theme/theme_math_test.dart` group "ambient background (PLAN §6.3)" (8 tests). RV "with motion on the blobs move, and stop when the window is not in front". | proof |
| §6.3 | Motion off and the system setting "reduce motion" stop all motion | `state/store_appearance.dart`, `ui/shell/root_view.dart` | RV "with motion off nothing moves", "the device setting "reduce motion" stops the blobs". | proof |
| §6.3, §6.2 | Growing plant: 0 to 6 leaves, sways 3° in 5 s; in the header of Layout B | `state/rules/` | Rules only: `state/theme_motion_test.dart` group "the plant" (10 tests). No plant is drawn (`ui/spread/day_spread_view.dart` line 221 says "The growing plant comes with milestone F10"). | in work (F10-screens) |
| §6.3, §6.2 | Check-burst on completion (leaves, fade, ring, "DONE" stamp); the check box fills with a spring | `ui/theme/check_box.dart` | Rules only: `state/theme_motion_test.dart` "grove throws six leaves out 18 points", "each theme has its own burst". Missing: the animation. The file says "without the burst". | partly |
| §6.3 | Rows of a list move in and out with a slide and a fade | none | No such transition found in `app/lib/ui/tasks`. A row that is done stays a moment (`state/theme_motion_test.dart` "a task checked off with linger stays in the open list a moment"). | missing |
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
| §8 | Every layout can reach Planner, Tasks, Calendar, Notes, the command palette and Settings | `ui/shell/root_view.dart` | Missing: the command palette and Settings cannot be reached. | partly |
| §8 A | Layout A · Garden (sidebar, inspector) | none | Off by §0 (B only). | missing (off by PLAN) |
| §8 C | Layout C · Week Board | none | Off by §0 (B only). | missing (off by PLAN) |
| §8 D | Layout D · Journal | none | Off by §0 (B only). | missing (off by PLAN) |
| §9 | First launch: lists "Home 🌿", "Work 💼", "Personal ✨" and 3 sample tasks | `data/first_run.dart` | `data/first_run_test.dart` "a new database gets three lists and three sample tasks", "the sample tasks explain drag to plan, links and the palette". | proof |
| §9 | First launch: the daily note of today | `ui/spread/day_spread_view.dart` (line 292) | No test of a first launch. The note is made when the Today screen opens, not by the first-run code. | built, no proof |
| §9 | Welcome card with "Got it" and "Remove samples" | `ui/tasks/notice_cards.dart`, `state/store_welcome.dart` | Store only: `state/welcome_store_test.dart` (9 tests). No test shows the card. | built, no proof |
| §9 | Empty planner: "Drag a task here, or drag on the grid to plan time." | `ui/planner/planner_grid.dart` | PV "shows the week, the hours and the now line". | proof |
| §9 | Empty notes: "Your thoughts grow here. ⌥⌘N for a new note." | `ui/notes/notes_view.dart` | NV "no notes: the screen says so, and "New note" makes one". Missing: the hint "⌥⌘N" (there is no such shortcut). | partly |
| §9 | Empty lists of tasks and goals say so | `ui/tasks/tasks_pane.dart`, `ui/goals/goals_pane.dart` | TP "an empty day says so", "an empty list says so". GP "an empty panel says what a goal is". | proof |
| §10 | All buttons have labels | `ui/shell/`, `ui/planner/planner_view.dart` | RV "the buttons say what they are". PV finds "Next" by its label. Missing: no test checks the buttons of the other screens. | partly |
| §10 | A block says "Title, 11:15 to 12:45" to a screen reader | `ui/planner/block_view.dart` (lines 88–93) | No test. The text is "Title · 11:15 – 12:45 · 1h 30m". | built, no proof |
| §10 | Ink on surface has a contrast of 4.5 to 1 or more | `ui/theme/theme_spec.dart` | `ui/theme/theme_spec_test.dart` "ink reads on every layer in every variant". | proof |
| §10 | No database call during a drag | `ui/planner/planner_grid.dart` | PV "the label shows the new time during the drag" (the store has the old time until the pointer goes up). | proof |
| §10 | An error shows a small message; the app never crashes | `state/app_store.dart` | `data/data_export_test.dart` group "bad files change nothing" (rule). Missing: the store keeps the error in `errorMessage`, and no file in `app/lib/ui` reads it. | partly |
| §10 | A list of 1 000 tasks is read in under 50 ms | `data/repos.dart` | `data/database_test.dart` "a thousand tasks query is fast". | proof |
| §10, §1 | Launch in under 1 s; a drag at 60 pictures a second | none | Not measured here. The speed check is another part of F12. | built, no proof |
| §11.1 | The app has its own icon | `app/macos/Runner/Assets.xcassets/AppIcon.appiconset/` | The macOS icon is the default Flutter icon. | missing |
| §11.2, §11.3 | `scripts/make_icon.swift`, `scripts/build_app.sh`, `scripts/install.sh` | none | Scripts of the Mac app. Flutter has `scripts/flutter_build.sh`, `scripts/flutter_test.sh`, `scripts/flutter_integration.sh`. | not for this platform |
| §11.3 | One command builds, installs and puts an icon on the Desktop | `scripts/flutter_build.sh` | The CI builds the 4 targets. There is no install step on this branch. Signed installs are another part of F12. | partly |
| §12 | PlannerMath tests | `core/planner/planner_math.dart` | PM, 8 groups. The layout cases are for the cascade (see §5.1.3). | proof |
| §12 | QuickAddParser tests: 25 phrases or more, with a fixed "today" | `core/parsing/quick_add_parser.dart` | `core/parsing/quick_add_parser_test.dart` (33 tests, 8 groups). | proof |
| §12 | NoteParser tests: links, check boxes, `@date`, `#tags` | `core/parsing/` | `core/parsing/note_parser_test.dart` groups "tags" and "check boxes". `core/parsing/reference_parser_test.dart`. `core/parsing/at_date_test.dart`. | proof |
| §12 | Recurrence tests | `core/recurrence/` | `core/recurrence/recurrence_test.dart` (34 tests). | proof |
| §12 | Database tests: migrations, each repo, cascade, search, 1 000 tasks | `data/` | `data/database_test.dart` (27 tests). | proof |
| §12 | LinkIndexer tests | `data/reference_indexer.dart` | `data/reference_indexer_test.dart` "reindex writes and clears backlinks", "reindex keeps manual links". | proof |
| §12, §1.1 | The test script passes | `scripts/flutter_test.sh` | I ran it on 2026-10-11: 1904 tests passed. | proof |

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
| Busy-day alert when a day goes over 9 hours | `ui/planner/planner_view.dart` (line 127), `ui/planner/planner_dialogs.dart` | Store only: PS group "busy-day alert" (6 tests). | built, no proof |
| Bar of planned time against the daily limit | `ui/planner/workload.dart` | Rules only: PR group "Workload" (3 tests). | built, no proof |
| Sync engine: outbox, push, pull, last write wins | `sync/`, `state/store_sync.dart`, `services/supabase_backend.dart` | `sync/sync_engine_test.dart`, `sync/outbox_test.dart`, `sync/store_sync_test.dart`, `state/sync_store_test.dart`, with a fake server. The SQL ran on a plain Postgres on CI. A real two-device sync was never run. | proof |
| Login card and the question of the first sync | `ui/auth/sync_card.dart`, `ui/auth/first_sync_dialog.dart` | `ui/auth/sync_card_test.dart` (13 tests). Pictures in `app/test/ui/auth/goldens/` (16). The card and the gate are on no screen, so a user cannot log in. | in work (F10-screens) |
| Garden screen | `core/services/garden.dart` | Rules only: `core/services/garden_test.dart`. The screen is a stand-in. | in work (F10-screens) |
| A web link in a note opens the browser | none | A click does nothing. | waits for the owner (Q-16) |
| Closing the window keeps Grove in the tray, as the Mac app does | `services/app_window.dart` | Closing the window quits. | waits for the owner (Q-8) |
| The futuristic Day Spread picture on Linux and Windows | `app/test/ui/goldens/f9_golden_test.dart` | Skipped off macOS. | waits for the owner (Q-17) |

## PLAN.md §1.1 — the 27 lines

These lines are a short form of the rows above. They are not in the counts.

| # | Line of §1.1 | State | Why |
|---|---|---|---|
| 1 | `scripts/install.sh` builds, installs, Desktop icon | not for this platform | A Mac script. A Flutter install is part of the release builds. |
| 2 | Own app icon | missing | Default Flutter icon. |
| 3 | Planner: create by drag, by double click, by a task from the list | partly | Drag and task drop have proof. Double click has no test. |
| 4 | Planner: move, snap to 15 minutes | proof | PV, DEV. |
| 5 | Planner: resize top and bottom, 15 minutes at least | proof | PV, DEV. |
| 6 | Planner: overlaps side by side in columns | partly | Overlaps have proof. They cascade; they are not in columns. Same as the Mac source. |
| 7 | Planner: drag a block to another day | proof | PV, DEV. |
| 8 | Planner: live label during a drag | partly | The label is checked; its words on the screen are not. |
| 9 | Planner: undo and redo | proof | PV, DEV. |
| 10 | Planner: keys for the selected block | partly | Arrows, Shift+arrows, Return, Delete, N have proof. Space, ⌘D and the zoom keys have no test. |
| 11 | Planner: ⇧ at the drop pushes later blocks | built, no proof | Store and maths tests only. |
| 12 | Planner: "Fit" | proof | PV. |
| 13 | Tasks: quick add in plain words | proof | TP and the parser tests. |
| 14 | Tasks: buckets, lists, tags, subtasks, repeats | proof | TI, TP, store tests. |
| 15 | Calendar: day, 3-day, week, month; repeating events | partly | Week (Planner), month and today have proof. 3-day is off by PLAN §5.1. |
| 16 | Notes: editor, check lists, `[[links]]`, backlinks | proof | RT, NV. |
| 17 | Notes: `- [ ] text` makes a task | proof | NV and the store tests. |
| 18 | Notes: `@fri 9am` offers an event or block | proof | RT. |
| 19 | Daily and weekly note | proof | NV and the store tests. |
| 20 | Every connection of §5.5 | partly | The command palette has no window. A task body is a plain field. |
| 21 | Four themes, live; light and dark | proof | RV and the pictures. |
| 22 | Motion switch; Reduce Motion | proof | RV. |
| 23 | ⌘K command palette | partly | Rules and store only. No window. |
| 24 | Notifications | partly | The list and the calls have proof with a fake system. No real reminder was seen. |
| 25 | Menu bar item with the next block and a quick-add field | waits for the owner (Q-7) | The lines have proof. The tray has no text field. |
| 26 | Data stays; daily backup; JSON export and import | partly | Backup has proof. Export and import are tested rules with no button (in work, F10-screens). |
| 27 | The test script passes | proof | `./scripts/flutter_test.sh`, 1904 tests. |

## Gaps

Ordered by weight. Day Planner first. "Track A" owns `app/lib/state/`,
`sync/`, `services/`, `data/`, `ui/tasks/`, `ui/goals/`, `ui/auth/` and
`supabase/`. "Track B" owns the rest of `app/lib/ui/` and
`app/integration_test/`. Layouts A, C, D, the week view of tasks, the layout
picker and the 3-day view are not gaps: PLAN.md turns them off.

### Day Planner

1. **Subtasks on goal blocks have no view.** No rows in a goal block, no menu
   line, no window to edit them. The store, the data and the sync are ready.
   Size: medium. Owner: Track B, `app/lib/ui/planner/`.
2. **Focus mode has no timer on the screen.** Only the menu lines "Start
   Focus" and "Stop Focus" are there. No floating timer; nothing on the screen
   asks "Mark done?". The store and the notification are ready.
   Size: medium. Owner: Track B, `app/lib/ui/planner/`.
3. **Planner paths with no test through the screen.** The block menu
   (Duration, Colour, Duplicate, Split in two, Mark done, Unschedule, Delete),
   double click, ⌘ at release for an event, "Schedule existing task", ⇧ at
   the drop with its message, ⌘-click and the move of many blocks, the scroll
   near an edge, Space, ⌘D, the zoom keys and buttons, the question for a
   repeating event after a drag, the all-day strip, a click on a task block,
   a click on a sticky note, a list task dropped on a day, the day totals,
   the working-hours tint, the faded past, the scroll to "now".
   Size: medium (tests only). Owner: Track B, `app/test/ui/planner/` and
   `app/integration_test/`.
4. **A block cannot be dropped on a day of the month. There is no week
   strip.** Size: small for the month drop (also for a note), medium for the
   week strip. Owner: Track B, `app/lib/ui/calendar/`. The Mac source has no
   week strip either, so the owner may want to take it out of PLAN.md.
5. **Small planner differences.** No pinch zoom. No ✎ icon on a block with
   linked notes. No menu line for a linked note. No grow-in after "Fit". A
   move is 220 ms ease-out, not a spring. The fills are 16 % and 10 %, not
   14 %; a block with a priority has a full border. No test reads the words
   of the live label, of the day totals or of the screen-reader text of a
   block. Size: small each. Owner: Track B, `app/lib/ui/planner/`.

### The rest of the app

6. **No Settings screen.** A user cannot export, import, see the data folder
   or the backups, change the note templates, the working hours, the busy-day
   limit, the week start, the reminder switch or the minutes before. The
   rules are ready and tested. Export and import also need a file window, and
   Flutter has none of its own (the same wall as Q-15).
   Size: large. Owner: Track B, `app/lib/ui/` (in work, F10-screens).
7. **The command palette cannot be opened.** No window, no ⌘K, no "Search"
   pill. The rules and the store are ready.
   Size: medium. Owner: Track B, `app/lib/ui/shell/`.
8. **A user cannot log in.** The sync card and the first-sync gate are on no
   screen. Size: small (placing). Owner: Track B places them in
   `app/lib/ui/store_app.dart` and the Settings screen (in work,
   F10-screens); the widgets are Track A's, `app/lib/ui/auth/`.
9. **The description of a task is a plain text field.** PLAN wants the rich
   editor there: lists, formatting, `[[` mentions, images.
   Size: medium. Owner: Track A, `app/lib/ui/tasks/task_inspector.dart`.
10. **Shortcuts and menus.** No ⌘N (new task), ⌥⌘N (new note), ⇧⌘N (new
    event), ⌘K, ⌘,. No menu bar with File, View, Go, Edit. No gear button.
    Size: medium. Owner: Track B, `app/lib/ui/shell/` and
    `app/lib/ui/store_app.dart`.
11. **The "alive" parts.** No growing plant (in work, F10-screens). No
    check-burst when a task is finished. No slide and fade when a row comes or
    goes. The rules for the plant and the burst are tested.
    Size: medium. Owner: Track B, `app/lib/ui/theme/` and
    `app/lib/ui/spread/`; the rows of a list are Track A, `app/lib/ui/tasks/`.
12. **The Garden screen is a stand-in.** Size: large. Owner: Track B,
    `app/lib/ui/` (in work, F10-screens).
13. **An error is not shown.** The store keeps it in `errorMessage`; no
    screen reads it. Size: small. Owner: Track B, `app/lib/ui/shell/` (the
    field is in Track A's `app/lib/state/app_store.dart`).
14. **Images.** The button "Add an image" is hidden (Q-15). No paste and no
    drop of an image file. A stored image is not made smaller (PLAN: 1600 px).
    Size: small for the resize, medium for paste and drop. Owner: Track A,
    `app/lib/data/attachment_repo.dart` (resize); Track B,
    `app/lib/ui/editor/` (paste, drop).
15. **Window and install.** No smallest window size, no hidden title bar,
    Windows opens at 1280×720, the icon is the default Flutter icon, the name
    under the icon is "grove" with a small g, the bundle id is not the one of
    PLAN §0 (Q-26), `grove://` links are not handled, there is no install
    step. Size: small each. Owner: the shared native folders `app/macos/`,
    `app/windows/`, `app/android/`, `app/ios/` and `scripts/` (the release
    part of F12).
16. **Built things with no test through the screen, outside the planner.**
    The welcome card. The quick-add field that keeps a task on a click away.
    The key ⇧⌘T and the "make task" button. The list, time, repeat, note and
    tag chips of a row. The colour of `@date` and `#tag`. The labels of the
    buttons on other screens than the shell. Size: small each. Owner: Track A,
    `app/test/ui/tasks/`; Track B, `app/test/ui/editor/` and
    `app/test/ui/notes/`.
17. **Small differences from the text of PLAN.md.** A click on a link with no
    target says "That item is gone." and makes no note (the Mac source does
    the same). The empty Notes screen has no "⌥⌘N" hint. No `AppLayout` enum.
    The theme, light/dark and motion are in a `Prefs` file, not in the
    `settings` table, so they are not in an export. The tray shows the growth
    as text, not as a bar. Size: small each. Owner: Track B for the screens,
    Track A for `app/lib/state/prefs.dart`.

### Things that wait for the owner

- Q-7: the tray is a system menu with no quick-add field.
- Q-8: closing the window quits Grove.
- Q-15: `file_selector`, so that "Add an image" can show.
- Q-16: `url_launcher`, so that a web link opens the browser.
- Q-17: one picture is checked on macOS only.
- Q-26 (new): the bundle id of the Flutter app.
- Still open with a default that is built: Q-3, Q-5, Q-6, Q-9, Q-10, Q-12,
  Q-13. Open and asked: Q-11, Q-14.

## Not verified by a machine

Only a person with real devices can check these.

- A reminder that really shows on macOS, Windows, Android and iOS, and the
  permission question of each system.
- The "Mark done?" notification at the end of a focus session, and its button.
- A click on a real reminder that opens Grove on the right day.
- The tray icon and its menu on macOS and on Windows.
- A real sync between two devices with a real Supabase project. The SQL ran
  only on a plain Postgres on CI. The engine ran only against a fake server.
  I used no keys.
- The login email with its code.
- Signed installs and installers for each system, and the app icon in the
  Dock, the task bar and the home screen.
- A file from the Mac app's "Export JSON…" imported by a user. The import
  rule is tested with a Mac-shaped file; there is no button yet.
- The feel of a drag: 60 pictures a second, the small tick at each snap on a
  phone, the scroll near an edge.
- Launch time under 1 s and memory use on each system.
- The look of the real fonts. The tests draw text with a box font, so the
  pictures do not show letter shapes.
- Screen readers (VoiceOver, TalkBack, Narrator).
- The device tests: I read them and I read the green CI run 38136166701. I
  did not run them on a device myself.

## Counts

PLAN.md table (the tables §0 to §12 above):

| State | Rows |
|---|---|
| proof | 155 |
| built, no proof | 35 |
| partly | 23 |
| missing | 23 |
| in work (F10-screens) | 10 |
| not for this platform | 3 |
| waits for the owner | 3 |
| All rows | 252 |

Of the 23 `missing` rows, 6 are `missing (off by PLAN)`: PLAN.md itself turns
them off. 17 are real gaps.

The table "Things the port added" has 10 more rows: 3 proof, 2 built with no
proof, 2 in work (F10-screens), 3 that wait for the owner.

So the acceptance line of F12, "Every PLAN.md feature has proof", is not met
yet. 155 of 252 rows have proof. 88 rows are open: 35 built with no proof,
23 partly, 17 missing, 10 in work, 3 with the owner. 9 rows do not apply
(6 off by PLAN, 3 not for this platform).
