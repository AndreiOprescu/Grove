# ADR 0008 · A goal is a habit or a project, and a project has a goal map of squares

Status: Proposed (2026-11-05; the owner marks it Accepted)

## Context
A goal was a weekly target with one flat list of subtasks. It could not show "I need to do other things first", and it could not show a wait for a reply. It also never ended.
The owner wants a goal that can finish, with a short description and a map, on its own screen.

## Decision
- **Two kinds.** `goals.type` is `habit` or `project`; `goals.kind` (hours or sessions) was already taken. All old goals are habits. A null type reads as habit, because rows on the server from before this have none.
- **Squares are not goal subtasks.** New tables: `goal_squares`, `square_links` and `square_blocks`. Habits keep goal subtasks. "Make it a Project" turns a habit's subtasks into squares, one way.
- **The map is a graph, not a tree.** A square can have many parents, so a link table holds them. The owner chose this over a strict tree: one step can be needed by two others.
- **One square, many blocks.** A report can take many sessions, and a block can hold many squares. So `square_blocks` is a link table, not a column like `goal_subtasks.event_id`.
- **Stable ids.** The root square is `root:<goalId>`, and a converted subtask is `sq:<subtaskId>`, so two devices that convert the same goal reach the same rows.
- **Finished is worked out.** A project is finished when its root square has `done_at`. There is no extra column to disagree with it.
- **Sync can break the graph; the rules cannot.** Each device is right alone, but a merge can make a loop or leave a square with no parent. `GoalGraph` ignores bad links, drops the link that closes a loop and joins a lost square to the root. A pull never writes repairs. The next edit on that map does.
- **Grove places the squares.** No positions are stored, so no device can disagree about them. The layout is our own code, in layers from the root; there is no new package.

## Consequences
- The owner runs the new SQL once, at the release. A schema mismatch stops sync.
- An older Grove shows a project as a goal with no target. It does not see the squares.
- The goal rule "never marked done" (PLAN §5.9) now holds only for habits.
