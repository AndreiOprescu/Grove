# An agent that does tasks for you

*2026-10-19*

Some tasks are mostly reading and writing. "Reply to Ana's email." "Write a one-page plan for the trip." "Text Mum that I'll be late."
Now you can hand tasks like these to an AI agent, right from Grove.

## What you can do
Right-click a task and pick **Ask the agent…**. Add a few words if you like, and press **Start**.
The agent can:

- **write a document**. It comes back as a Grove note, linked to the task;
- **read your email**, only if you allow it, and read-only;
- **draft an email** (to, subject, text);
- **draft a text message**.

When it is done, the task gets a result note: a summary, the steps it took, the drafts, and any questions it has for you.
Press **Open in Mail** or **Open in Messages**. The draft is filled in. You read it, and you press Send.

## Safe first
We built it to be safe before it is clever:

- **It never sends anything.** It only drafts. You always press Send yourself.
- **It cannot run commands or change files** on your computer. Those tools are not there at all.
- **Email is off at first.** It needs two yeses: one for the task, and one in Settings on the computer that runs the agent.
- When it reads email, it **cannot open web pages**. So an email that tries to trick it cannot send your data anywhere.
- Your emails are not saved in Grove. Only the agent's summary and drafts are.
- A job stops by itself after 10 minutes. You can cancel it at any time, from any device.

## How it works
The agent is [Claude Code](https://claude.com/claude-code), on your own Mac or Windows PC, with your own Claude plan. No extra cost and no new account in Grove.
That computer acts as the server. You can ask from any device, also your phone. The job syncs to the computer, the computer runs it, and the results sync back to all your devices.

To make this possible, Grove for Mac now runs outside the macOS sandbox. The first time the new version starts, it copies your data to its new folder. The old folder stays as a backup.

## Try it
1. Install Claude Code and log in with your Claude plan.
2. In Grove, open **Settings ▸ Agent**. Turn on **Use the agent** and **This device runs agent tasks**.
3. For email: connect Gmail in claude.ai ▸ Settings ▸ Connectors, then turn on **Let the agent read my email**.
4. Right-click a task, pick **Ask the agent…**, and press Start.

No Claude Code? Leave the switches off. The rest of Grove works the same.

## Not done yet
- Documents are notes for now. Files such as PDF or Word come later.
- The jobs wait while your computer is off or Grove is closed.
- Only Gmail for now.

The details of the design are in [ADR 0004](../adr/0004-agent-delegation.md).
