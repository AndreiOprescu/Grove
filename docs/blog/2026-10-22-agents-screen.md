# A home for your agents

*2026-10-22*

Last week the agent learned to do tasks for you. But you could not see it work. You waited, and a note came back.
Now the agent has its own screen: **Agents**. You see what each agent does, step by step, while it works.

## What you can do
Open **Agents**, next to Persona. It looks like a chat:

- **Write what you want** in the big box, and press Send. A task is not needed.
- **Link things with "+"**: a note, a task, or a file (PDF, Word, text) from your computer.
- **Pick a helper** to start fast:
  - **Fix my day**: you fell behind, and it proposes a new plan for the rest of the day.
  - **Split a big task** into small steps.
  - **Get a task ready**: it finds what you need before you start.
  - **Find tasks in a document**: link a file, and it lists the tasks in it.
  - **Watch my deadlines**: it tells you what is at risk.
  - **Weekly review**: what went well, and what to plan next.
- **Watch it work.** Each step shows live: what it reads, what it searches, what it thinks. The phone sees the steps of a job that runs on the Mac.
- **Answer its questions.** When it needs you, the job moves to **Needs you**. Write a reply, and it goes on.
- **Apply its ideas.** With **Plan** on, it can see your next days. It proposes changes and new tasks. Each one has an **Apply** button. Nothing changes until you press it, and Undo takes it back.
- **Queue many jobs.** They run one after the other, in the background, until all are done.

## Safe first
- It still **only reads and drafts**. It never sends, and it never changes your plan by itself.
- Each chat says what the agent may do: "Reads and drafts only · Plan off · Email off · Stops after 30 min".
- **Stop** works at any time, from any device.
- A job stops by itself after 30 minutes.
- **Files stay on your computer.** Grove copies a linked file into its own folder. It never uploads it. When the agent reads a file, it cannot open web pages.

## Try it
1. Ask the owner of your Grove sync to run the new SQL file once (see below).
2. Update Grove on all your devices.
3. Turn on **Settings ▸ Agent ▸ Use the agent**. The **Agents** tab shows up.
4. Pick **Weekly review**, and press Send.

For the owner: run `supabase/migrations/20261022000000_grove_sync_agent_chat.sql` once in Supabase.

## Not done yet
- Files can be linked only on the computer that runs the agent. On the phone, link notes and tasks.
- Jobs wait while that computer is off or Grove is closed.

The details of the design are in [ADR 0005](../adr/0005-agents-screen.md).
