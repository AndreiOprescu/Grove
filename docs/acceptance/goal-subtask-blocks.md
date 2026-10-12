# A subtask of a goal in a block of the goal — proof

Branch `feat/xp-goal-subtask-blocks`, into `feat/cross-platform-flutter`. Flutter app only: nothing in `Sources/` or `Tests/` (the Swift Mac app) changed.
The owner's words: "Make the subtasks of a goal be assignable to an instance of the goal on the planner. The subtask should be removed from the general goal once done."
The owner's choices (2026-10-12): "Link it" (the subtask stays one row, with a pointer to the block) and "Drag from the Goals panel". The owner said yes to the plan with the 10 rules below.
Check: `./scripts/flutter_test.sh` (2026-10-12: 2751 tests passed, analyze clean, format clean). The base had 2612.

## What was built

| Part | File |
|---|---|
| Shared migration 9: the column `goal_subtasks.event_id` (points at the block, `ON DELETE SET NULL`) and its index | `app/lib/data/migrations.dart` (`Migrations.all`, 9 entries) |
| New order of the synced tables and of the export tables: `goal_subtasks` is after `events` and `block_subtasks` | `app/lib/data/migrations.dart` (`SyncMigrations.syncedTables`), `DataExport.tables` |
| The model | `app/lib/core/model/goal_subtask.dart` (`eventId`, `isPlanned`) |
| The repository | `app/lib/data/repos.dart` (`GoalSubtaskRepo.forEvents`, `EventRepo.byIds`) |
| The store calls | `app/lib/state/store_goal_subtasks.dart` (`assignGoalSubtask`, `unassignGoalSubtask`, `plannedGoalSubtasks`, `freeGoalSubtasks`, `canDropGoalSubtask`, `dropGoalSubtaskOnBlock`, `goalSubtaskMarks`) |
| A deleted block gives its subtasks back, in the same undo step | `app/lib/state/app_store.dart` (`_unplanSubtasksOfDeletedBlocks`) |
| A goal block has the planned subtasks first, then its own | `app/lib/state/store_planner.dart` (`blocks`), `app/lib/state/rules/block_subtask_row.dart` (`BlockSubtask.fromGoal`) |
| What the goal shows, and the mark of the block | `app/lib/state/rules/goal_subtask_rules.dart` (`inGoal`, `moreLine`, `planMark`) |
| The text that a dragged subtask carries | `app/lib/state/rules/drag_payload.dart` (`goalSubtask`, `goalSubtaskId`) |
| Goals panel: drag a line, the grip in the open goal, the mark | `app/lib/ui/goals/goal_subtasks.dart`, `goal_row.dart`, `goals_pane.dart` |
| Planner: a goal block takes the drop and shows a frame | `app/lib/ui/planner/planner_grid.dart` (`_subtaskDrop`) |
| The "Subtasks…" window of a goal block: both kinds, the arrow "back to the goal", the part "From the goal" | `app/lib/ui/planner/block_subtask_editor.dart` |
| SQL for Supabase, the whole schema with number 9 | `supabase/migrations/20261013000000_grove_sync_goal_subtask_block.sql` (new file; the two older files are not changed) |

No new package. The sync engine did not change: it reads the list of tables and the columns of each table.

## Proof for each rule

Test files: `store` is `app/test/state/goal_subtask_store_test.dart`, `panel` is `app/test/ui/goals/goal_subtasks_test.dart` (group "a subtask in a block of the goal", the whole app at 1100×620), `window` is `app/test/ui/planner/planner_subtasks_test.dart` (group "subtasks of the goal in the window of a block").

| # | Rule | Tests (all green) |
|---|---|---|
| 1 | Drag a subtask from the Goals panel, drop it on a block of the same goal: the block shows it | `panel` "a drag onto a block of the goal plans it there: the block shows it, and the goal shows it with the mark of the block", "in the open goal an open subtask has a grip, and a drag of the grip plans the subtask"; `store` "a drop on a block of the same goal plans it there", "a planned subtask shows in its block, and only there" |
| 2 | The goal still shows it, with a mark of the block, until it is ticked | `panel` (the same first test: "Today 11:00"); `store` "it is still one subtask of the goal: the goal shows it until it is ticked", group "The mark of the block on a planned subtask" (2) |
| 3 | Tick it: it leaves the goal list (not in the 3 lines, not in the open goal, not in "N done"). The block keeps it, ticked | `panel` "a tick takes a planned subtask out of the goal: it is not in the lines, not in the open goal and not in the count. The block keeps it"; `store` "a tick takes it out of the list of the goal, and the block keeps it", "a done subtask that is in no block stays in the goal"; `window` "a tick ticks the subtask of the goal, and a second tick opens it again" |
| 4 | Untick it: the goal shows it again | `panel` (the same test, its last part); `window` (the same test) |
| 5 | One subtask is in one block at most; a drop on another block moves it | `panel` "a drop on a second block of the goal moves it there"; `store` "a subtask is in one block at most: a second block takes it from the first", "the same block again changes nothing and is no undo step" |
| 6 | Delete the block: the subtask goes back to the goal with no mark; Undo puts it back | `panel` "a deleted block gives the subtask back to the goal with no mark, and Undo puts it in the block again"; `store`, group "The block of a planned subtask goes" (6); `app/test/data/goal_subtask_test.dart` (the database rule) |
| 7 | A drop on a block of another goal, on a task block or on an empty place does nothing | `panel` "a drop on a block of another goal, on a task block or on an empty place does nothing", "only a block that can take the subtask shows a frame while the subtask is over it"; `store` "a block of another goal, a task block, an event and a missing block take no subtask", "a drop on another block, or of another thing, does nothing", "a done subtask cannot be dragged into a block" |
| 8 | The block shows the linked subtasks first (goal order), then its own | `store` "the block shows the planned subtasks first, in the order of the goal, then its own subtasks"; `window` "shows the subtasks of the goal first, then the ones of the block, and counts both" |
| 9 | The window of a goal block shows both kinds; a linked one has "back to the goal"; its bin deletes the subtask for good | `window` "the arrow puts the subtask back in the goal: the block no longer has it, and \"From the goal\" has it", "the bin deletes the subtask from the goal too", "a new name with Return is the name of the subtask of the goal", "the window stays when the last subtask of the goal goes back to the goal"; `store` "\"back to the goal\" takes it out of the block, with undo" |
| 10 | Phone: the window has a part "From the goal"; one tap puts an open, free subtask in this block | `window` "on a phone: one tap on a line of \"From the goal\" puts the subtask in the block, and the places to tap fit a finger" (390×844, 28 points), "\"From the goal\" has the open subtasks of the goal that are in no block, and a click puts one in this block", "a block with its own subtasks only, of a goal with no free subtask, has no \"From the goal\" part"; `store` "the subtasks of the goal that a block can take: open, and in no block" |

## Proof for the other rules

| Rule | Tests |
|---|---|
| A click on a line that can be dragged still opens the goal, and a click on its box still ticks | `panel` "a click on a line that can be dragged still opens the goal, and a click on its box still ticks it" |
| The texts stay on whole pixels with the mark | `panel` "the mark does not push the name off its pixels" |
| A version 8 database upgrades and keeps its data; the column and the index are there | `app/test/data/goal_subtask_test.dart`, `app/test/data/database_test.dart` |
| The export file says schema 9; a file of schema 6, 7 or 8 still imports | `app/test/data/goal_subtask_test.dart`, `app/test/data/data_export_test.dart` |
| A copy of a block does not take the planned subtask; a block cut in two keeps it on the first half; a deleted goal takes its planned subtasks | `store` "a copy of the block does not take the planned subtask", "a block that is cut in two keeps the planned subtask on its first half", "a deleted goal takes its planned subtasks too…" |
| Sync: a database of an older build (schema 8, sync on) gets the column, and the triggers see it | `app/test/sync/goal_subtask_sync_test.dart`, group "The schema" |
| Sync: a deleted block writes down its planned subtask as a saved row, in no block | the same file, group "What the outbox writes down" |
| Sync on two devices: the plan travels; a push that stops half way leaves no subtask that points at a missing block; taken out; moved; deleted block; delete against plan; tick against delete; deleted goal | the same file, group "A subtask planned in a block, on two devices" |
| Sync: 3 devices with random edits (now also: new block, plan, take out, delete block) end the same | the same file, group "Many devices" |
| The SQL file in the repository is what the generator makes | `app/test/sync/supabase_sql_test.dart` |
| The look | `app/test/ui/goals/goals_golden_test.dart`: 6 pictures made again (the scene has one planned subtask) |

Tests first: the tests of the data, the store and the sync were written before their code and failed first. The two screen test files were written before the screen code.

The table order: with the old order (`goal_subtasks` right after `goals`) the test "a push that stops half way…" fails. With the new order it passes. See `docs/assumptions.md`.

## Different from the plan

- The grip in the open goal is at the right, before the bin. The plan said left.
- The drop area is on each goal block itself. The plan said one search for the block under the pointer in the day column. A block takes the pointer before the day column, so the plan's way cannot work.
- The pictures of the Goals panel were made again (6 files).

## Not built

- A drop on an empty place of the planner that makes a new block with the subtask.
- Putting the subtasks in another order.
- A new device test. The widget tests cover a computer size and a phone size.
- Anything in the Swift Mac app.

## Not verified

- Nobody looked at it in the running app. The app was not started on this Mac (a build here opens the owner's real data). The proof is tests and pictures. The pictures use the test font (blocks for letters), so the mark looks cut there; with the real font "12 Oct 10:00" must fit in 84 points. The owner should look at it once.
- `supabase/tests/run.sh` did not run on this Mac (no `psql`). The CI ran it; see "The CI" below.
- No call to a real Supabase project.
- An upgrade of a real database of the owner from schema 8 to 9 was tested only on test databases.

## The CI

For commit `209da79`, on draft PR #26:

- `flutter`, run 38260692400 (the run of the PR): green on the 4 systems (macOS, iOS, Android, Windows).
- `supabase`, runs 38260692390 and 38260661099: green. This is `supabase/tests/run.sh` with the three SQL files on Postgres.
- `flutter`, run 38260661027 (the run of the push, same commit): Android and Windows green. Somebody cancelled the macOS and the iOS job while they ran. No test failed in it.

## For the owner

- **Supabase (only if you use the sync).** Run the whole file `supabase/migrations/20261013000000_grove_sync_goal_subtask_block.sql` in the SQL Editor, after the two older files. The app and the server must have the same schema number (9 now). `README.md` and `docs/acceptance/F11-login.md` say this too.
- **The Mac app (Swift).** An export file of this build says schema 9. The Swift app refuses it, as it refuses schema 8 (Q-49).
- **By hand, in the app** (after the merge and a new build): the 10 rules of the table above.
