# ADR 0002 · Goal blocks use goal subtasks only

Status: Proposed (2026-10-14; the owner said yes to it in the plan, the owner marks it Accepted)

## Context
A goal block could hold two kinds of steps: goal subtasks (from the goal's list) and block subtasks (only on that block).
The new goal panel shows a goal block's steps and lets the user add, tick and unplan them.
Two lists in one panel are confusing.

## Decision
- A goal block holds only goal subtasks. It has no block subtasks.
- One time, each block subtask on a goal block becomes a goal subtask of that goal. It keeps its id, title, done state and order.
- On a single goal block, it stays planned in the same block.
- On a repeating goal block, it goes to the goal's list and is not planned. A goal subtask can sit in one block only, and a series is many days.
- The old block subtask rows are then removed.
- Block subtasks stay for blocks that have no goal and no task.

## Options
- Keep both lists in the panel, with labels. Rejected: two lists for the same idea.
- Move them (chosen). No step is lost, and the panel has one list.

## Consequences
- The move cannot be undone in the app.
- The ids stay the same, so two synced devices that both run the move make the same rows, not copies.
