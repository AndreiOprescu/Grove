# ADR 0005 · An Agents screen: chats with the agent, live steps, linked documents, proposals

Status: Proposed (2026-10-22; the owner said yes to it in the plan of 2026-10-22, the owner marks it Accepted)

## Context
ADR 0004 gave Grove an agent that reads a task and writes drafts. A job started from a task, and its result was a note.
The owner wants more:

- **Transparency:** see the plan, the steps, the sources and the tools of each job.
- **Visibility:** see the progress live, on any device, at any time.
- **Autonomy:** a job works in the background until it is done. It can ask a question, and go on when it gets the answer.
- **Guardrails:** the agent stays safe.
- **One place:** a screen that shows what each agent does. The look is like the home page of claude.ai: a list of chats on the left, a greeting and a big box to write in, and "+" to link documents.

## Decision
- **An Agents screen**, after Persona in the screen switch. It shows only while "Use the agent" is on (`agent.enabled`); the switch and the command palette leave it out when it is off.
  - Wide window: the list of jobs on the left (search, "+ New", and the sections Running, Needs you, Done, Stopped), the chat on the right.
  - Phone: the home with the list under it, or one chat with Back.
  - The home: a greeting, the composer, and six helpers (Fix my day, Split a big task, Get a task ready, Find tasks in a document, Watch my deadlines, Weekly review). A helper fills the box and sets the switches; the person still presses Send.
- **A chat does not need a task.** `agent_jobs` gets `title`, `plan_access` and `links_json`. A reply in a finished chat makes the next job of the same chat; the run gets the chat so far.
- **Live steps.** Each line the agent writes while it works becomes a row in a new table `agent_events` (job, line number, kind, text, label). The rows sync, so the phone sees the steps of a run on the Mac. The order column is `line_no`, because `seq` is a name the remote uses.
  - The screen groups the tool steps and shows the last 3; a toggle shows all.
  - A device that does not run jobs asks for a sync every 10 seconds while the screen shows a job that is not finished.
- **Linked things, with "+".**
  - Notes and tasks: from any device. The agent gets their text, and nothing else of the notes and tasks.
  - Files: only on a desktop that runs jobs. Grove copies the file to `<data folder>/Agent files/<id>/<name>`. The file is never synced or uploaded. Other devices see only its name.
  - For a run, the files are copied to the empty temp folder of the run. The agent gets the `Read` tool for that folder only. A run with files has no `WebFetch`, so a file cannot send data to a web page.
- **The plan switch** (per job, off at first). When on, the agent gets the next days, the deadlines and the open tasks. It can only propose: plan changes (move or add a block) and new tasks. Each proposal shows an **Apply** button. Apply makes the change as one undo step. The applied keys are kept in the event's `label`, so the button shows "Applied" on every device.
- **Guardrails, on top of ADR 0004:**
  - Still read and draft only. Nothing changes in Grove until the person presses Apply.
  - A run stops after 30 minutes (was 10) and after 60 turns.
  - A run keeps at most 300 steps.
  - Stop works from any device, at any time.
  - Many jobs can wait in the queue. The runner does one at a time.
  - The rules line of each chat says what the job may do: "Reads and drafts only · Plan on/off · Email on/off · Stops after 30 min".
- **One SQL file** that the owner runs once: `supabase/migrations/20261022000000_grove_sync_agent_chat.sql` (local schema 13, sync 7).

## Options
- **A: a full screen with chats, live steps and proposals** (chosen). It meets all four needs. It costs one table and one SQL file.
- **B: keep the result note of ADR 0004 and add a progress line to the dialog.** Cheap, but no live steps on the phone, no chats without a task, and no linked files.
- **Files on every device, through Supabase Storage.** Not now. It uploads private files and costs storage. The owner picked "Mac only, for now".
- **Let the agent change the plan itself.** No. A wrong change is hard to see. Proposals with Apply keep the person in control.

## Consequences
- Every device needs the new version and the SQL file. Without the SQL file, sync of the new columns and of `agent_events` fails.
- A file linked on the Mac cannot be read by a run on another computer. The agent is told the name, and says so if it needs it.
- Undo of an applied change takes the change away, but the button still says "Applied". The person can apply it again only by hand.
- The steps make more rows to sync. The 300-step limit keeps a run small.
- The tab is hidden for people without the agent, so their Grove looks the same as before.
