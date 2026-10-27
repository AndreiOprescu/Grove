# The agent gets a desk, and reads with your services

*2026-10-27*

Until now the agent could only read and write a note back. It could not save a file, and the only service it could read was Gmail.
Now each chat gives the agent a folder of its own, and you pick which of your services it may read.

## What you can do
- **Let the agent save its work.** Each chat has its own folder on the computer that runs the agent. The agent can save files there: a plan, a list, a draft page. The chat shows **Files the agent saved**. Click a text file to open it. Any other file shows in Finder, so Grove never runs it.
- **Pick your services.** Open **Settings ▸ Agent ▸ Services the agent may read** and press **Refresh**. Grove lists the services of your Claude Code: Gmail, Google Drive, Notion and more. Turn on the ones the agent may read. Each line shows what it may use, like "Connected · reads with: search_threads".
- **Turn them on per chat.** The **Services** switch of a chat (it was "Email") lets that chat use them. In the task window it is "Let the agent use my services for this task".
- **Clean up.** **Settings ▸ Agent ▸ Agent folder** shows where the folders are. **Show in Finder** opens it, and **Delete agent files** removes them all, after a question.

## Safe first
- The agent **can only change files in the folder of its chat**. A write anywhere else is refused by Claude Code itself.
- It **never runs commands**, and it **never sends**. You still press Send yourself.
- It gets **only the tools that read** of a service: search, get, list, read. A tool that sends, drafts, moves or deletes is blocked. A tool name Grove is not sure of is blocked too.
- In a chat with services, the agent **cannot open web pages**, so a text it reads cannot make it send your data to a web address.
- A linked file is **copied** into the folder. Your file is never changed.
- If your Claude Code settings would let the agent reach more (for example a rule that allows all file reads), Grove says so and does not start the run.

## Try it
1. Update Grove on the computer that runs the agent. No SQL this time.
2. Open **Settings ▸ Agent**, press **Refresh**, and turn on a service.
3. On the **Agents** screen, turn on **Services**, and ask: "Find the emails about my trip and save a packing list."
4. Click the file it saved.

If you had "Let the agent read my email" on, Gmail is turned on for you.

## Not done yet
- Deleting one chat does not exist yet, so its folder stays until you press **Delete agent files**.
- A phone shows the names of the files, not the files. Open them on the computer.
- In a chat with services the agent can still search the web. What it reads could change what it searches for. The owner decides if that stays (question Q-58).

The details of the design are in [ADR 0008](../adr/0008-agent-folder-and-services.md).
