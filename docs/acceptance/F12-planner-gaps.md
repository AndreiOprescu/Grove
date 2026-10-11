# F12 · the Day Planner gaps — proof

A check of the Flutter app against `PLAN.md` gave a list of gaps in the Day Planner. This file takes each one: is it real, what was built, which tests prove it, and what is not verified.

Branch `feat/xp-planner-gaps`, draft PR #15 into `feat/cross-platform-flutter`. The branch was made on top of `feat/xp-screens` (PR #11). PR #11 and PR #13 are merged now, and `feat/cross-platform-flutter` (`b7a20b9`) is merged into this branch (`096e994`). So PR #15 waits for no other PR.

Check: `./scripts/flutter_test.sh` (2026-10-11, on `096e994`: 2250 tests passed, analyze clean, format clean). 152 of them are new here. Before this branch there were 2031; 46 more came with the merge of `feat/xp-screens`, and 21 more with the merge of `feat/cross-platform-flutter` (the engine requests of PR #13). Device check: `app/integration_test/planner_test.dart`, 7 new tests, 16 in all. CI run: see "CI" below.

For each gap I looked at the code first. The claims came from a check by another helper, so they were second-hand.

## The gaps

| # | Gap in the list | Real? | Built? | Proof |
|---|---|---|---|---|
| 1 | Subtasks on goal blocks have no view | Yes. The store had the data and the calls (Track A, migration 7). The grid drew nothing for a goal block and the menu had no line. | Yes | `planner_subtasks_test.dart` (22), one golden picture |
| 2 | Focus mode: no timer on the screen, nothing asks "Mark done?" | Yes. Only the menu lines "Start Focus" and "Stop Focus" were there. `store.focus` changed and no screen showed it. | Yes | `planner_focus_test.dart` (21), 3 golden pictures, 1 device test |
| 3 | Planner paths with no test through the screen | Yes. The paths worked, and no test went through the screen for them. | Yes, tests only. They found no bug in the planner. | `planner_menu_test.dart` (26), `planner_paths_test.dart` (56), 5 device tests |
| 4a | Pinch zoom | Yes. The Mac grid has a pinch (36 to 160 points for one hour). The Flutter grid had none. And two fingers on a block could move the block. | Yes | `planner_pinch_test.dart` (12), 1 device test (phones) |
| 4b | The grow-in after "Fit" | Yes. The plan asks for it (§5.1.7). The Mac source has no code for it of its own. The Flutter grid showed the block at once. | Yes | `planner_fit_test.dart` (6) |
| 4c | The note icon on a block | Half. The plan asks for it (§5.1.2). No app draws it, and no store sets `PlannerBlock.hasNote` for a block. | The drawing only | `planner_note_icon_test.dart` (5). The flag is a request to Track A; Q-35 asks the owner for the rule. |
| 4d | Overlaps cascade in layers, not equal columns | Not a gap of the port. The Mac source does the same as the Flutter app. | Nothing changed | Noted for the owner here. |

All test files are in `app/test/ui/planner/`. All code is in `app/lib/ui/planner/`.

## 1 · Subtasks on goal blocks

Source: the Swift branch `feat/planner-subtasks` (`BlockView.swift`, `BlockSubtaskEditor.swift`, `PlannerGrid.swift`).

- A tall goal block shows its subtasks, one line each, with a small mark. When not all fit, the last line says "+N more" with the count of done ones. A short block shows a count ("1/4") after the title.
- Each block of a goal has its own subtasks.
- The menu of a goal block has "Add Subtasks…" (none yet) or "Subtasks…" (it has some). A task block and a plain event have no such line.
- The line opens a small window: the title of the block, the count, one row per subtask (check box, name, bin), a field for a new one, and "Done". Return adds. Escape or "Done" closes. A name saves at Return, when the keys leave the field and when the window closes. An empty name puts the saved name back.
- The window closes by itself when the store closes it or when its block goes away. It fits on a phone.

New: `block_subtask_editor.dart`. Changed: `block_view.dart`, `planner_grid.dart`, `planner_view.dart`, `planner_geometry.dart`, `planner_dialogs.dart` (`PlannerSheet` is public now).

Tests: `planner_subtasks_test.dart`, 22 tests in 3 groups ("subtasks in a goal block", "the menu line for subtasks", "the subtask window of a goal block"). Golden picture `goldens/planner_subtasks_grove_light.png`: a tall goal block with its subtask lines, a short one with a count, and the window over them.

## 2 · The focus timer

Source: `PLAN.md` §5.1.7 ("Focus mode": a floating mini timer counts down; at the end it asks "Mark done?") and the Swift `Planner/FocusCard.swift`.

- "Start Focus" in the menu of a block shows a card 230 points wide, 16 points from the bottom right corner. It has the title of the block, a clock that counts down each second, a bar, and a cross that stops the session. A session of more than one hour shows the hours.
- At the end of the block the card asks "Mark done?" with "Mark done" and "Not yet". A block with no task says "Time is up." with "OK".
- A session that ended while another screen was in front asks at once when the card shows. A new session on another block takes the place of the old one.
- The rest of the screen still takes clicks. The card shows on Planner, Today and Calendar. It fits on a phone. With motion on it slides in from the right.
- A screen reader hears the timer and the time left.

New: `focus_card.dart` (`FocusCard`, `FocusLayer`). Changed: `planner_view.dart` (it puts `FocusLayer` around the planner).

Tests: `planner_focus_test.dart`, 21 tests in 2 groups ("the focus timer", "the focus card alone"). Golden pictures: `goldens/planner_focus_done_grove_light.png`, `goldens/focus_card_grove_light.png`, `goldens/focus_card_futuristic_dark.png`. Device test: 'focus: "Start Focus" shows the timer; the cross stops it'.

## 3 · Tests through the screen

No planner code changed in this part. No test of this part showed a bug in the planner.

`planner_menu_test.dart` (26):

| Group | Tests | What they do |
|---|---|---|
| the menu of a block | 16 | A right click shows the right lines for a task block, an event and a goal block. Each line is used: Duration, Colour, Duplicate, Split in Two (and the message for a block of 15 minutes), Mark Done and Mark Not Done, Unschedule, Delete Task, Edit Event…, Delete Event. A click away closes the menu. The menu of a selected block works on all selected blocks. A long press with a finger opens the menu. |
| clicks | 10 | A click on a task block selects it and shows the task at the side. A click on an event opens its card. A double click opens the title of a task block and of a goal block, and the card of an event. A double click on empty time starts a block of 30 minutes; a double tap with a finger too. Two slow clicks do nothing more than two clicks. |

`planner_paths_test.dart` (56):

| Group | Tests | What they do |
|---|---|---|
| the command key | 3 | Held at the end of a drag on empty time, or at Return in the title: an event. Let go before the end: a task. |
| "Schedule existing task" | 4 | Two letters show the open tasks with that name, three at most. A click gives the task the time of the draft. Return makes a new task. A task with a time on this day is not in the list. |
| Shift at the end of a drag | 6 | A move or a longer block pushes the blocks under it. The message says "Pushed 1 block" or "Pushed N blocks". No Shift, or Shift let go before the end: nothing is pushed. A block above stays. |
| more than one block | 6 | A click with the command key adds and takes out. A drag of one selected block moves all. They stop together at the end of the day. Delete and the arrows work on all. |
| auto-scroll | 6 | A block held near the top or bottom edge scrolls the grid and goes with it. Nearer the edge is faster. The grid stops at the end of the day. A new block grows while the grid scrolls. A finger does the same. |
| keys | 5 | Space marks the selected task block, the selected goal block, or all selected ones. The command key with D puts a copy after the block. |
| zoom | 6 | The command key with + and −, the number pad too. The two buttons. Never under 36 or over 160. A drag after a zoom still follows the pointer. |
| a repeating event | 9 | A drag, a drag to another day, a new length, "Delete Event" and "Duration" ask "This event only" or "All events", each with its own word. Each answer does its work; "Cancel" puts the block back. A copy or a split says that it cannot be done. |
| the all-day strip | 4 | An all-day event is in the strip and not on the grid. No all-day event: no strip. A click opens the card. A phone shows the events of its one day. |
| the day totals | 7 | The bar in the header shows planned time against the limit. The pointer over it shows the numbers. They follow a change. Two blocks at the same time count once. A day over the limit says so, and a change that goes over opens "Busy day". |

Device tests, where a real pointer matters (in `app/integration_test/planner_test.dart`):

| Test | Runs on |
|---|---|
| menu: a long press or a right click opens the menu of a block | all 4 |
| double tap: two taps on empty time start a block of 30 minutes | all 4 |
| Shift at the end of a drag pushes the next block down | macOS, Windows (needs a mouse and a keyboard) |
| the command key at the end of a drag on empty time makes an event | macOS, Windows |
| two blocks: a command-click adds a block, a drag moves both | macOS, Windows |

## 4a · Pinch zoom

Source: the Swift `PlannerGrid.swift` (`MagnifyGesture`, hour height 36 to 160).

- A pinch on a trackpad changes the height of an hour. Two fingers on a touch screen do the same.
- The hours follow the fingers at once, also with motion on. The height is saved once, at the end of the pinch.
- The limits are 36 and 160, the same as the keys and the buttons. A second pinch starts from the height of the first.
- Two fingers that only slide on a trackpad scroll the grid and do not zoom.
- Under two fingers the grid does not scroll, no block moves, no block is made and no menu opens. This was a real bug before: with two fingers down, a block under the first finger could move.
- After a pinch one finger scrolls again, and a hold and drag makes a block at the place of the finger.

Changed: `planner_grid.dart`.

Tests: `planner_pinch_test.dart`, 12 tests ("a pinch on a trackpad" 6, "a pinch with two fingers on a phone" 5, one for motion). Device test 'pinch: two fingers apart make the hours taller' (Android and iOS).

## 4b · The grow-in after "Fit"

Source: `PLAN.md` §5.1.7 ("Animate the block growing in").

- The block that "Fit" makes fades in and grows from 85 % to its full size in 0.22 s. Both ways to "Fit" do it: the small button on a sticky note and "Fit in Next Gap" in the menu of a note.
- With motion off the block is there at once.
- A block made by a drag does not grow in. A block that comes back with Undo does not grow in again. When there is no free time, the message shows and nothing grows.

Changed: `planner_grid.dart` (`growNew`), `sticky_strip.dart` (`aroundFit`), `planner_view.dart`.

Tests: `planner_fit_test.dart`, 6 tests. I wrote them before the code but ran them first after it. So I took the code out again to check them: 3 of the 6 fail without `growNew`.

## 4c · The note icon

Source: `PLAN.md` §5.1.2 ("a small ✎ icon if linked notes exist").

- `BlockView` draws a small pencil after the title when `block.hasNote` is true. A short block shows it in its one line. A block narrower than 104 points leaves it out, so the title keeps its room. A screen reader hears "Has a linked note" with the block.
- No block has the icon in the app today. `PlannerBlock.hasNote` is never set for a block by `store.blocks()`. The Mac app is the same: the field is there, nothing sets it, and `BlockView.swift` draws no icon.
- What is open: which note is "linked" to a block, and the store code for it. See Q-35 and the request to Track A in `docs/tracks.md`.

Changed: `block_view.dart`.

Tests: `planner_note_icon_test.dart`, 5 tests on a block built by hand.

## 4d · Overlaps

The check said: "overlaps cascade in layers, not equal columns". That is true, and it is the same in the Mac source (`PlannerGeometry.swift`): a block that starts inside a longer one lies on top of it with an inset. Nothing changed. If the owner wants equal columns, it is a change of both apps.

## CI

Commit `096e994` (the head with all code: the merge of `feat/cross-platform-flutter`, `b7a20b9`, into this branch), workflow `flutter`, 2026-10-11. The merge changed no planner file.

Run 38157016863 (push) and run 38157020499 (pull request #15): both green on the 4 jobs at the first try. The numbers are the same in the two runs.

| Job | Test | Build | Integration test (16 tests) |
|---|---|---|---|
| `build (ubuntu-latest, android)`, Android emulator | pass (2249, 1 skipped) | pass | pass (13, 3 skipped) |
| `build (windows-latest, windows)` | pass (2249, 1 skipped) | pass | pass (15, 1 skipped) |
| `build (macos-latest, macos)` | pass (2250) | pass | pass (15, 1 skipped) |
| `build (macos-latest, ios)`, iPhone simulator | pass (2250) | pass | pass (13, 3 skipped) |

The skips are on purpose. On Linux and Windows one golden picture of F9 is parked (Q-17). On the phones the 3 device tests that need a mouse and a keyboard are skipped. On the computers the pinch with two fingers is skipped.

No golden picture failed. The 4 new pictures against the limit of 0.2 % (from the job logs of run 38157016863):

| Picture | Linux | Windows | macOS, iOS job |
|---|---|---|---|
| `planner_subtasks_grove_light.png` | 0.094 % | 0.096 % | 0.000 % |
| `planner_focus_done_grove_light.png` | 0.041 % | 0.032 % | 0.000 % |
| `focus_card_grove_light.png` | 0.016 % | 0.006 % | 0.000 % |
| `focus_card_futuristic_dark.png` | 0.000 % | 0.006 % | 0.000 % |

Before the merge, commit `00974f7` (the merge of `feat/xp-screens` on top of `b2f1e5b`): run 38146389696 (pull request #15) was green on the 4 jobs (2229 tests; 2228 and 1 skipped on Linux and Windows). Run 38146327066 (push) was green on android, windows and ios at the first try. Its macOS job was red at the first try: 2228 tests passed and 1 failed, in the step "Test". That one job ran again (`gh run rerun 38146327066 --failed`) with no change of code, and it was green.

- The red test was `app/test/state/sync_store_test.dart`, "a change goes to the account some moments later" (line 341: expected 0, got 1). It is Track A's test, and not a planner test. It is the same test that failed once before on a slow CI machine (see `docs/tracks.md`, "a test of yours failed once on the CI"). Nobody touched it here. Track A's fix (`5936405`) came with the merge of PR #13, and the test passed in the 8 jobs of `096e994`.

## Notes

- The zoom keys and N work only while the grid has the keyboard. Right after the planner opens, the grid does not have it; a click on the grid gives it. The Mac app is the same.
- The Flutter shell has no menu command "Zoom In" and "Zoom Out" (the Mac app has them in the View menu, `GroveApp.swift`). The keys work in the grid. A request to the owner of the shell is in `docs/tracks.md`.
- The list "Schedule existing task" can be under the lower edge of the grid when the draft is at the bottom of the view. The Mac app is the same.
- `PLAN.md` §5.1.4 lists "Open / create linked note" in the menu of a block. No app has that line. It is part of Q-35.
- The day totals are in the tooltip of the bar in the header, as on the Mac.
- After a zoom the grid keeps its scroll place in points, not the time under the fingers. The Mac app is the same.
- `./scripts/flutter_integration.sh android` cannot start its own emulator on this Mac (the image is x86_64, the Mac is arm). I started the emulator `RealTraveller_Pixel7` read-only and ran `flutter test integration_test/planner_test.dart -d emulator-5554` from `app/`: 13 pass, 3 skipped. The script is not mine and did not change.
- The device test for focus uses a day in 2099 and the test hook `FocusCard.clock`: `store.startFocus` reads the real clock (a request to Track A is in `docs/tracks.md`).

## Not verified

- A pinch on a real trackpad (Mac or Windows). The tests use the trackpad events of the test framework. No CI job has a trackpad.
- A pinch with two real fingers on a real phone. The device test sends two touch pointers on the emulator and the simulator.
- The system notification at the end of a focus session. That is the store's and the system's part; no test here looks at it.
- The bar of the focus card for a session that the store made with the real clock. The tests set the clock of the card.
- Command with Return in the title field on a real keyboard. The test uses the test text input.
- The look of the grow-in and of the slide of the focus card. The tests read the numbers of the animation; nobody looked at it on a screen.
- The planner by hand on a real device. This Mac has no Xcode, so the macOS and iOS device tests ran only in CI.
