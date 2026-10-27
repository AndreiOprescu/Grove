# Progress: agent folder and services (branch feat/agent-scope-tools)

Plan: `/Users/andrei/.claude/plans/you-are-on-ultracode-vast-petal.md` (PR A part).
Owner answers 2026-10-27: services read only; no commands (no Bash); agents may not change files outside a folder Grove owns.
Resume rule: continue from the first open box. Commit after each box.

## Step 0 results (live, claude 2.1.309, 2026-10-27)
- Mode L (locked, no services): `--restricted --permission-mode dontAsk --tools Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,TodoWrite --allowedTools Write(./**) Edit(./**) Read(./**)`. Write in cwd: works. Write `~/x`: refused. Read `~/.zshrc`: refused. `--restricted` loads NO MCP servers (not even claude.ai connectors), also with `--setting-sources user`.
- Mode S (services on): `--setting-sources user --settings {"disableAllHooks":true} --permission-mode dontAsk --tools Read,Write,Edit,Glob,Grep,WebSearch,TodoWrite --allowedTools Write(./**) Edit(./**) Read(./**) WebSearch TodoWrite <read MCP tools>`. Write/Read/Glob/Grep outside cwd: refused. IMPORTANT: a bare `Glob` or `Grep` in --allowedTools lets them see outside cwd. Never allow Glob/Grep by name; in cwd they work without a rule.
- Mode S loads the user's settings, so user allow rules (file tools, additionalDirectories) could widen access. Grove must read `~/.claude/settings.json` and `~/.claude/settings.local.json` before a Mode S run and refuse with a clear message if they allow Read/Write/Edit/Glob/Grep/NotebookEdit or list additionalDirectories. (Owner's file today: only Bash allows + Read denies, so OK.)
- init event (`type: system, subtype: init`) gives `tools` (names, MCP as `mcp__<server>__<tool>`) and `mcp_servers` [{name, status: connected|needs-auth|...}]. Server names look like `claude.ai Gmail`; tool prefix `mcp__claude_ai_Gmail__`.

## Boxes
- [x] 1. Tests first: agent_scope_test, mcp_tool_rules_test, agent_policy_test (modes L/S, never Bash, never bare Glob/Grep allow, WebFetch off in S), runner tests (cwd = chat folder, kept, env cut, stdout cap), settings-guard test.
- [x] 2. `app/lib/core/agent/agent_scope.dart` (root `<dataDir>/Agent workspace/<jobId>/`, uuid ids, isInside, audit: drop symlinks, 500 files / 200 MB caps) + fix `_agentFiles` traversal in `store_agent.dart`.
- [x] 3. Runner: cwd = chat folder, inputs/ copy, env cut (HOME USER LOGNAME PATH LANG TMPDIR SHELL), stdout cap 20 MB, folder kept.
- [x] 4. Policy args: Mode L / Mode S; user-settings guard; prompts say the folder rule.
- [x] 5. Services: `McpToolRules.isReadTool`, `listServices()` probe parsing init, prefs `agent.services`, old `agent.email` → Gmail on.
- [x] 6. UI: Settings → Agent (Services list with switches + status + read tools, Refresh; Agent folder row: Show in Finder, Delete agent files). Agents screen: Files part, per-chat "Use my services" (email_access reused).
- [x] 7. Docs: ADR 0008 (0007 is notebooks), fix ADR 0004 drift, settings help text, docs/assumptions.md lines, CHANGELOG 1.3.0 lines, blog post in docs/blog/.
- [x] 8. `./scripts/flutter_test.sh` green; goldens regenerated + pixel-compared if UI pictures changed.
- [x] 9. Review (security lens) + fixes.
- [x] 10. Live check on Mac (done 2026-10-27: probe lists 9 services; locked run and run with Context7 both refuse a write and a read outside the folder and have no shell). Push and draft PR into feat/next-version: not done here, the workflow does not allow them.
- [x] 11. Review 2, high: a run with services cannot write auto memory or agent memory files (`--settings` memory off, env `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, deny `Write/Edit(~/.claude/**)`, guard refuses `autoMemoryDirectory`); live check logged in ADR 0008.
- [ ] 12. Review 2: another computer shows the file names of the result when it did not run the chat.
- [ ] 13. Review 2: a linked file named CLAUDE.md or CLAUDE.local.md gets another name in `inputs/`.
- [ ] 14. Review 2: a bare verb (`query`, `fetch`) is not a read tool; `sql`, `url`, `http` are write words.
