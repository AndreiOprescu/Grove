# Migration 7 · Subtasks in planner blocks (`block_subtasks`) — proof

Plan: `docs/cross-platform-plan.md` (the port follows the Mac app). Track A, branch `feat/xp-engine` (`docs/tracks.md`).
Source: Swift PR #3 (subtasks of a task show in its blocks, on `main`) and Swift PR #4 (a goal block has its own subtasks, shared migration 7). PR #4 is on the branch `feat/planner-subtasks`, not on `main` (see "For the owner").
Check: `./scripts/flutter_test.sh` (2026-10-10: 1369 tests passed, analyze clean, format clean). 78 of them are new.
CI: see the line at the end.

## What was built

| Part | File |
|---|---|
| Shared migration 7, word for word from the Mac app | `app/lib/data/migrations.dart` (`Migrations.all`, 7 entries) |
| The table joins the sync: list of synced tables, sync migration 3 | `app/lib/data/migrations.dart` (`SyncMigrations`), `app/lib/data/sync_schema.dart` (`SyncSchema.addTable`) |
| The model | `app/lib/core/model/block_subtask.dart` (`BlockSubtaskItem`) |
| The repository | `app/lib/data/repos.dart` (`BlockSubtaskRepo`, `Repos.blockSubtasks`) |
| Undo and redo | `app/lib/state/mutation.dart` (`Mutation.blockSubtasks`), `app/lib/state/app_store.dart` (`commit`, `_apply`) |
| The store calls | `app/lib/state/store_block_subtasks.dart` (`blockSubtasks`, `addBlockSubtask`, `toggleBlockSubtask`, `renameBlockSubtask`, `deleteBlockSubtask`, `openBlockSubtasks`, `closeBlockSubtasks`), `AppStore.editingBlockSubtasks` |
| Subtasks inside each block | `app/lib/state/rules/block_subtask_row.dart` (`BlockSubtask`), `app/lib/state/rules/planner_block.dart` (`PlannerBlock.subtasks`), `app/lib/state/store_planner.dart` (`blocks`) |
| The two labels | `app/lib/state/rules/subtask_rules.dart` (`moreLabel`, `badge`) |
| A real Mac export file with subtasks | `app/test/fixtures/mac_export_v7.json` |

No new package. The export code and the sync engine did not change: they read the list of tables.

## Proof for each rule

| Rule (PLAN.md of PR #3 and PR #4) | Tests (all green) |
|---|---|
| A task block shows the subtasks of its task, in panel order, without cancelled ones | `block_subtask_store_test.dart`, group "A task block" (5) |
| A goal block has its own subtasks. Another block of the same goal has none. A new block starts empty | `block_subtask_store_test.dart`, group "One instance only" (6); `block_subtask_test.dart`, group "One instance only" (12) |
| Only a goal block takes a new subtask (not a task block, not a missing block, not an empty title) | "only a goal block takes a new subtask" |
| Duplicate does not copy the subtasks. Split keeps them on the first half | "duplicating a block does not copy its subtasks", "splitting a block keeps the subtasks on the first half" |
| Tick, rename and delete are one undo step each. A tick does not tick the block | `block_subtask_store_test.dart`, group "Tick, rename, delete, with undo" (11) |
| Deleting the block deletes its subtasks. Undo brings them back, with their ticks | "deleting the block and undoing brings the subtasks back", "deleting the block deletes its subtasks" |
| Deleting the goal keeps the subtasks on the plain block. They can be ticked, renamed and deleted. No new one can be added | "deleting the goal keeps the subtasks on the plain block", "an old goal block keeps its subtasks…" |
| The editor opens only for a goal block, or for an old goal block that still has subtasks. An import closes it | `block_subtask_store_test.dart`, group "The editor" (4) |
| The labels "+3 more", "1/4 subtasks" and "1/4" | `block_subtask_store_test.dart`, group "The labels" (2) |
| A version 6 database upgrades and keeps its data | "upgrading a version 6 database keeps its data", "the shared schema has the table and its index" |
| The export file has the table right after `events`, with the 7 Mac columns only. An older file still imports | `block_subtask_test.dart`, group "Export and import" (4) |
| A real Mac file (schema 7 and schema 6) imports and comes back with the same rows and columns | `data_export_test.dart`, "the file has the same rows and columns as a Mac export (schema 7)" and "(schema 6)" |
| Sync: the table has the sync columns; a database of an older build gets them at the next open, one time; rows that were there go in the outbox | `block_subtask_sync_test.dart`, group "The schema" (5) |
| Sync: every write is in the outbox, also the subtasks that go with a deleted block | `block_subtask_sync_test.dart`, group "What the outbox writes down" (3) |
| Sync: subtasks travel between two devices; delete block against tick or add; last write wins; an import replaces them | `block_subtask_sync_test.dart`, group "Two devices" (9) |
| Sync: 3 devices with random edits end the same | `block_subtask_sync_test.dart`, group "Many devices" (12 seeds) |

New tests by file: `app/test/data/block_subtask_test.dart` 20, `app/test/sync/block_subtask_sync_test.dart` 29, `app/test/state/block_subtask_store_test.dart` 28, `app/test/data/data_export_test.dart` 1 more (the schema 7 file).

Tests first: the three new test files were written before the code. The first run failed because `BlockSubtaskItem` and `Repos.blockSubtasks` did not exist.

## Older tests that changed

| Test | Change | Why |
|---|---|---|
| `database_test.dart` "the shared migrations match the Mac app" | 6 → 7 migrations, and the table list has `block_subtasks` | Migration 7 |
| `data_export_test.dart` "the file has the same rows and columns as a Mac export" | Runs for the schema 7 file and for the schema 6 file. Our file always says schema 7 | Migration 7 |
| `sync_engine_test.dart` `fill` | Adds a goal block with one subtask | "A second device gets every kind of row" needs a row in every synced table |
| `sync_engine_test.dart` "a delete travels, with everything that hung on the row" | Expects the events `Standup` and `Read`, and the subtask of `Read` | The new goal block has no task, so it must stay |

## Not in this step

- The rows inside a block, the menu lines and the subtask editor window. They are view code (Track B). The request is in `docs/tracks.md`.
- The remote table `block_subtasks` on Supabase. There is no remote schema in the repository yet (login step of F11).

## For the owner

- Swift PR #4 was merged into `feat/planner-subtasks`, not into `main`. PR #3 went to `main` 37 seconds before.
- So the Mac app on `main` has schema 6. It refuses an export file from this Flutter build ("from a newer Grove"). The other way works: Flutter reads a schema 6 file.
- To fix: open a pull request from `feat/planner-subtasks` into `main` and merge it. I did not open or merge one.
