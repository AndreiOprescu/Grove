# ADR 0003 · Skill points are a log of earnings

Status: Proposed (2026-10-15; the owner said yes to it in the plan, the owner marks it Accepted)

## Context
The Persona screen shows skill points. Points come from tasks and goal blocks that are ticked done.
The owner can change a reward later, delete a done task, or change the length of a done goal block.
The points must not jump when that happens. They must sync between devices without copies.

## Decision
- Each tick that pays points writes one **earning** row per skill: the skill, the points, the task or goal block, its title and the time.
- The points of a skill are the sum of its earnings. They are never stored, and never worked out again from the tasks.
- Un-ticking deletes the earnings of that task or goal block. Deleting a done task keeps them.
- A goal pays per hour of the goal block, pro rata, rounded to a whole number, at the moment of the tick.
- Ids are fixed: `r:task:<task>:<skill>`, `r:goal:<goal>:<skill>` for rewards and `e:<kind>:<source>:<skill>` for earnings. Two devices that tick the same task make the same row, not two.
- The 8 built-in skills have fixed ids (`skill-strength` …) and are on every device from the start. They are never in the outbox until the user changes one, so a new device never overwrites a rename from another device. "Use the data of the account" and an import put any missing built-in skill back.

## Options
- Work out the points from the done tasks and blocks each time. Rejected: a changed reward or a deleted task would change old points.
- Keep one points number per skill. Rejected: un-tick and sync from two devices would race.
- A log of earnings (chosen).

## Consequences
- Old points stay as they were paid, also when the reward changes.
- The `earnings` table grows by one row per skill per tick. That is small for one person.
- Skills are never deleted (only hidden), so no earning loses its skill.
