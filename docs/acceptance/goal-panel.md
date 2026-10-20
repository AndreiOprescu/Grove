# The goal panel — proof

Branch `feat/xp-goal-panel`, into `feat/cross-platform-flutter`. Flutter app only: nothing in `Sources/` or `Tests/` (the Swift Mac app) changed. No new package. No change to the Supabase SQL.
The owner's words: "I want to make goal instances clickable on the planner tab. It should act kind of like a task, so it should make a tab pop up from the right with info and stuff on it. On the goals tab on the left, I want to be able to choose subtasks that I want to bring onto the planner to do at a specific time. I should be able to remove subtasks from the planner that I dont want to do anymore."
The owner's choices (2026-10-14) are below. The owner said yes to the plan and to ADR 0002 (`docs/adr/0002-goal-blocks-use-goal-subtasks.md`). Words: `CONTEXT.md`.
Check: `./scripts/flutter_test.sh` (2026-10-14: 2801 tests passed, analyze clean, format clean). The base had 2756. The two new test files have 44 tests, and one old test became two.

## What was built

| Part | File |
|---|---|
| The goal panel: goal name and colour, "Edit goal", close, day and time of the block, the week of the goal, "In this block", "Add a subtask", "Add from goal", linked note, "Mark done", "Delete goal block" | `app/lib/ui/goals/goal_panel.dart` (new) |
| The panel at the right (desktop), over the screen (phone), in the place of the note (Today) | `app/lib/ui/tasks/store_panes.dart` (`selectedPanel`), `app/lib/ui/spread/day_spread_view.dart` |
| Escape closes the panel | `app/lib/ui/store_app.dart`, and the panel itself |
| The store: which goal block is open, open, close, "Edit goal", a drop on empty time, a new subtask in the block, the one-time move of old block subtasks | `app/lib/state/store_goal_panel.dart` (new), `app/lib/state/app_store.dart`, `app/lib/state/store_sync.dart` |
| A tap on a goal block opens the panel | `app/lib/state/store_planner.dart` (`selectBlock`) |
| "+" and a drop work on a day of a repeating block (the day becomes its own block); a refused drop says why | `app/lib/state/store_goal_subtasks.dart` |
| The old block subtasks of goal blocks | `app/lib/data/repos.dart` (`BlockSubtaskRepo.onGoalBlocks`) |
| The grid: right-click "Subtasks…" opens the panel, a drop on empty time, a drop on every block | `app/lib/ui/planner/planner_grid.dart` |
| "Edit goal" opens the goal editor in the Goals panel | `app/lib/ui/goals/goals_pane.dart` |
| The rows of a subtask, shared by the panel and the old window | `app/lib/ui/planner/subtask_lines.dart` (new), `app/lib/ui/planner/block_subtask_editor.dart` |

## Proof for each choice of the owner

Store tests: `app/test/state/goal_panel_store_test.dart` (26). Screen tests: `app/test/ui/goals/goal_panel_test.dart` (18).

| Owner's choice | Proof |
|---|---|
| One tap on a goal block opens a panel at the right, the same place and width as the task panel | Screen: "a tap on a goal block opens the goal panel at the right…", "a tap on a task block shows the task panel in its place", "a tap on another goal block shows that block". Store: "a tap on a goal block opens the goal panel…", "the goal panel and the task panel are never open at once". |
| On a phone it covers the screen | Screen: "on a phone the panel takes the place of the planner". |
| The panel shows goal name and colour, block time, progress this week, "In this block", "Add from goal", linked note, "Mark done", "Delete goal block" | Screen: "a tap on a goal block opens…" (name, time, progress), ""In this block" shows the planned ones, "Add from goal" the open ones…", "the linked note row makes a note of the block", ""Mark done" ticks the block…", ""Delete goal block" deletes the block and closes the panel…". |
| Goal subtasks live on the goal | Store: "a new subtask from the panel goes in the goal and in this block". Screen: "the add field makes a subtask of the goal, planned in the block…". |
| A drop of a subtask on empty time makes a new 1-hour goal block that holds it | Store group "A subtask dropped on empty time" (3). Screen (`app/test/ui/goals/goal_subtasks_test.dart`): "a drop on empty time makes a block of the goal, one hour long, that holds the subtask". |
| "Remove from planner" = unplan: back to the goal list, still open. Delete only in the Goals panel | Store: "unplan sends it back to the goal, still open. The block stays". Screen: ""Remove from the planner" takes the subtask out of the block…". The panel has no bin. |
| Old block subtasks on goal blocks move into the goal, one time, with the same ids | Store group "Old block subtasks of goal blocks move into the goal" (7, also at import and from another device). |
| Repeating block: split that day off | Store: "a day of a repeating goal block becomes its own block…", "a new subtask on a day of a repeating block splits that day off". Screen: "a day of a repeating goal block becomes its own block when it takes a subtask…". |
| The goal is read-only in the panel; "Edit goal" opens the goal editor in the Goals panel | Store: ""Edit goal" closes the panel, shows the Goals panel…". Screen: ""Edit goal" closes the panel and opens the editor of the goal in the Goals panel". |
| An empty block stays after the last unplan | Store: "unplan sends it back to the goal, still open. The block stays". Screen: ""Remove from the planner"…" checks the block is still there. |
| Old subtasks on a repeating goal block go to the goal list, not planned | Store: "on a repeating block they go to the goal and are not planned". |
| All subtasks ticked: no auto-done | Store: "all subtasks ticked does not mark the block done". Screen: "a tick marks the subtask done. It stays in the block". |
| "Add from goal" shows only unplanned open ones | Screen: ""In this block" shows the planned ones, "Add from goal" the open ones that are in no block" (a done one is not offered). |

## Changed tests

- `app/test/ui/goals/goal_subtasks_test.dart`: the old test "a drop on … an empty place does nothing" is now two tests. A drop on a block of another goal or on a task block does nothing and shows "Chapter 1 can go only in a block of Read.". A drop on empty time makes a block. The task block in that test moved from 16:00 to 15:00: at 16:00 it was below the window, so the old test dropped on nothing and passed by luck.
- `app/test/ui/planner/planner_subtasks_test.dart`: "Add Subtasks…" and "Subtasks…" on a goal block now open the goal panel, not the old window.
- `app/test/ui/planner/planner_menu_test.dart`: "a double click on a goal block opens its title" clicks the block where it is after the first click, as the task block test does: the panel opens at the first click, so the block moves.

## Not built

- The old window (`BlockSubtaskEditor`) stays for a plain block that still has block subtasks (a block whose goal was deleted). Its code for goal subtasks (planned rows, "From the goal") is now not reached from a goal block. A later change can remove it.
- `store.addBlockSubtask` and `store.openBlockSubtasks` still accept a goal block. Nothing on the screen calls them for one. A block subtask made that way moves into the goal at the next start, pull or import.

## Not verified

- On a real phone and on Windows. The screen tests run at phone size and at desktop size.
- `test/state/planner_store_test.dart` "one undo brings back the old block and the old plan date" failed one time in a full run, then passed alone 3 times and in the next full run. The two blocks it compares print the same. It looks like a timing flake. This branch does not change that code.

## For the owner

1. Open the Planner. Click a goal block. The goal panel opens at the right.
2. Drag a subtask from the Goals panel to empty time. A 1-hour block of the goal holds it.
3. In the panel, use the arrow on a subtask to take it off the planner. It goes back to the goal.
