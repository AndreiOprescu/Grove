# F11-core · Sync engine — proof

Plan: `docs/cross-platform-plan.md` (milestone F11). Track A, branch `feat/xp-engine` (`docs/tracks.md`).
Check: `./scripts/flutter_test.sh` (2026-10-10: 1219 tests passed after the merge of `origin/feat/xp-screens`, analyze clean, format clean). 102 of them are the new tests in `app/test/sync/`.
CI run 38060395876 (commit 4f07cfa): green on Android, Windows, macOS, iOS.

Scope (`docs/tracks.md`): "outbox, push/pull, last-write-wins, soft deletes, tested against a fake remote in pure Dart."
Acceptance of F11 in the plan: "Two-device offline-edit test syncs to same data."

Not in this step: Supabase schema, Row Level Security, magic-link login, image upload, the login screen, and the call from the store. They need the owner's Supabase keys and the answer to Q-4.

## What was built

| Part | File |
|---|---|
| Outbox table, clock, pull cursor, triggers on the 12 synced tables | `app/lib/data/sync_schema.dart` (`SyncSchema`, `SyncTable`), sync migration 2 in `app/lib/data/migrations.dart` |
| Read the outbox, the clock and the cursor | `app/lib/sync/outbox.dart` (`Outbox`, `OutboxEntry`) |
| One row on its way | `app/lib/sync/row_change.dart` (`RowChange`) |
| The contract of a remote | `app/lib/sync/sync_remote.dart` (`SyncRemote`, `RemoteUnavailable`) |
| The fake remote | `app/lib/sync/memory_remote.dart` (`MemoryRemote`) |
| Push, pull, last write wins, repairs | `app/lib/sync/sync_engine.dart` (`SyncEngine`, `SyncReport`) |
| One import | `package:grove/sync/sync.dart` |

`app/lib/sync/` and `app/lib/data/` have no Flutter import. `scripts/flutter_test.sh` checks this now for `lib/sync` too. No new package.

## Proof for each scope word

| Scope | Tests (all green) |
|---|---|
| Outbox | `outbox_test.dart` (20): a save, a second save, a delete, a cascade, a set-null, a link clean-up, two-part keys, exdates, settings, every table; 50 saves = 50 rising stamps; the clock never goes back; import; an old database file is filled at stamp 0; reopen keeps outbox and cursor; a new column is watched; a sync-only column is no change; only 2 unique rules exist; the export file holds no sync tables |
| Fake remote | `memory_remote_test.dart` (9): new row, newer row, older and same age refused, delete, two tables, pages, offline, a push that stops half way, own copy of the data |
| Push / pull | `sync_engine_test.dart` group "Push and pull" (9): every kind of row arrives; nothing is sent back; search finds pulled rows; pages; the cursor |
| Offline | group "Offline" (6): offline throws and loses nothing; a push or a pull that stops half way; a change during a push; two sync calls are one run; a new sync after a failed one |
| Last write wins | group "Last write wins" (8): later change wins in both sync orders; delete against change, both ways; same age; a clock that is behind; whole row, not single fields |
| Soft deletes | "a delete travels, with everything that hung on the row"; "a later delete wins over a change"; "a later change wins over a delete: the row comes back"; `remoteRows(...)` checks the "gone" rows on the remote |
| Rows that point at other rows | group of 4, and group "A pull between two pages of a push" (2): a watcher that syncs after each page never has to repair a row |
| Two rows that must be one | group of 8 (tags and daily notes) and group "A row that comes back with a new id" (6) |
| Rows this app cannot use | group of 3: unknown table, unknown column, a row that cannot be saved is named in `SyncReport.skipped` |
| **Two-device offline-edit test syncs to same data** | `store_sync_test.dart` (2): two `AppStore`s on two devices work offline (subtask, quick add with a time, tick, rename a note, tag), sync, and `expectSame` compares every row of every synced table. And "an undo is a new change and travels too" |
| Many devices | group "Many devices": 25 random runs, 3 devices, 90 steps of 14 kinds of work with syncs in between. At the end all 3 databases are the same, and a 4th new device gets the same data with an empty outbox and no skipped row |

## Extra checks, done one time (not in the test suite)

- 1000 more random runs (2 to 4 devices, page size 1 to 5, 40 to 240 steps; in 500 of them a second device synced between two pages of a push, and the first device changed data during its own push). All ended with the same data on every device and on a new device.
- 13 breaks of the engine on purpose (no clock update, no repair, no id rule, other push order, late win decision, and more). Each break made at least 1 test fail. So the tests see these rules.

## Decisions and questions

- Decisions: `docs/assumptions.md`, section "Cross-platform Track A", the lines that start with "F11-core".
- Q-3 (DEFAULT, built as A): the same daily note on two devices → one note with both texts.
- Q-4 (ASK, waits for the owner): first login on a device that has data when the account has data too.
