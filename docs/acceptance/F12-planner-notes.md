# F12 · the planner notes — proof

Three parts of the Day Planner that came after the planner gaps (`docs/acceptance/F12-planner-gaps.md`). This file takes each one: is the gap real, what was built, which tests prove it, which engine files changed, and what is not verified.

Branch `feat/xp-planner-notes`, draft PR #19 into `feat/cross-platform-flutter`. The base (`ec73831`, with PR #16 and PR #17) is merged into the branch (`6b2c582`).

Check: `./scripts/flutter_test.sh` (2026-10-12, on `6b2c582`: 2334 tests passed, analyze clean, format clean). 59 of them are new here. The base has 2275. Device check: `app/integration_test/planner_test.dart`, 1 test changed, none new. CI run: see "CI" below.

For each part I looked at the code first.

## The parts

| # | Part | Gap real? | Built? | Proof |
|---|---|---|---|---|
| 1 | The linked note of a block (Q-35, answer A) | Yes. The menu had no line, and the store gave the flag `hasNote` to no block. | Yes | `block_note_store_test.dart` (13), `planner_linked_note_test.dart` (11), one golden picture |
| 2 | The focus timer uses the clock of the store | Yes. `startFocus` read `DateTime.now()`. | Yes | `focus_store_test.dart` (7 new), `planner_focus_test.dart` (6 new), 1 device test changed |
| 3 | The now line and the idle processor use | Yes. The now line had a ticker for its pulse. A ticker asks for a frame at each refresh of the screen. | Yes, with one limit: with "Motion on" the pulse still asks for 20 frames a second at most (Q-37). The processor use is not measured. | `planner_now_line_test.dart` (21) |

The planner tests are in `app/test/ui/planner/`, the store tests in `app/test/state/`.

## 1 · The linked note of a block

The owner answered Q-35 with A on 2026-10-12: the linked note is the meeting note of the block.

- The menu of a block has a new line after "Split in Two". It says "Create Linked Note" when the block has no note, and "Open Linked Note" when it has one. The plan has one name for both ("Open / create linked note", §5.1.4).
- The line calls `store.createMeetingNote`. That is the call of "Create meeting note" in the card of an event. It makes the note or finds the one that is there, and shows it in Notes.
- It works for the three kinds of block: an event, a task block and a goal block. The title of the note is "name — day" ("Write report — 7 Oct"). The note starts with "Meeting: [[name|id of the block]]". "New Meeting Note" is one undo step.
- With some blocks selected, the line is for the block under the pointer only.
- A block with a note draws the small pencil (§5.1.2). The drawing was there since the planner gaps; now the store sets the flag.
- Each day of a repeating event has its own note and its own pencil.

Engine files (small edits, no new column, no migration):

- `app/lib/state/store_meeting.dart`: new `withMeetingNote(events)`. One query over the links and the notes for all blocks of the days. It uses the same rule as `meetingNote`.
- `app/lib/state/store_planner.dart`: `blocks()` sets `hasNote`.
- `app/lib/state/app_store.dart`: in `_updateReferences`, a task block or a goal block that comes back with Undo gets its links from notes again. This was a real bug that the new tests found: after "Unschedule" or a delete and then Undo, the block had lost the link to its note. The pencil was gone and the menu line would have made a second note.

Tests:

- `block_note_store_test.dart` (13): each kind of block gets its note, the link and the flag. Asking again opens the same note. Undo and redo. Only the block with the note has the flag, not one with the same name. A note that only mentions the block gives no flag. Each day of a repeating event. A deleted note takes the flag away. A deleted block that comes back keeps its note. A block moved in its day keeps its note. The rule of Q-36. A week of blocks.
- `planner_linked_note_test.dart` (11): through the screen, for each kind of block: the line makes the note and shows it; with a note the block has the pencil and the line opens the same note. The place of the line in the menu. Two blocks selected. A day of a repeating event. The pencil comes and goes with the note. "Unschedule" and then Undo.
- `planner_gaps_golden_test.dart`, "blocks with a linked note have the pencil": picture `goldens/planner_linked_note_grove_light.png`. I looked at it: 4 blocks with a pencil (an event, a task block, a goal block, a short task block) and one block with none.

The tests failed first, for the right reason, and passed after the change.

Rules to know:

- The note is found by its title, "name — day". After a rename of the block or a move to another day the block has no pencil, and the line makes a new note. The old note stays in Notes. The card of an event has the same rule. Q-36 asks the owner if it stays; a test holds it.
- A block that "Fit", "Plan my day" or a new drop from the strip makes is a new block with a new id. It has no pencil.
- A block narrower than 104 points draws no pencil (from the planner gaps).

## 2 · The focus timer uses the clock of the store

- New `store.clockNow()`: the fixed clock of a test (`clockOverride`, a day and a whole minute) or the real clock. `store.startFocus` uses it.
- The focus card reads the same clock. `FocusCard.clock` stays as a hook for tests that count seconds. It is empty in the app.
- In the app nothing changes: no clock is fixed there.

Engine files (small edits):

- `app/lib/state/app_store.dart`: `clockNow()`.
- `app/lib/state/store_focus.dart`: `startFocus` uses `clockNow()`.

Tests:

- `focus_store_test.dart`, group "the clock of the store" (7): the session starts at the time of the clock of the store. A block that is over by that clock cannot start. The last minute of a block. Tomorrow and yesterday. The test moves the clock and the session is that much further. With no fixed clock, "now" is the real clock.
- `planner_focus_test.dart`, group "the clock of the store" (6): the test moves the clock and the bar follows (0, 0.25, 0.5, 0.95). A clock that stands still keeps the card still. The clock reaches the end and the card asks "Mark done?". A session that starts in the middle of a block. A block of the test day starts a session, also when the real clock is past that day. A block that is over starts no session.
- 11 of the 13 failed before the change, for the right reason.
- Device test "focus: Start Focus shows the timer; the cross stops it" (`app/integration_test/planner_test.dart`): it uses the test day (Wednesday, 11:00) and no day in 2099 any more. It moves the clock of the store to 11:45 and reads "15:00" on the card.

## 3 · The now line and the idle processor use

The cause, in the code before the change (`_NowLineState` in `app/lib/ui/planner/planner_grid.dart`):

- The now line had a `Ticker` for its pulse (`PLAN.md` §6.3: opacity 1 to 0.45 and back in 3.2 seconds). The ticker ran when motion was on and the window was in front. A running ticker asks for a frame at each refresh of the screen: 60 or 120 a second.
- Each of those frames built the now line again. The grid is inside a `LayoutBuilder`, so each build laid out and painted the whole planner again.
- The ticker did not move the line. The place of the line came from a timer of the grid: every 20 seconds it drew the whole planner again, with motion off too.

What changed (no engine file):

- The pulse runs on a timer of 20 steps a second. A step changes only the opacity layer of the line (`FadeTransition`): no build, no layout, no paint.
- The pulse runs only with motion on, the window in front, and the planner not under another screen.
- The grid still looks at the clock every 20 seconds. It draws again only when the day or the minute is new.

The numbers, from the widget tests (`planner_now_line_test.dart`, 21):

| State of an idle planner | Before | Now |
|---|---|---|
| Motion on, window in front | a frame at each refresh (1000 a second in the test, where a frame is 1 ms; `pumpAndSettle` never ended) | 20 frames a second at most; no frame waits after a frame; `pumpAndSettle` ends |
| Motion off, or "Reduce motion" | 3 frames a minute | 0 frames while the minute is the same; 1 frame for a new minute |
| Window not in front | no pulse; 3 frames a minute | no pulse; 0 frames in 3 seconds |
| Planner under another screen | no pulse (the system stops a ticker there) | no pulse; 0 frames in 3 seconds. A timer does not stop there by itself, so the code looks at `TickerMode`. |
| A week with no today | 3 frames a minute | 0 frames |

- The line is at the minute of the clock and moves when the clock moves, with motion on and off. The faded past ends at the line. After midnight the line is in the next day. The line waits 20 seconds at most for a new minute, as before.
- A step of the pulse paints no part of the window again. One step changes the line by 0.03 at most. The pulse still goes from 1 to 0.45 and back in 3.2 seconds.
- The timeline of the Today screen has the same numbers.
- With "Motion off" nothing is worse: there was no pulse before and there is none now, and the planner draws less often.

The task said "an idle planner asks for no frames". That holds with motion off, with the window not in front, and under another screen. With motion on the pulse of the plan needs frames; it is 20 a second at most now. No pulse at all is a change of the plan, so it is the owner's call: Q-37 (default: the pulse stays).

## CI

Commit `ac95999` (the head; the last code commit is the merge `6b2c582`, and `ac95999` adds only files in `docs/`), workflow `flutter`, 2026-10-12.

Run 38181158902 (push) and run 38181181378 (pull request #19): both green on the 4 jobs at the first try. No job ran again. The numbers are the same in the two runs.

| Job | Test | Build | Integration test (16 tests) |
|---|---|---|---|
| `build (ubuntu-latest, android)`, Android emulator | pass (2333, 1 skipped) | pass | pass (13, 3 skipped) |
| `build (windows-latest, windows)` | pass (2333, 1 skipped) | pass | pass (15, 1 skipped) |
| `build (macos-latest, macos)` | pass (2334) | pass | pass (15, 1 skipped) |
| `build (macos-latest, ios)`, iPhone simulator | pass (2334) | pass | pass (13, 3 skipped) |

The skips are the same as before this branch. On Linux and Windows one golden picture of F9 is parked (Q-17). On the phones the 3 device tests that need a mouse and a keyboard are skipped. On the computers the pinch with two fingers is skipped.

- The changed device test, "focus: "Start Focus" shows the timer; the cross stops it", passed in the 4 jobs of both runs.
- The new picture `planner_linked_note_grove_light.png` against the limit of 0.2 %: 0.080 % on Linux, 0.072 % on Windows, 0.000 % in the macOS job and in the iOS job. No golden picture failed.
- The test "a strip drop is one undo step that brings back the block" (`app/test/state/planner_store_test.dart`), which failed one time on the base on Windows, passed in the 8 jobs.
- A later commit that changes only files in `docs/` starts no run: the workflow looks only at `app/`, the `scripts/flutter_*.sh` files and its own file.

## Notes

- Q-36 (open, with a default): does a block keep its note after a rename or a move to another day? Today it does not.
- Q-37 (open, with a default): does the now line keep its pulse? Today it does.
- The requests to the shell are in `docs/tracks.md`, "Requests, with the planner notes": measure the idle processor use after both branches are merged, and put the now line on the shared beat (`SlowClock`) of the shell branch.
- The two requests of the planner gaps to Track A (`startFocus` and `hasNote`) are marked done in `docs/tracks.md`.
- The decisions are in `docs/assumptions.md` (2026-10-12, "F12 planner notes").

## Not verified

- CPU not measured. The idle tool (`scripts/flutter_idle.sh`, `app/tool/idle_check.dart`) is only on the branch `feat/xp-shell-gaps`. The tests count the frames that the planner asks for; they do not measure the processor. Before the fix the shell helper measured 42 % (Planner) and 43 % (Today) of one core.
- The whole app on this branch. The tests of the now line pump the planner alone. On this branch the background of the shell and the plant in the header of Today still have their own tickers (the shell's files; fixed on `feat/xp-shell-gaps`). So the app of this branch alone can still draw at each refresh. The real number comes after both branches are merged.
- The look of the pulse at 20 steps a second. The tests read the numbers; nobody looked at it on a screen.
- The device tests on this Mac. This Mac has no Xcode. The changed device test for focus ran only in CI.
- The menu line and the pencil by hand in the app. The tests go through the screen of the test framework.
- The linked note with sync on (two devices). The note and its link are plain rows that the sync has already; no test here uses a server.
