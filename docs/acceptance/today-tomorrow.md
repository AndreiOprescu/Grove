# The Today screen can show only tomorrow — proof

The owner asked: "In the today screen, I also want to have the ability to ONLY see the next day as well, so I can plan tomorrow as well".

This file takes each thing that was asked: what was built, which tests prove it, which CI run, and what is not verified.

Branch `feat/xp-tomorrow`, draft PR #23 into `feat/cross-platform-flutter`. The base is merged into the branch two times: `8351ccd` (with PR #18, #19 and #20) in `c76a483`, and `c0c5b81` (PR #22, docs only) in `dfe9d0c`. The code commit is `2d6b970`.

The owner read the plan and said "A, yes to all" on 2026-10-12. The answer came to the builder through the coordinator of the session.

Check: `./scripts/flutter_test.sh` (2026-10-12, on `2d6b970` and again on the merge `dfe9d0c`: 2508 tests passed, analyze clean, format clean). 52 of them are new here. The base has 2456. Device check: `app/integration_test/planner_test.dart`, 1 new test; it runs in CI only. CI run: see "CI" below.

No database change. No migration. No new package. No edit in `planner_grid.dart`.

## What was asked

| # | Asked | Built? | Proof |
|---|---|---|---|
| 1 | A control in the header that shows ONLY tomorrow on the same screen, and a way back | Yes | `day_spread_view_test.dart` "the header has a switch, and it starts on Today", "a click on Tomorrow shows only tomorrow", "a click on Today goes back"; 3 new pictures |
| 2 | The header says which day is in view (name and date) | Yes | "a click on Tomorrow shows only tomorrow": the date is "Thursday 8 October", the line under it starts with "Tomorrow" |
| 3 | The schedule shows the blocks and events of tomorrow | Yes | the same test: only the column of Thursday, the event of Thursday is there, the event of Wednesday is not |
| 4 | A new block lands on tomorrow | Yes | "a block drawn on the timeline lands on tomorrow", "a block added on a phone lands on tomorrow"; the device test |
| 5 | A task dropped on the schedule lands on tomorrow | Yes | "a task dragged on the timeline gets its block tomorrow" |
| 6 | A task typed in quick add lands on tomorrow | Yes | "a task typed in the list lands on tomorrow"; `tasks_pane_test.dart` group "the list of tomorrow"; `today_screen_day_test.dart` group "quick add in the list of a day" |
| 7 | The task list shows the tasks of tomorrow | Yes | `tasks_pane_test.dart` group "the list of tomorrow" (8) |
| 8 | Nothing in the tomorrow view says "now" or "overdue" by mistake | Yes, part by part: see "The parts of the real today" | "a click on Tomorrow shows only tomorrow" (no now line, no greeting, no growth, no plant), "the card of yesterday is not in the tomorrow view", `tasks_pane_test.dart` "a due day is still named from the real today" |
| 9 | The switch belongs to the screen; the store edit is small | Yes | `git diff 8351ccd..2d6b970 --stat -- app/lib/state`: `app_store.dart` 10 lines, `store_navigation.dart` 34, `store_tasks.dart` 14 |
| 10 | A phone: the control fits the narrow header and works with touch | Yes, in a widget test with a touch pointer. Not with a real finger. | "a phone: the switch has its own row, and a finger has room"; the picture `spread_tomorrow_phone_grove_light.png`; the device test on Android and iOS |

The screen tests are in `app/test/ui/spread/`, the list tests in `app/test/ui/tasks/`, the store tests in `app/test/state/`.

## How it works

- The header of the Today screen has a switch with two words: "Today" and "Tomorrow". A click on "Tomorrow" shows only tomorrow on the same screen. A click on "Today" goes back. So does "Today" of the View menu (Cmd+T on a Mac, Ctrl+T on Windows).
- The header shows the day in view: the name of the day and the date. For tomorrow the line under it says "Tomorrow · No tasks yet", "Tomorrow · 1 task planned" or "Tomorrow · N tasks planned".
- The three columns take the day in view: the task list, the timeline and the note.
- A new block, a task dropped on the timeline, a task typed in the quick add, "New task" and "New event" land on the day in view. A time alone in the quick add of the list of tomorrow ("Call Ana 3pm") makes the block tomorrow.
- "Plan my day" plans the day in view. For tomorrow it starts at the start of the working hours. Its tooltip names the day.
- The app opens on today at each start. The choice stays while the app runs, also across screens.
- At midnight the screen keeps its date. That date is then today: the header says so and the switch is on "Today".
- A desktop window: the switch is in the header row, 188 wide, left of the plant. A phone: the switch has its own row under the date, as wide as the screen.

## The parts of the real today

Each has one line in `docs/assumptions.md` (2026-10-12, "Today screen, tomorrow view").

| Part | In the tomorrow view | Why |
|---|---|---|
| The now line | Not drawn | It is the real time. The grid draws it only in the column of the clock's today. |
| The shade over the past hours | Not drawn | The same. |
| The greeting ("Good morning") | Not shown | It is of the hour of today. |
| "% of the day grown" | Not shown | The growth is of today. The line says how many tasks are planned. |
| The plant | Not shown; its slot stays empty | It grows with the tasks done today and the streak. |
| The welcome card | Not shown | It is the first steps of a new user, on today. |
| The card "left open yesterday" | Not shown | "Yesterday" seen from tomorrow would be today. |
| The words of a due date, the "late" mark | Count from the real today | "due Tomorrow" for a task due on that day, never "due Today". |
| The focus timer card | Stays | It is a real timer that runs now. The window hosts it. |
| The tray, the menu bar text, the Tasks panel on the left | Stay on the real today | They are not parts of the Today screen. |

## The touch area of the switch

The coordinator asked: make the touch area at least as large as the other touch targets of a phone, with no change of the look.

- The look did not change: the control is about 27 points high.
- On a phone the place that takes a touch is 40 points high and as wide as the row (366 on a screen 390 wide). A dock button on a phone is 44 × 40 (`ShellRules.dockButton`).
- In a desktop window the place is the whole height of the header row (44 or more) and 188 wide.
- A touch in the empty space over or under a word picks that word. The left half is "Today", the right half is "Tomorrow".
- Cost: the phone header is about 42 points higher than before. The gaps there are smaller (10 to 4, and 2 inside), so the timeline loses as little as possible.
- Proof: "a phone: the switch has its own row, and a finger has room" (the row is from 12 to 378, the touch box is 40 high, a touch over the word and a touch under the word both work); the device test taps the empty space over "Today".

## Files

Screen and parts:

- `app/lib/ui/spread/day_spread_view.dart`: the header with the switch, the day of the three columns, the look at the clock for midnight.
- `app/lib/ui/spread/spread_rules.dart`: the width of the switch, the height of the touch area, the slot of the plant, the words of the line for tomorrow.
- `app/lib/ui/tasks/tasks_pane.dart`: an optional `day` for the list of a day.
- `app/lib/ui/tasks/quick_add_field.dart`: the preview knows the day of the list.
- `app/lib/ui/planner/planner_view.dart`: an optional `day`, and the tooltip of "Plan my day". No edit near the zoom buttons or the header limit.

Store and engine (small edits):

- `app/lib/state/app_store.dart`: one field, and one line in the `screen` setter.
- `app/lib/state/store_navigation.dart`: `todayScreenDay`, `showsTomorrow`, and a few lines in `showToday` and `showDay`.
- `app/lib/state/store_tasks.dart`: `quickAdd` gives the day of the list to the parser.
- `app/lib/core/parsing/quick_add_parser.dart`: an optional `defaultDay`.

## Tests (52 new)

- `app/test/state/today_screen_day_test.dart` (20, new file): the screen starts on today; the switch; the choice stays across screens and is not saved; View ▸ Today; `showDay`; New Event; "New task"; midnight (3); quick add in the list of a day (4).
- `app/test/core/parsing/quick_add_parser_test.dart` (1 new): the day of the list is the base of a time alone; a day in the text wins.
- `app/test/ui/spread/spread_rules_test.dart` (2 new): the words for tomorrow; the sizes of the switch.
- `app/test/ui/tasks/tasks_pane_test.dart` (8 new, group "the list of tomorrow"): the title and the counts; quick add lands there with no toast; "3pm" makes the block tomorrow and the chip says "Thu 8 Oct"; the cards of today are not there; the due words; whole pixels.
- `app/test/ui/spread/day_spread_view_test.dart` (18 new, group "the tomorrow view"): see the table above; also "the choice stays while the user is on another screen", "the key of \"Today\" goes back to today", "at midnight the tomorrow view keeps its date, as today" (also: no frame while idle), "at midnight the today view moves to the new day", and the switch in each of the 4 themes.
- `app/test/ui/goldens/f9_golden_test.dart` (3 new pictures): `spread_tomorrow_desktop_grove_light.png`, `spread_tomorrow_desktop_grove_dark.png`, `spread_tomorrow_phone_grove_light.png`.
- 7 pictures of the Today screen were made again, because the header has the switch now: `spread_desktop_grove_light.png`, `spread_desktop_grove_dark.png`, `spread_desktop_minimal_light.png`, `spread_desktop_vintage_light.png`, `spread_desktop_futuristic_light.png`, `spread_narrow_grove_light.png`, `spread_phone_grove_light.png`. I looked at each of the 10 pictures. No other picture changed.
- Device test (CI only), `app/integration_test/planner_test.dart`: "today: the switch of the header shows only tomorrow, and a new block lands there".

Order of work: the store tests, the parser test and the list tests were written first and seen failing. The screen tests were written right after the screen code; they were not seen failing against the old screen. One of them found a real bug (the day of the clock was read too late, so midnight was missed).

## CI

Workflow `flutter`, 4 jobs. The code commit is `2d6b970`. The commits after it change docs only (and bring the base, which changed docs only).

State on 2026-10-12, when this file was written. The Mac machines of CI had a long line of waiting jobs.

| Run | For | android | windows | macos | ios |
|---|---|---|---|---|---|
| 38233074479 | the push of `2d6b970` | green | green | red once: a test of the base, see below | not ended |
| 38233214149 | draft PR #23 (`2d6b970` with the base `8351ccd`) | green | green | waiting | waiting |

- The new device test passed on Windows and on Android in run 38233074479: "today: the switch of the header shows only tomorrow, and a new block lands there".
- The red macos job of run 38233074479: 2507 tests passed, 1 failed. The one is `app/test/ui/settings/settings_view_test.dart` "Export saves all data under the name of today". It is a test of the base, and this branch does not touch it or the export. It makes the export text two times and compares them; the text has the time with seconds; in this run the two were made in two seconds ("11:27:40" and "11:27:41"). Not fixed here: it is not a part of this task.
- The last state of the jobs is in the checks of PR #23.

## Not verified

- The app was not run on this Mac (the rule of the session). The proof is tests, pictures and the device tests in CI.
- A real finger on a real phone. The touch is a test pointer, in a widget test and on the CI devices.
- Midnight with a real clock. The tests use a fake clock.
- The look of the switch in the real fonts of each system, beyond what the CI devices run. The pictures use the test font.
- "A block and a task added in the tomorrow view are in the column of tomorrow in the week Planner": the tests prove the day of the block and of the task in the store. The week Planner draws from the same store; no test of this branch opens the week to look.
- The timeline does not scroll to the morning when the day changes (a follow-up, it needs an edit in the grid).

## Hand checks for the owner

1. Open Today. Click "Tomorrow". The header shows the date of tomorrow, and only the plan of tomorrow is in view.
2. Add a block on the timeline and type a task. Open Planner: both are in the column of tomorrow.
3. Click "Today". The screen is back on today.
4. In the tomorrow view nothing says "now" or "overdue": no now line, no greeting, no plant.
5. Make the window narrow as a phone, or use a phone: the switch has its own row and takes a touch.
