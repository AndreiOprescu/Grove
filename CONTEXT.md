# Grove

Grove is a personal day planner. Tasks, goals and events go on a timeline, and finished work grows a garden.

## Language

### Goals

**Goal**:
Something the user wants to put time into each week, with a target in hours or in sessions.

**Goal block**:
A slot of time on the planner set aside for one goal.
_Avoid_: Goal instance, goal session

**Goal subtask**:
A step that belongs to a goal and lives in that goal's own list. It is **planned** when it sits in one goal block of the same goal; a goal block can hold many.
_Avoid_: Goal step

**Block subtask**:
A step that belongs to one block only. Goal blocks do not have them; their steps are goal subtasks.

**Unplan**:
To take a planned goal subtask out of its goal block. The subtask stays in the goal's list.
_Avoid_: Remove, unschedule (unschedule is for task blocks)

### Planner

**Goal panel**:
The panel on the right that shows a goal block's details when the user taps that block.
_Avoid_: Goal inspector, goal sheet

**Task panel**:
The panel on the right that shows a task's details when the user taps that task or its block.
_Avoid_: Task inspector

### Persona

**Persona**:
The drawn person on the Persona screen who stands for the user. It has a name and a level.
_Avoid_: Avatar, character

**Skill**:
One area the persona grows in, such as Strength or Mind, with its own bar and level. A skill can be renamed or hidden, but never deleted.
_Avoid_: Stat, attribute

**Skill points**:
The number a skill collects.
_Avoid_: XP, experience

**Level**:
The step a skill, or the persona as a whole, has reached. Each new level needs a few more skill points than the one before.

**Reward**:
The setting on a task or a goal that says which skills get how many skill points. For a goal the points are per hour of a goal block.
_Avoid_: Bounty, prize

**Earning**:
One log line of skill points paid to a skill when a task or a goal block is ticked done. Un-ticking takes it away. A later change to the reward does not change it.
_Avoid_: Gain, transaction

**Your days**:
The 3 bars on the Persona screen that count the good, okay and rough days of this month or of all time. They come from the mood of each daily note.
_Avoid_: Mood stats, day score
