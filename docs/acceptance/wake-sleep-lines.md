# The wake-up line and the sleep line of the day planner — proof

The owner asked: "I want there to be the following markers on the day planner: wake up and sleep. These should be two lines that I can drag up or down during the day to help me decide when I should wake up and go to sleep. I should be able to add these by clicking a "+" icon at the top of the day schedule or whatever you deem most suitable."

This file takes each thing asked: what was built, which tests prove it, and what is not verified.

Branch `feat/xp-wake-sleep`, draft PR #24 into `feat/cross-platform-flutter`. The base is merged into the branch three times: `8351ccd` (PR #18, #19 and #20) in `b8a6bbb`, `c0c5b81` (PR #22, docs) in `5d60096`, and `345b6c7` (PR #21, the subtasks of a goal, and PR #23, the tomorrow view of Today) in `9a1bf32`.

Check: `./scripts/flutter_test.sh` (2026-10-12, on this Mac: after the last merge: 2686 tests passed, analyze clean, format clean). 74 of them are from this branch; the others are from the base. Device check: `app/integration_test/planner_test.dart`, 1 new test; it runs only in CI. CI run: see "CI" below.

## What the user sees

- Above the day schedule, left of the two zoom buttons, there is a "+". It is in the header of the Planner and in the "Timeline" row of Today. The month has none.
- A click on "+" opens a small menu: "Add wake-up line" and "Add sleep line". In the week the first row of the menu names the day ("Wed 7 Oct"): the lines are for the selected day.
- A line is a dashed line across the day column. At its right end is a small label: a sun or a moon, the word "Wake up" or "Sleep" when the column is wide, and the time ("07:00").
- A drag of the label or of the line moves it up or down in steps of 15 minutes. The time on the label follows. It works with the mouse and with a finger, with no hold.
- A tap or a click on the label or the line opens a menu with one row: "Remove wake-up line" or "Remove sleep line". A right click does the same. The menu of "+" says "Remove ..." too when the day has the line.
- When the Today screen shows tomorrow (the switch "Today | Tomorrow" of its header), the "+" adds the lines of tomorrow and the column shows the lines of tomorrow.
- Each day has its own two lines (Q-52, answer A). A new line starts at the time of the same line on the nearest day that has one; with none it starts at 07:00 (wake-up) or 23:00 (sleep).
- Undo takes back an add, a move and a remove.

## Each thing asked

| # | Asked | Built? | Proof |
|---|---|---|---|
| 1 | A "+" at the top of the day schedule adds "Wake up": a line shows with its time | Yes | `day_marker_test.dart`, group `the "+" above the schedule` (7 tests); pictures `day_lines_*.png` |
| 2 | I drag it up and down; the time on the label follows; it snaps like a block | Yes | `day_marker_test.dart`, group `a drag of a line` (13 tests); device test |
| 3 | I add "Sleep" the same way | Yes | the same tests add the sleep line; `day_marker_store_test.dart` |
| 4 | I can remove each line | Yes | `day_marker_test.dart`, group `a line goes away` (4 tests) and "names the line that is there as one to remove" |
| 5 | I leave the screen and come back, and I start the app again: the lines are where I left them | Yes, on a test database | `day_marker_store_test.dart`, "The lines stay · after the app starts again"; `day_marker_test.dart`, "are there again when the screen comes back" |
| 6 | It works with touch on a phone layout | Yes, in tests. Not on a real phone by hand | `day_marker_test.dart`, group `on a phone` (2 tests) and the finger tests of the drag; picture `day_lines_phone_grove_light.png`; the device test on the Android emulator and the iOS simulator in CI |
| 7 | A drag of a line starts no block drag, makes no new block, and the grid does not scroll under the finger | Yes | "with a finger moves it at once: the grid does not scroll ...", "with a finger that holds first ...", "over a block does not move the block", "a block drag that runs does not start a line drag" |
| 8 | No frame when nothing moves | Yes | "ask for no frame when nothing moves" (also after a drag); "with motion on" (the grid glides to a new line, then rests) |
| 9 | No migration, no new table, no new column | Yes | the rows are in the old table `settings`; this branch changed no file under `app/lib/data/`. Migration 8 (`goal_subtasks`) is from the base (PR #21); the tests of the lines for the export file, the import and the sync pass with it |
| 10 | The lines show for each day that a column shows | Yes | "each day of the week shows its own lines", "the Today screen has it: the line is on today", "the Today screen on "Tomorrow": the "+" and the lines are those of tomorrow" (desktop and phone); the layer draws the days that the grid gets |
| 11 | Undo | Yes: add, move and remove are steps | `day_marker_store_test.dart`, group `Undo` (4 tests); `day_marker_test.dart`, "is one undo step" and "follow the store: another device, or undo" |

The screen tests are in `app/test/ui/planner/`, the store test is in `app/test/state/`.

## How it is built

Storage (no migration):

- One row in the table `settings` for each line of a day. The key is `planner.wake.<YYYY-MM-DD>` or `planner.sleep.<YYYY-MM-DD>`. The value is the minute of the day as text (`420` is 07:00). No row means no line.
- The table is in the export file and in the sync since the first schema, so the lines go with them. No code of the sync changed.

Engine files:

- New `app/lib/state/rules/day_marker.dart`: the two kinds, their names, the key of a row, the snap (15 minutes, 00:00 to 23:45).
- New `app/lib/state/store_day_markers.dart`: `dayMarkers`, `dayMarker`, `addDayMarker`, `moveDayMarker`, `removeDayMarker`.
- Small edits: `app/lib/state/mutation.dart` (a list `settings`, so a change of a line is an undo step), `app/lib/state/app_store.dart` (one `part` line, one line in the undo code), `app/lib/state/state.dart` (one export).

Screen files:

- New `app/lib/ui/planner/day_markers.dart`: the menu of "+", the layer that draws the lines and takes the drag, and `DayMarkerPlus`, the "+" of the button as two bars on whole pixels.
- `app/lib/ui/planner/planner_grid.dart`: one layer after the now line; a flag so the grid does not scroll and starts no block drag during a line drag; `scrollToMinute`.
- `app/lib/ui/planner/planner_view.dart`: the "+" in `_zoomButtons`, `_showDayMarkers`, and the two width limits of the header (470 and 680 points; they were 430 and 640).
- `app/lib/ui/theme/symbols.dart`: the moon.

## Tests

`app/test/state/day_marker_store_test.dart` (23):

- A new line: none until one is added; 07:00 and 23:00 first; a line belongs to one day; the time of the last day before; the time of the next day when none is before; a second add changes nothing.
- Moving and removing: only that line of that day; the snap and the limits of the day; no order of the two lines; a line moves and blocks no task; a move of a line that is not there; a move to the same time is no undo step; remove; each change tells the screens; a value that is not a time is no line.
- Undo: add, move and remove are one step each, with a name; the sleep line has its own names; undo of a line move leaves an older block move; two moves are two steps.
- The lines stay: after the app starts again (a database file in a temp folder, closed and opened again); in an export file and after its import.
- Sync (two test devices and the test backend, no real server): a line goes to the other device when added, moved and removed; wake-up moved on one device and sleep on the other, both stay.

`app/test/ui/planner/day_marker_test.dart` (35):

- The "+": adds the wake-up line with its time and brings it into view; adds the sleep line; a line in view does not move the grid; the menu says "Remove ..." for a line that is there; in the week it acts on the selected day and names it; Today has it; Today on "Tomorrow" adds and shows the lines of tomorrow, and back on today the lines of today (desktop and phone; added after the merge of PR #23); the month has none.
- A drag: with the mouse in steps of 15 minutes, the label follows, nothing is saved before the end; on the line itself; with a finger at once, the grid does not scroll; with a finger that holds first, no new block; over a block the line moves, not the block; stops at 00:00 (the store test has 23:45 too); near the edge of the screen the grid scrolls; one undo step; two fingers on a trackpad scroll the grid and leave the line; the mouse wheel scrolls; a line that goes away during the drag frees the grid; a running block drag starts no line drag; sleep can be above wake-up.
- A line goes away: a tap on the label and "Remove"; a right click on the line; a click that slips by a point opens the menu and moves nothing; a tap outside the menu keeps the line.
- On the screen: the lines follow the store (undo, redo); they come back after the screen was left, and Today shows the same line; each day has its own lines; no frame at rest, also after a drag; a screen reader says the line and its time and can move it.
- Motion on: the grid glides to a new line and then rests.
- On a phone (390 × 844): "+" adds both lines, a finger moves one, a tap removes it; Today on a phone.
- The small header of the timeline fits from 240 to 520 points.

`app/test/ui/planner/day_marker_header_test.dart` (6): it loads the real fonts of the app. The header of the week fits at each width from 320 to 1100 points in the 4 themes (4 tests). The "+" does not cut the dates of the week in the grove theme and the minimal theme (2 tests).

`app/test/ui/planner/day_marker_golden_test.dart` (7 pictures in `app/test/ui/planner/goldens/`): `day_lines_desktop_grove_light.png`, `day_lines_desktop_minimal_light.png`, `day_lines_desktop_futuristic_light.png`, `day_lines_desktop_vintage_light.png`, `day_lines_desktop_grove_dark.png`, `day_lines_phone_grove_light.png`, `day_lines_today_drag_grove_light.png`. I looked at each: the two dashed lines, the labels at the right end with the sun or the moon and the time, the dark label during a drag.

The same file has 3 tests "the "+" has no soft edge" (the Planner, a phone, Today): they draw the screen and read the points inside the "+" button. There are two colours only, the button and the ink.

`app/integration_test/planner_test.dart` (1 new device test): "day lines: "+" adds the wake-up line, a drag moves it, a tap takes it away". A finger on Android and iOS, the mouse on macOS and Windows.

The tests failed first for the right reason ("key not found"; for the header: too wide from 458 to 482 points, dates cut at 664 points; for the "+": more than two colours with the shape of the icon font) and passed after the code. Four guard tests ("a line that goes away ...", "a block drag that runs ...", "no frame ...", "the Today screen on "Tomorrow" ...") passed at once; I broke the code on purpose to see each one fail, then put the code back.

## Old pictures made again

The "+" is in each picture with the header of the Planner or the "Timeline" row of Today. 48 old pictures were made again with `flutter test --update-goldens`: 33 in `app/test/ui/goldens/`, 6 in `app/test/ui/goals/goldens/`, 6 in `app/test/ui/tasks/goldens/`, 3 in `app/test/ui/planner/goldens/`.

How I checked them: a script compared each new picture with the old one point by point and cut out the changed part of both. I looked at each of the 48 pairs. In all of them the changed points are in the row of the header only: the "+" is new, and the buttons left of it moved by 38 points. In the 6 pictures of Goals the dates of the header lose one more letter; that is the test font, where each letter is a square. I looked at two whole pictures as well (`goals_desktop_grove_light.png`, `goals_desktop_futuristic_light.png`).

## Pictures after the merge of PR #21 and PR #23

The base got the subtasks of a goal and the tomorrow view while this branch was open. Both sides had changed 12 pictures (5 `goals_desktop_*.png`, 7 `spread_*.png`). The merge commit `9a1bf32` has the pictures of the base. The next commit has 16 pictures made again on this Mac with `--update-goldens`, for the tests that own them (`goals_golden_test.dart`, `f9_golden_test.dart`, `day_marker_golden_test.dart`): the 12, the 3 new `spread_tomorrow_*.png` of the base (they had no "+"), and `day_lines_today_drag_grove_light.png` (the header of Today has the switch now).

A script compared each new picture with the one of the merge commit: all changed points are in the row of the buttons above the schedule (the "+", and the buttons left of it that moved). I looked at each of the 16 whole pictures: the 5 of Goals show the subtasks under the open goal and the "+"; the 10 of Today show the switch "Today | Tomorrow" and the "+"; the picture of the lines shows the switch, the "+" and the two lines. A run of the whole suite with `--update-goldens` changed no other picture.

## The "+" was drawn again after the first CI run

In CI run 124 the android job failed on one old picture, `planner_phone_grove_light.png` (test "planner phone grove"): 0.204 % of the points were off, and the limit is 0.2 %. All tests of the lines passed there, and so did the 7 new pictures.

The cause: the "+" was a shape of the icon font. Such a shape has soft edges, and Linux draws them in another way than the Mac. 24 of the 671 points that were off were the "+". Without them the picture is at 647 points; the limit is 658.

The fix (commit `79c6326`): the "+" is two bars of 2 points on whole pixels, drawn by `DayMarkerPlus`. The limit and `TolerantGoldenComparator` did not change. 55 pictures were made again: the 48 old ones and the 7 new ones. A script compared each with the picture before: in each one the points that changed by more than the noise are in the 10 by 10 points of the "+". I looked at the old and the new "+" of all 55, and at two whole pictures (`planner_phone_grove_light.png`, `day_lines_today_drag_grove_light.png`).

## CI

Workflow `flutter`, 4 jobs each (android, windows, macos, ios), with the device tests.

| Run | Commit | android | windows | macos | ios |
|---|---|---|---|---|---|
| 124 (push) | `814cc11` (the code of `99cba46`) | failed: one old picture, see above | green | green | green |
| 125 (pull request) | `814cc11` | failed: the same picture | green | green | green |
| 128, 129 | `5d60096` (merge of the docs of the base) | cancelled by me: the same code as run 124, and a newer commit was pushed | | | |
| 134 (push), 135 (pull request) | `79c6326` (the "+" as two bars) | not finished | not finished | not finished | not finished |
| the runs of the head after the merge of `345b6c7` | the last commits of the branch | not finished | not finished | not finished | not finished |

No run is green on all 4 jobs yet. The owner said on 2026-10-12 not to wait for the CI queue (more than one hour for macOS), so this file was closed before the runs ended. The last finished runs are 124 and 125: green on windows, macos and ios, red on android. The new device test of the lines passed on windows, macos and ios in runs 124 and 125. On android the job stopped at the picture test, before the device tests.

The android result of the fix is an estimate made on this Mac: the picture of run 124 with the new "+" has 647 points off, and 658 are allowed.

## Not verified

- CI on the last commits: the runs were not finished when this file was written. The fix for the android picture is not proven in CI yet.
- The real app. I did not start it on this Mac: a build here has the app id of the owner's live app and would open the real data. So the drag was not felt by hand, with a mouse or with a finger.
- A real phone. The phone layout is tested in widget tests, and the device test runs on an emulator and a simulator in CI.
- Sync against a real Supabase project. The tests use the test backend.
- The header in the futuristic theme and the vintage theme: the dates were cut at some widths before this change (up to 704 and 824 points of the planner); the cut now ends 36 points later.
- The picture `planner_phone_grove_light.png` is near the limit on Linux also without the "+": about 647 points are off and 658 are allowed. That comes from the letters and icons that were there before. A later change of that screen can make the android job fail on it.
- The strip of a line that takes the drag is 8 points high and lies over a block under it. A finger that starts a scroll exactly on a line moves the line. Undo puts it back.
