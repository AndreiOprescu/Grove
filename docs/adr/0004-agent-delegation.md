# ADR 0004 · An agent does tasks for you, on your own Mac, and only drafts

Status: Proposed (2026-10-19; the owner said yes to it in the plan of 2026-10-19, the owner marks it Accepted)

Changed by [ADR 0008](0008-agent-folder-and-services.md) (2026-10-27): the agent now works in a folder of its own and may write files there, and it may read with any service the person turns on, not only Gmail. The parts below that say otherwise are history.

## Context
The owner wants to hand a Grove task to an AI agent. Tasks may need the agent to read email, write a document, or write an email or a text message.
The agent must be reliable and safe ("better safe than sorry").
It uses the owner's own Claude plan, not a paid API key.
Some people have no agent, so the feature is off at first.
The owner wants to delegate from any device, also the phone, and see the results on every device.

## Decision
- **Where it runs.** On a desktop that has Claude Code (the `claude` command) and is logged in with the person's own Claude plan. The Mac acts as the server: any device makes a job, the job syncs, and the desktop with "This device runs agent tasks" on runs it. One job at a time. A job stops after 30 minutes (it was 10 minutes at first; the Agents screen, ADR 0005, made it 30).
- **Read and draft only.** The agent can never send, never run commands, never write files. It returns structured JSON: a summary, its steps, an optional document, an optional email draft, an optional text draft, open questions and sources. Grove saves that as notes linked to the task. The person opens a draft in Mail or Messages (`mailto:`, `sms:`) and presses Send there.
- **Switches, all off at first, kept per device:** `agent.enabled` (show "Ask the agent…"), `agent.runner` (this desktop runs jobs), `agent.email` (this runner may read email). Email is read only when the job asks for it and the runner allows it.
- **Data.** A synced table `agent_jobs` holds the job, its status and the result. The result notes sync like every note. Raw emails are never stored; only the agent's summary and drafts are.
- **Mac sandbox off.** A sandboxed app cannot start `claude`. Grove leaves the sandbox. On the first start it copies (never moves) the old data from the sandbox folder. The database is copied by SQLite (`VACUUM INTO` a `.part` file, renamed last), so rows still in the WAL come too; a marker file `.sandbox-copied` says it is done. A new database with data of the person is never replaced; a new empty one is kept as `grove.sqlite.empty-<time>`.

## How Grove calls `claude` (spike of 2026-10-19, Claude Code 2.1.302)
- `claude -p` with the prompt on stdin, in a new empty temp folder, without a shell.
- Always: `--output-format stream-json --verbose --json-schema <schema> --no-session-persistence --permission-mode dontAsk --max-turns <n>`. It was `--output-format json` at first; since the Agents screen (ADR 0005) Grove reads the steps live from the stream, and the last line holds the answer. The answer is in the field `structured_output`; `is_error`, `subtype` and `permission_denials` tell how it went. `--max-turns` works, though `--help` does not list it.
- `--tools` lists the built-in tools that exist at all. Grove passes only `WebSearch` (and `WebFetch` when email is off). Bash, Write and Edit do not exist in the run, so no allow rule can turn them on.
- **Email off:** `--setting-sources "" --strict-mcp-config`. No connector, no hook and no allow rule of the person loads.
- **Email on:** the claude.ai connectors (Gmail) load only with the person's user settings (`--setting-sources user`). So:
  - First a probe: the same command with `--output-format stream-json --verbose --tools ""`. Grove reads the first line (the `init` event, with `tools` and `mcp_servers`) and stops the process before the model is called.
  - If any MCP server in the probe has a status other than `connected`, `needs-auth`, `failed` or `disabled` (for example `pending`), the job fails with: "The agent's connections were still starting. Try again in a minute." A server that is still starting could bring tools the probe did not see.
  - From the probe, Grove allows only Gmail tools whose names are read-only: the name is cut into words at `_`, `-` and capitals; every word must be on a list of read words (verbs such as search, get, read, list, fetch, find; nouns such as message, thread, email, attachment, id), and the first word (after "gmail") must be a read verb. A name with any other word is refused (`list_labels`, `get_and_mark_read`, `create_draft`). Every other connector tool from the probe is put on `--disallowedTools`. `dontAsk` refuses any tool that is not allowed.
  - Every MCP server of the probe other than Gmail is also denied as a whole: `mcp__` and its name, with each character other than a letter, a digit, `_` or `-` as `_` ("claude.ai Google Drive" gives `mcp__claude_ai_Google_Drive`). This also covers the person's own MCP servers and tools the probe did not list. The Gmail server is never denied as a whole: a deny beats an allow. Another server whose name gives the Gmail prefix makes Gmail "not ready".
  - `--strict-mcp-config` cannot be used with email: the lead tested on 2026-10-19 that `--setting-sources user --strict-mcp-config` loads no claude.ai connector. So the person's own MCP servers start in a run with email, and are denied by the server rule above.
  - A cancel or the time limit also stops the processes `claude` started (its MCP servers): Grove finds them with `pgrep -P`, sends SIGTERM, and SIGKILL after 3 seconds.
  - Hooks are turned off with `--settings '{"disableAllHooks":true}'`.
  - WebFetch is off, so an email that tells the agent to send data to a web address cannot.
  - If the probe finds no Gmail tool, or Gmail says `needs-auth`, the job fails with: "Connect Gmail in claude.ai → Settings → Connectors, then try again."
- On 2026-10-19 Gmail showed `needs-auth` in `claude -p`. So the Gmail tool names were not seen yet; the name rules above are the guard.

## Options
- A real server with a paid API key. Rejected for now: a cost per task, a new service, and the person's Google login on a server.
- Agent only on the device where the task is. Rejected: phones cannot run `claude`.
- The Mac acts as the server (chosen).
- Let the agent send after an OK in Grove. Rejected by the owner: a mistake leaves the computer and cannot be undone.

## Consequences
- Jobs wait while the runner desktop is off or Grove is closed. The task shows "Waiting for your Mac".
- The agent's summaries of emails sync to Supabase like other notes.
- Grove on the Mac can now reach more of the disk than in the sandbox.
- A document is a Grove note in v1. Files (PDF, Word) as attachments are for later.
- The owner must run the new Supabase SQL file once.
