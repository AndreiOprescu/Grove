# Grove

Grove is a personal day planner. Tasks, goals and events go on a timeline, and finished work grows a garden.

## Language

### Goals

**Goal**:
Something the user works toward. A goal is either a habit or a project; the user picks one when making it.

**Habit**:
A goal the user puts time into each week, with a target in hours or in sessions. It never ends.

**Project**:
A goal that can finish. It has a goal map, and its finish line is its root square.
_Avoid_: Big goal, one-off goal

**Goal map**:
The connected squares of one project. Each project has exactly one.
_Avoid_: Tree, tree map, treemap (a square can have more than one parent)

**Square**:
One thing that must happen on a goal map. A square's children must be done before the square itself; one square can be a child of many.
_Avoid_: Node, card, goal subtask

**Root square**:
The square that stands for the project's result. Ticking it finishes the project.

**Loose square**:
A square with no line to the root square, so it does not hold up the finish. It waits for the user to link it.
_Avoid_: Orphan, unlinked node

**Length**:
How long a square or a goal subtask takes. When it is planned, its goal block is exactly that long.
_Avoid_: Estimate, duration (estimate is for tasks)

**Ready square**:
A square whose children are all done, or that has no children. A square that is not ready looks dim, but the user can still plan it and tick it.
_Avoid_: Unlocked, locked

**Wait**:
A length of time on a square for something the user does not control, such as a reply. It starts when the user presses "Start waiting"; only the user's tick ends the square, even when the time runs out.
_Avoid_: Delay, timer

**Goal block**:
A slot of time on the planner set aside for one goal.
_Avoid_: Goal instance, goal session

**Goal subtask**:
A step that belongs to a habit and lives in that habit's own list. A project has squares instead. It is **planned** when it sits in a goal block of the same goal; a goal block holds at most one.
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

### Text editor

**Rich text box**:
Any place where the user writes formatted text: a note, a task's notes or an event's notes. All of them look and work the same.
_Avoid_: Markdown editor, note editor (when the task and event boxes are meant too)

**Format**:
A look the user gives to text: bold, italic, underline, strike, highlight, code, a heading (a text size), a list, a quote, a link, a divider. The user sets it with the toolbar, a key, or by typing or pasting marks.
_Avoid_: Markup, styling

**Mark**:
A sign in the saved text that gives a format, such as `**` for bold or `# ` for a heading. Marks are hidden on screen; the "Show marks" setting shows them dim.
_Avoid_: Markdown command, syntax, markup

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

### Sleep

**Night**:
The time from one evening to the next morning. It is named by the date of its evening, so the night of Friday ends on Saturday morning.

**Fell asleep / Woke**:
The start and the end of the night's no-use gap. Grove learns them from the devices; they are a guess, not a measurement.
_Avoid_: Sleep line, wake-up line (those are the lines the user puts on the planner; detection never moves them)

**No-use gap**:
The longest time in a night when no device of the user was in use. It must last at least 3 hours and start in the evening or early night.
_Avoid_: Sleep session

**Brief use**:
A use of a device that lasts less than 3 minutes, such as a look at the time. It does not end a no-use gap.

**Usual bedtime**:
The time the user usually falls asleep on a given night, worked out from earlier nights of the same weekday, then from all recent nights, then from the sleep line.
_Avoid_: Bedtime goal, target bedtime

**Usual sleep length**:
How long the user usually sleeps, worked out the same way. With the phone's next alarm it can make the usual bedtime earlier.

**Bedtime reminder**:
The notification that asks the user to plan tomorrow, a lead time (1, 1½ or 2 hours) before the usual bedtime.
_Avoid_: Sleep reminder, evening nudge
