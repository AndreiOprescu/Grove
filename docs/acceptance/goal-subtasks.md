# Subtasks of a goal (`goal_subtasks`) — proof

Branch `feat/xp-goal-subtasks`, into `feat/cross-platform-flutter`. Flutter app only: nothing in `Sources/` (the Swift Mac app) changed.
The owner's words: "I want goals to also have subtasks. A goal category (not an instance) shares the subtasks, and are listed under the goal on the left goal panel. They can be added by clicking on the goal on the left panel and adding a subtask. 3 subtasks should be displayed under the goal, and can be expanded by clicking on the goal."
Check: `./scripts/flutter_test.sh` (2026-10-12: 2560 tests passed, analyze clean, format clean). 104 of them are new. The base had 2456.
CI: see "CI" at the end.

## What was built

| Part | File |
|---|---|
| The model | `app/lib/core/model/goal_subtask.dart` (`GoalSubtaskItem`) |
| Shared migration 8: the table `goal_subtasks` (`goal_id` points at the goal, `ON DELETE CASCADE`) and its index | `app/lib/data/migrations.dart` (`Migrations.all`, 8 entries) |
| The table joins the sync: list of synced tables (right after `goals`), sync migration 4 | `app/lib/data/migrations.dart` (`SyncMigrations`) |
| The repository | `app/lib/data/repos.dart` (`GoalSubtaskRepo`, `Repos.goalSubtasks`) |
| Undo and redo | `app/lib/state/mutation.dart` (`Mutation.goalSubtasks`), `app/lib/state/app_store.dart` (`commit`, `_apply`) |
| The store calls | `app/lib/state/store_goal_subtasks.dart` (`goalSubtasks`, `goalSubtasksOf`, `addGoalSubtask`, `toggleGoalSubtask`, `renameGoalSubtask`, `deleteGoalSubtask`) |
| What a closed goal shows | `app/lib/state/rules/goal_subtask_rules.dart` (`closedCount = 3`, `closed`, `moreLine`) |
| The subtasks under a goal, closed and open | `app/lib/ui/goals/goal_subtasks.dart` (`GoalSubtasksClosed`, `GoalSubtasksOpen`) |
| A click opens the subtasks; "Edit goal…" opens the editor | `app/lib/ui/goals/goal_row.dart`, `app/lib/ui/goals/goals_pane.dart` |
| SQL for Supabase, the whole schema with number 8 | `supabase/migrations/20261012000000_grove_sync_goal_subtasks.sql` (new file; the file of 2026-10-11 is not changed) |

No new package. The export code and the sync engine did not change: they read the list of tables.

## How it works

- A closed goal shows its first 3 subtasks that are not done, each with a check box. Under them a line says what is not shown: "+2 more", "+2 more · 1 done" or "1 done".
- A click (or a tap) on the goal opens it: all subtasks, done ones with a line through the name, and the line "Add a subtask". Type and press Return: the subtask is under the goal, and the line is ready for the next one. A second click closes the goal.
- In the open goal: tick, type a new name, or delete with the bin. Each is one undo step.
- A tick works in the closed goal too. The ticked subtask leaves the 3 and the next one shows.
- The editor of the goal (name, colour, target, archive, delete) is under "Edit goal…" in the open goal, and under "Edit…" in the right-click menu (Q-48).

## The two lists: of a goal and of a block

They are separate. No code of the block subtasks changed.

| | List of the goal (new) | List of one block (was there) |
|---|---|---|
| Table | `goal_subtasks`, a row points at a goal | `block_subtasks`, a row points at one block |
| Who has it | The goal. Each block of the goal on each day has the same list, because no row is stored on a block | One block only. Another block of the goal has its own |
| Where it shows | Only in the Goals panel, under the goal | Only inside the block in the planner, and in its "Subtasks…" window |
| How the UI keeps them apart | The panel never shows a block's list | The window says "Only this block has these. Other blocks of the goal keep their own." A block never shows the goal's list |

A tick of a goal subtask does not tick a block, and a done block does not tick a goal subtask (test "a tick of a subtask does not tick a block…").

## Proof for each check of the owner

| Check | Tests (all green) |
|---|---|
| Click a goal in the left panel: it opens, I type a subtask and press Enter, it shows under the goal | `goal_subtasks_test.dart`: "opens it, and a typed line with Return is a new subtask under the goal", "a mouse click opens it too", "in the whole app on a computer window: a tap opens a goal, a typed line is a subtask, a tap ticks it" |
| With 5 subtasks the closed goal shows 3 and tells me there are more; a click shows all 5 | `goal_subtasks_test.dart`: "shows three when it is closed and says that there are more", "a click shows all five, a second click three again"; `goal_subtask_store_test.dart`, group "What a closed goal shows" (3); pictures `goals_phone_grove_light.png` (closed, "+1 more · 1 done") and `goals_desktop_*_light.png` (open, 5 subtasks) |
| I check one off; it stays checked after I leave the screen and come back | `goal_subtasks_test.dart`: "the tick is still there after the panel went away and came back" |
| … and after the app starts again | `goal_subtask_store_test.dart`: "subtasks and their ticks are in the database file" (a store on a file in a temporary folder, closed, a new store on the same file); `goal_subtask_test.dart`: "a tick is still there after the file is closed and opened again". Not the real app, not the real data |
| Two blocks of the same goal on two days: the list is the same one | `goal_subtask_store_test.dart`, group "One list for every block of the goal" (5): "two blocks of the goal on two days have the same list", "a tick shows for every block of the goal", "a deleted block leaves the list of the goal"; `goal_subtask_test.dart`, same group (3) |
| It works with touch on a phone layout too | `goal_subtasks_test.dart`, group "a phone" (2): "a tap opens the goal, the keyboard adds a subtask, a tap ticks it", "the places to tap are as large as a finger needs" (28 points); "in the whole app on a phone: …"; the device test "goals: a tap opens a goal, a typed line is a subtask of the goal, a tap ticks it" in `app/integration_test/planner_test.dart` (CI only: Android emulator, iOS simulator, macOS, Windows) |

## Proof for the other rules

| Rule | Tests |
|---|---|
| A subtask needs its goal. A deleted goal takes its subtasks, Undo brings them back with their ticks. An archived goal keeps them | `goal_subtask_test.dart`, group "The list of a goal"; `goal_subtask_store_test.dart`, group "The goal goes or changes" (4); `goal_subtasks_test.dart` "a deleted goal takes its subtasks out of the panel, and undo shows them again" |
| Add, tick, rename and delete are one undo step each | `goal_subtask_store_test.dart`, group "Tick, rename, delete, with undo" (7) |
| An empty line adds nothing; Esc clears the line; a typed line is added when the line loses the keys | `goal_subtasks_test.dart`, group "a click on a goal" |
| One goal is open at a time; the editor shows under "Edit goal…" | `goal_subtasks_test.dart` "one goal is open at a time", "\"Edit goal…\" shows the editor of the goal under the subtasks, and hides it again"; `goals_pane_test.dart` (the editor tests) |
| A version 7 database upgrades and keeps its data | `goal_subtask_test.dart` "upgrading a version 7 database keeps its data", "the shared schema has the table and its index" |
| The export file says schema 8 and has the table right after `goals`. A file of schema 6 or 7 still imports. A file of a newer Grove is refused | `goal_subtask_test.dart`, group "Export and import" (6); `data_export_test.dart` (the two Mac files) |
| Sync: the table has the sync columns; a database of an older build gets them at the next open | `goal_subtask_sync_test.dart`, group "The schema" (5) |
| Sync: each write is in the outbox, also the subtasks that go with a deleted goal | `goal_subtask_sync_test.dart`, group "What the outbox writes down" (3) |
| Sync: subtasks travel between two devices; delete goal against tick or add; the later change stays; an import replaces them | `goal_subtask_sync_test.dart`, group "Two devices" (9) |
| Sync: 3 devices with random edits end the same | `goal_subtask_sync_test.dart`, group "Many devices" (12 seeds) |
| The SQL file in the repository is what the generator makes | `supabase_sql_test.dart` "the newest file in supabase/migrations is the SQL of this schema" (was there; the new file is the newest now) |
| The SQL on a real Postgres: both files in name order, two times, then the checks | CI workflow `supabase-sql` (`supabase/tests/run.sh`); 15 tables, 45 policies, schema number 8 |
| Texts on whole pixels; a screen reader can tick and open | `goal_subtasks_test.dart` "the texts of the subtasks sit on whole pixels", "a screen reader can tick a subtask and open the goal" |
| The look in the 4 themes, dark, and a phone | `goals_golden_test.dart` (7 pictures; 6 made again, see below) |

New tests by file: `app/test/data/goal_subtask_test.dart` 22, `app/test/state/goal_subtask_store_test.dart` 27, `app/test/sync/goal_subtask_sync_test.dart` 29, `app/test/ui/goals/goal_subtasks_test.dart` 26. One new device test in `app/integration_test/planner_test.dart` (not in the count: it runs in CI only).

Tests first: each of the four new test files was written before its code. The first runs failed because `GoalSubtaskItem`, `Repos.goalSubtasks`, the store calls and the widgets did not exist.

## Older tests that changed

| Test | Change | Why |
|---|---|---|
| `database_test.dart` "there are eight migrations: the seven of the Mac app, and one of this app only" | New name; 7 → 8 migrations; the table list has `goal_subtasks` | Migration 8 |
| `block_subtask_test.dart` (export) | The schema of the file is `Migrations.all.length`, not the number 7 | Migration 8 |
| `data_export_test.dart` (the Mac files, schema 7 and 6) | Our file says schema 8 and has one more table, `goal_subtasks`, which is empty; the rest is compared as before | A Mac file has no such table |
| `sync_engine_test.dart` `fill`, `sync/support.dart` | Adds one subtask of a goal | "A second device gets every kind of row" needs a row in each synced table |
| `block_subtask_sync_test.dart` "a database of an older build…" | The script that makes the old database also drops `goal_subtasks` | The script goes back to schema 6, and migration 8 runs again after it |
| `goals_pane_test.dart`: the 6 editor tests and the phone test | They open the editor with a tap on the goal and then on "Edit goal…". The first is now named "\"Edit goal…\" in the open goal opens it, a click on the goal closes it" | A click on a goal opens the subtasks now (Q-48). No check was taken out |
| `goals_golden_test.dart` | The scene has subtasks (5 for "Read", one done; 2 for "Gym"). The 4 theme pictures show "Read" open; the dark picture shows "Gym" open with its editor; the phone picture shows the closed goals | The new look |
| `supabase/tests/sync_test.sql`, `after_rerun_test.sql` | Schema number 7 → 8 ("older" 7, "newer" 9); 14 → 15 tables; 42 → 45 policies | One more table |

Pictures made again on this Mac and looked at one by one: `goals_desktop_grove_light.png`, `goals_desktop_grove_dark.png`, `goals_desktop_minimal_light.png`, `goals_desktop_vintage_light.png`, `goals_desktop_futuristic_light.png`, `goals_phone_grove_light.png` (in `app/test/ui/goals/goldens/`). `goals_desktop_empty_grove_light.png` did not change. The 0.2 % limit and the comparator did not change.

## Not built

- Putting the subtasks in another order. A new one goes to the end.
- Anything in a planner block: a block does not show the list of its goal.
- The Swift Mac app.

## Not verified

- Nobody looked at it in the running app. The app was not started on this Mac (a build here opens the owner's real data). The proof is tests and pictures. The pictures use the test font (blocks for letters), so they show places and sizes, not the real letters.
- The device test was not run on this Mac. It runs in CI.
- No call to a real Supabase project. The SQL ran only on the Postgres of the CI runner, in this order: the file of 2026-10-11, then the file of 2026-10-12. The new file alone on an empty database was not run there (it is made by the same generator and has the whole schema).
- An upgrade of a real database of the owner from schema 7 to 8 was tested only on a test database.

## For the owner

- **Supabase.** When you set up the project (you have not run a file yet): in the SQL Editor run the whole file `supabase/migrations/20261011000000_grove_sync.sql` first, then the whole file `supabase/migrations/20261012000000_grove_sync_goal_subtasks.sql`. The app and the server must have the same schema number (8 now), so the sync of this build does not work with the first file only. The steps are in `docs/acceptance/F11-login.md`, step 2.
- **The Mac app.** An export file of this build says schema 8. The Swift Mac app refuses it ("from a newer Grove"). This app still imports the files of the Mac app (Q-49).
- **By hand, in the app** (after the merge and a new build): the 5 checks of the table above.

## CI

Filled in after the runs (see the pull request).
