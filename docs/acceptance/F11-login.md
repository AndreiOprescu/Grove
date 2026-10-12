# F11-login · Login, Supabase remote, store wiring — proof

Plan: `docs/cross-platform-plan.md` (milestone F11: "Supabase project schema + Row Level Security, magic-link login, outbox push/pull, last-write-wins, image upload"). Track A, branch `feat/xp-engine` (`docs/tracks.md`). The engine itself is F11-core (`docs/acceptance/F11-core.md`).

This step was built with no Supabase project and no keys. No account was made, no real service was called and no data left this Mac. All tests run against fakes: a fake in memory, and a small HTTP server on `127.0.0.1` that the real Supabase package talks to.

Check: `./scripts/flutter_test.sh` (2026-10-11: 1764 tests passed, analyze clean, format clean). About 180 of them are new with this step.
CI: see "CI" below.

## What was built

| Part | File |
|---|---|
| SQL for Supabase: 13 data tables and a counter table, Row Level Security, the two sync functions, the private bucket for images and its rules | `supabase/migrations/20261011000000_grove_sync.sql` |
| The code that makes this SQL from the schema of the app | `app/lib/sync/remote_schema.dart` (`RemoteSchema`), `app/lib/sync/supabase_sql.dart` (`supabaseSql`, `SupabaseNames`) |
| The Supabase remote (`SyncRemote`), behind a small interface | `app/lib/sync/supabase_remote.dart` (`SupabaseRemote`, `SchemaMismatch`, `NotSignedIn`), `app/lib/sync/supabase_api.dart` (`SupabaseApi`, `SupabaseApiError`) |
| The login behind an interface, and a fake | `app/lib/sync/auth_gateway.dart` (`AuthGateway`, `Account`, `AuthFailure`, `MemoryAuth`) |
| The config and the two parts a store needs | `app/lib/sync/sync_backend.dart` (`SyncConfig`, `SyncBackend`) |
| The only file that imports `supabase_flutter` | `app/lib/services/supabase_backend.dart` (`SupabaseBackend.start`, `SupabaseClientApi`, `SupabaseAuth`) |
| First login: tie the database to an account, "add this device", "use the account" | `app/lib/sync/sync_engine.dart` (`account`, `remoteHasData`, `hasLocalData`, `addDeviceTo`, `replaceWithAccount`), `app/lib/sync/outbox.dart`, `app/lib/data/sync_schema.dart` (`queueAll`), `app/lib/data/backup.dart` (`beforeSyncName`) |
| The store calls the engine | `app/lib/state/store_sync.dart` (`AppStoreSync`: `syncStatus`, `sendLoginLink`, `verifyLoginCode`, `signOut`, `answerFirstSync`, `syncNow`, `lastSyncAt`, `syncError`, `syncWaiting`, …) |
| A sync each 5 minutes and when the app comes to the front | `app/lib/services/sync_schedule.dart`, `app/lib/services/app_services.dart` |
| The login screen | `app/lib/ui/auth/sync_card.dart` (`SyncCard`, `SyncWords`), `app/lib/ui/auth/first_sync_dialog.dart` (`FirstSyncChoices`, `showFirstSyncDialog`, `FirstSyncGate`) |
| The config file | `app/config/supabase.example.json` (in git, empty values), `app/config/supabase.json` (yours, git ignores it) |
| SQL checks on a plain Postgres | `supabase/tests/` (`run.sh`, `stub_supabase.sql`, `sync_test.sql`, `after_rerun_test.sql`), `.github/workflows/supabase.yml` |

New package: `supabase_flutter` 2.18.2 (on the plan's list). No other package was added by hand.

## Proof for each part of the job

| Part | Tests (all green) |
|---|---|
| 1. SQL schema and RLS | `app/test/sync/supabase_sql_test.dart` (9): the newest SQL file is what the code makes from the app schema; every synced table and every data column of the app is there and no other column; the only bytes are image bytes; every table has RLS and the 3 rules (read, add, change the own rows); no delete rule and nothing open to all; every step can run again. On Postgres: `supabase/tests/sync_test.sql` and `after_rerun_test.sql` (see "CI") |
| 2. Supabase remote | `app/test/sync/remote_contract.dart` holds the 12 shared checks of a `SyncRemote`. They run against the memory remote (`memory_remote_test.dart`, 14), against `SupabaseRemote` on a fake (`supabase_remote_test.dart`, 43) and against `SupabaseRemote` with the real package over HTTP (`app/test/services/supabase_backend_test.dart`, 27). Also: values keep their type; the errors of the server become `SchemaMismatch`, `NotSignedIn`, `RemoteUnavailable`; the whole sync engine works on this remote |
| 3. Login | `supabase_backend_test.dart`: the real package sends the email, signs in with the code, keeps the session and signs out, against the local server; a wrong code, too many emails, no connection each give their own message. Screen: `app/test/ui/auth/sync_card_test.dart` (13) and `auth_golden_test.dart` (16 pictures in `app/test/ui/auth/goldens/`: no sync, email, email with error, code, signed in in the 4 themes and dark, error, the question in the card, the window of the question in the 4 themes and dark). Each picture test first checks that all text sits on whole pixels (`textOffPixels`) |
| 4. Store | `app/test/state/sync_store_test.dart` (35): a build with no keys; the login steps; a session from the last start; Q-4 in every case (empty account, empty device, both have data, "Not now", a failed replace keeps the device as it was, another account); when a sync runs (after login, after a change, many changes are one sync, "Sync now", nothing to send sends nothing); errors (offline, other schema, login ended) and no retry loop; sign-out keeps the data. `app/test/sync/account_sync_test.dart` (15): the engine side of the first login. `app/test/services/sync_schedule_test.dart` (4) |
| 5. Config | `app/test/sync/sync_config_test.dart` (5): no values, half of the values or a bad address mean "no sync". `supabase_backend_test.dart`: "a build with no keys has no sync". `git check-ignore app/config/supabase.json` prints the path |
| 6. Image upload | `supabase_remote_test.dart` group "Images" and `supabase_backend_test.dart` group "Files" and "Two devices of one person": the bytes go up before the row, come down the same on the second device, are not downloaded when the device has them, another person cannot reach them, a missing file gives a row with no bytes |
| Two devices (acceptance of F11) | `supabase_backend_test.dart` "every kind of row and an image go from one to the other" (real package, local server) and `sync_store_test.dart` (two stores, one account) |

## CI

- Flutter, 4 jobs: runs 38091561817 (pull_request) and 38091559060 (push) on commit 20e1121. In both runs android, windows, macos and ios ended with success, and no step failed. The only skipped steps are the ones for another target and the upload of the pictures of a golden failure (it runs only after a failure).
- SQL on Postgres: workflow `supabase-sql`, runs 38091561825 (pull_request) and 38091559070 (push) on commit 20e1121, both success. PostgreSQL 16.15 of the runner, 80 checks "ok", "All SQL checks passed."

## Not done, or not verified

- **The SQL never ran on a real Supabase project.** It ran on the Postgres of the CI runner with a small stand-in for the Supabase parts (`supabase/tests/stub_supabase.sql`: the two roles, `auth.uid()`, `auth.users`, `storage.buckets`, `storage.objects`, `storage.foldername`). The stand-in is my reading of Supabase, not Supabase.
- **The Supabase package never talked to a real Supabase.** It talked to my local server (`app/test/services/local_supabase.dart`), which answers as I read the package code. Real login email, real token refresh after 1 hour, real file store: not seen.
- **The dashboard steps below are from memory.** I did not open Supabase. A name of a menu can differ.
- **The login cannot be reached in the app yet.** The card and the gate are widgets; Track B owns the screens and has to place them (`docs/tracks.md`, "Requests to Track B, with F11-login").
- A link in the email that opens Grove: not built (Q-9).
- Deleting an account: not built (Q-11).
- The app was not started by hand on a device with the new network permission (macOS entitlements, Android manifest). CI builds it for the 4 systems.

## Needs the owner's keys

Do these steps in this order. They cost nothing on the free plan.

1. **Make the project.** Sign in at supabase.com, "New project", free plan, a region near you. Keep the database password in your password manager.
2. **Apply the SQL.** Dashboard → SQL Editor → new query. Paste the whole file `supabase/migrations/20261011000000_grove_sync.sql` and run it. It says "Success. No rows returned". It is safe to run again.
   - Since 2026-10-12 (the subtasks of a goal): then paste and run the whole file `supabase/migrations/20261012000000_grove_sync_goal_subtasks.sql` the same way. It adds the table `goal_subtasks` and moves the schema number from 7 to 8. The app and the server must have the same number, so the sync of a build with goal subtasks works only after this second file. It is safe to run again.
   - Look: Table Editor shows 15 tables in `public` (14 data tables and `sync_state`), each with RLS on. Storage shows the bucket `grove-attachments`, not public.
3. **Email login.** Authentication → Sign In / Providers → Email must be on (it is, in a new project).
   - Authentication → Emails → Templates: in "Magic Link" and in "Confirm signup" add a line with the code, for example `Your code for Grove: {{ .Token }}`. The first login of an address uses "Confirm signup", each later login uses "Magic Link". Without this line the email has no code, and Grove cannot finish the login (Q-9).
   - The mail service of a new project sends only a few emails each hour, and only to the addresses of the members of your Supabase organisation. Sign in to Grove with the address of your Supabase account.
4. **Put the address and the key in the file.**
   - `cp app/config/supabase.example.json app/config/supabase.json`
   - Project Settings → API (or "API Keys"): copy "Project URL" to `SUPABASE_URL` and the `anon` `public` key (or the "publishable" key) to `SUPABASE_ANON_KEY`.
   - Never use the `service_role` key or a "secret" key. Never commit `app/config/supabase.json`. `git status` must not show it.
   - The address and this key are inside each app you build. That is normal for Supabase: the rules of step 2 protect the rows.
5. **Build with the keys.** `./scripts/flutter_build.sh macos` (or `ios`, `android`, `windows`) finds the file by itself. To run from source: `cd app && flutter run -d macos --dart-define-from-file=config/supabase.json`. A build made by CI has no keys and no sync.
6. **After your first login** (Q-14, pick A): Authentication → Sign In / Providers → turn off "Allow new users to sign up".

### The two-device check

This needs the card in the app (Track B). Then:

1. Device 1 (for example the Mac): open the sync card, type your address, "Send the email", type the code of the email, "Sign in". The card says "Signed in as …" and "Last sync today at …". Supabase → Table Editor → `tasks` shows the rows of the device.
2. Device 2 (for example the Android phone, same build with the keys): sign in with the same address. Grove asks one time: "Use the account data" or "Add this device too". Choose "Use the account data". Device 2 shows the lists and tasks of device 1.
3. Turn the network off on both devices. On device 1 rename a task and add a task. On device 2 tick another task and write a line in a note.
4. Turn the network on. On each device press "Sync now" (or wait 5 minutes). Both devices show the same 4 changes.
5. Change the title of the same task on both devices while offline, device 1 first. After a sync on both, the title of device 2 is on both (the last write wins).
6. Put a picture in a note on device 1. After a sync, device 2 shows the picture. Storage → `grove-attachments` has one folder with your user id.
7. Second account (optional, before step 6 of the list above): sign out, sign in with another address. Grove asks before anything moves. Table Editor shows the rows of each user with their own `user_id`.

If a step fails, the card shows the error in one line. Send me that line.

### If you want to delete an account by hand (Q-11, pick A)

Not verified on a real project. In this order:

1. Storage → `grove-attachments`: delete the folder with the user id.
2. SQL Editor, with the user id in place of `<user id>`:

```sql
do $$
declare
  u uuid := '<user id>';
  t text;
begin
  foreach t in array array['attachments', 'settings', 'note_tags', 'task_tags', 'tags',
    'links', 'event_exdates', 'block_subtasks', 'events', 'tasks', 'goals', 'notes',
    'lists', 'sync_state'] loop
    execute format('delete from public.%I where user_id = $1', t) using u;
  end loop;
end
$$;
```

3. Authentication → Users: delete the user.

The devices keep their local data. On a device that is still signed in, the next sync shows an error; sign out there.

## Decisions and questions

- Decisions: `docs/assumptions.md`, section "Cross-platform Track A", the lines that start with "F11-login".
- Q-4 (answered A): built. Grove asks one time.
- Q-9 (DEFAULT, built as A): the code of the email is typed in Grove. No link opens Grove.
- Q-10 (DEFAULT, built as A): sign-out keeps the data of the device.
- Q-11 (ASK): a "Delete account" button. Not built.
- Q-12 (DEFAULT, built as A): the login is kept as the Supabase package keeps it.
- Q-13 (DEFAULT, built as A): the file of a deleted picture stays on the server.
- Q-14 (ASK): who can make an account in your project. A setting in Supabase, no code.
