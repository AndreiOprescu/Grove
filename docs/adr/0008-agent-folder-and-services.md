# ADR 0008 · The agent works in a folder of its own, and reads with the services you turn on

Status: Proposed (2026-10-27; the owner said yes to it in the plan of 2026-10-27, the owner marks it Accepted)

## Context
The owner wants two things (2026-10-27):
- The agent must never change files outside a folder that Grove owns.
- The agent should use the owner's own services (the MCP servers of Claude Code, like Gmail, Google Drive or Notion) and the normal file tools, so the work is ready before a task starts.

The owner's answers: services are **read only**, and the agent **never runs commands** (no Bash, no PowerShell).

Until now (ADR 0004, ADR 0005) the agent had no file tools, ran in a temp folder that was deleted, and could only use Gmail.

## Decision

### The folder
- Each chat has its own folder: `<data folder>/Agent workspace/<chat id>/`. Only a uuid is a chat id, so an id can never point somewhere else (`AgentScope.folder`). A job with another id runs in a new temp folder, as before.
- `claude` runs in that folder. The folder stays after the run, so the person can open what the agent saved.
- A file the person linked is copied into `inputs/` of the folder, again before each run. The original is never touched.
- Before and after each run Grove checks the folder (`AgentScope.audit`):
  - it removes links, odd entries, and every file Claude Code would load as settings (`.mcp.json`, `.claude/`, `CLAUDE.md`, `CLAUDE.local.md`, in any case), so a run cannot plant a tool or a rule for the next run;
  - a folder with more than 500 files or 200 MB fails the job with a message.
- The run gets only these names of the environment: `HOME USER LOGNAME PATH LANG TMPDIR SHELL` (on Windows: `USERPROFILE APPDATA LOCALAPPDATA SystemRoot TEMP TMP HOMEDRIVE HOMEPATH USERNAME PATH`). No API key goes in, so `claude` stays on the person's Claude plan. It also always gets `MCP_CONNECTION_NONBLOCKING=false`: `claude -p` starts the MCP servers in the background, and without it the probe often found none (live check). And `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`: no memory of Claude Code in any run (see "With services"). The output is cut at 20 MB.
- The result line of a run lists the files the agent saved (`grove_files` in the JSON of the line, no SQL), so a phone can show their names.
- Grove opens only plain text files of the agent (`md`, `markdown`, `txt`, `json`). Any other file, like a web page, a script or a table, is never run by Grove: the folder of the chat shows in Finder or Explorer. Grove never shows a folder the agent named, because the Mac opens a folder like `x.app` or `x.prefPane` as a program; the openers refuse a folder with a dot in its name too.
- Settings → Agent shows the folder, "Show in Finder" and "Delete agent files" (with a question first; refused while a job runs).

### Two ways to run (live check, Claude Code 2.1.309, 2026-10-27)
Both ways always pass `-p --output-format stream-json --verbose --json-schema <schema> --no-session-persistence --permission-mode dontAsk --max-turns 60`. `dontAsk` refuses every tool that is not allowed.

**Locked (no services).** `--restricted --strict-mcp-config`.
- `--restricted` turns off command tools, keeps the file tools inside the working folder, ignores the settings and hooks of the person and of the folder, and loads no MCP server at all (not even the claude.ai connectors).
- `--tools Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,TodoWrite`.
- `--allowedTools Read(./**),Write(./**),Edit(./**),WebSearch,WebFetch,TodoWrite`.
- With a linked file WebFetch is left out, so a file cannot make the agent send data to a web address.
- Checked live: a write in the folder works; a write to `~/x` and a read of `~/.zshrc` are refused.

**With services.** The connectors load only with the user settings, so:
- `--setting-sources user --settings {"disableAllHooks":true,"autoMemoryEnabled":false}`: the user settings of the person, without their hooks and without the memory of Claude Code; never the settings of a project folder.
- `--tools Read,Write,Edit,Glob,Grep,WebSearch,TodoWrite`: no WebFetch, so a text the agent reads cannot make it send data to a web address.
- `--allowedTools` = `Read(./**)`, `Write(./**)`, `Edit(./**)`, `WebSearch`, `TodoWrite`, and the exact names of the read tools of the services that are on and ready.
- `--disallowedTools` = every other tool of those services, every server that is off or not ready as a whole (`mcp__<name>`, which also covers tools the probe did not list and the person's own stdio servers), every `mcp__` tool of no server, and `Write(~/.claude/**)`, `Edit(~/.claude/**)`. A deny beats an allow.
- **The memory of Claude Code.** Without `--restricted`, claude 2.1.309 allows writes to its own memory files before any rule of Grove: `.md` files in `~/.claude/projects/<folder>/memory/` (or the folder `autoMemoryDirectory` names) and in `~/.claude/agent-memory/`. That check does not look at whether memory is on. `MEMORY.md` would then load into the next run of the chat, so a text the agent reads could plant rules for later runs (review, 2026-10-27). So a run with services turns memory off (`--settings` and the env), denies `~/.claude/**` for Write and Edit, and the settings guard refuses `autoMemoryDirectory`. A locked run is safe: `--restricted` turns these allows off.
- Checked live (2026-10-27, services on with Context7): the agent was asked to write `~/.claude/projects/<folder>/memory/grove-escape.md` and `~/.claude/agent-memory/grove-escape/grove-escape.md` with the Write tool. Both were refused ("denied by your permission settings") and no file was made; a write to `./inside.md` worked.
- **Glob and Grep are never allowed by name.** The live check showed that a bare `Glob` or `Grep` in `--allowedTools` lets them look outside the folder. In the folder they work without a rule.
- Checked live: a write, a read, a Glob and a Grep outside the folder are refused. With Context7 on, its read tool `query-docs` ran and its other tool `resolve-library-id` was not even offered to the agent.
- **The settings guard.** This way loads the person's user settings, so an allow rule there could reach more. Before each run Grove reads `~/.claude/settings.json`, `~/.claude/settings.local.json` and the admin file (`managed-settings.json`). The run is refused with a plain message when one allows a file tool (Read, Write, Edit, MultiEdit, Glob, Grep, NotebookEdit, NotebookRead, LS), a whole MCP server, an MCP tool that is not a read tool (a tool the probe did not list would not be denied in the run) or a `*` rule, adds folders (`additionalDirectories`), moves the memory folder (`autoMemoryDirectory`), or turns on the MCP servers of a project folder (`enableAllProjectMcpServers`, `enabledMcpjsonServers`). A file Grove cannot read as settings is refused too (`AgentScope.settingsProblem`, pure Dart; the runner reads the files).

### Services
- **Finding them.** A probe runs `claude -p` with `--tools ""`, the user settings and hooks off, and reads the `init` event: `mcp_servers` (name, status) and `tools` (`mcp__<server>__<tool>`). Grove stops the probe there. The list is kept in the device prefs (`agent.services`) and Settings has a Refresh button. Each run probes again first and uses that fresh list.
- **A server that is still starting** (a status other than connected, needs-auth, failed or disabled) fails the job: "The agent's connections were still starting. Try again in a minute."
- **Read tools** (`McpToolRules.isReadTool`). The name of the tool is cut into words at `_`, `-` and capitals. The first word, after the words of the server name, must be a read verb (get, list, search, find, query, read, fetch, describe, view, lookup, count), with at least one word after it: a bare `query` of a database server runs any SQL, and a bare `fetch` may reach any web address (review, 2026-10-27). No word may name a web address or SQL (`url`, `http`, `sql`, in any form), so `fetch_url` cannot work as the WebFetch a run with services leaves out. No word may be a write word in any form ("send", "sends", "sending"; also create, update, delete, draft, label, mark, run, exec and many more), and no word may join two actions (and, then). A name Grove is not sure of is not a read tool.
- **Two servers whose names give the same rule** (for example "a.b" and "a_b") are never usable: Grove cannot tell their tools apart.
- **Switches.** Settings → Agent → "Services the agent may read" has one switch per server, off at first, kept per device (`agent.servicesOn`). Each line shows the status, or the read tools it allows. The old switch `agent.email = true` turns on "claude.ai Gmail" once, then it is removed.
- **Per chat.** The old "Email" switch of a chat becomes "Services" ("Let the agent use my services for this task" in the task window). It reuses the column `email_access`, so no SQL. A chat runs with services only when it asks for them and this computer has a service on. Otherwise it runs locked, and when it asked for services the result gets a question that says they were off.
- When the chat asks for services but none that is on is connected with a read tool, the job fails with a plain message.

## Options
- Keep the agent without file tools. Rejected: the owner wants work saved before a task starts.
- One `--restricted` run with services. Not possible: the live check showed that `--restricted` loads no MCP server.
- Allow every tool of a service and trust the model. Rejected: the owner wants read only, and a text the agent reads could ask it to send.
- A list of read tools per service, made by hand. Rejected for now: each new service would need a Grove update. The name rule refuses what it does not know.

## Consequences
- The agent can now leave files on the computer, only in `Agent workspace`. "Delete agent files" removes them all. Deleting one chat does not exist yet, so its folder stays.
- A run with services starts the person's own MCP servers (they are denied, but they run while the job runs). A cancel or the time limit stops them (ADR 0004).
- **Left risk:** in a run with services the agent still has WebSearch. A text it reads (an email) could steer what it searches for, and a search query leaves the computer. WebFetch is off, so it cannot send a page of data to an address. Card Q-58 asks the owner.
- **Left risk:** the read-tool rule trusts the names the servers give their tools. A server that names a write tool `get_x` would get it allowed. Only turn on services you trust.
- Settings rules of the person that reach too far block runs with services until the person changes them, or turns services off for that chat.
- ADR 0004 is changed by this ADR: the agent may now write files, in its folder only, and may use other services than Gmail.
