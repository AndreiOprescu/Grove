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
