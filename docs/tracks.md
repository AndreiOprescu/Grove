# Cross-platform port — two parallel tracks

The milestones F5–F12 in `docs/cross-platform-plan.md` are split into two
tracks. Two agents work at the same time, one per track. Each agent reads this
file, the plan, and `docs/assumptions.md` before it starts.

## The two tracks

| | Track A — engine | Track B — screens |
|---|---|---|
| Branch | `feat/xp-engine` | `feat/xp-screens` |
| Folder | `/Users/andrei/Desktop/Grove` (main checkout) | `/Users/andrei/Desktop/Grove-screens` (git worktree) |
| Milestones, in order | F5 → F11-core → F10-services → F8 | F6 → F7 → F9 → F10-screens |
| Owns (only this track edits) | `app/lib/state/`, `app/lib/sync/`, `app/lib/services/`, `app/lib/data/`, `app/lib/ui/tasks/`, `app/lib/ui/goals/`, `supabase/`, matching folders under `app/test/` | everything else in `app/lib/ui/`, `app/integration_test/`, goldens, matching folders under `app/test/` |

### What each milestone means here

- **F5 App state + undo** (A): as in the plan. The `AppStore` API is the
  contract for Track B. Push it as soon as it is green.
- **F6 Theme system + app shell** (B): as in the plan. It needs no store. Use
  fake data until F5 is pushed.
- **F7 Day Planner** (B): as in the plan. Merge `origin/feat/xp-engine` first,
  to get the F5 store. Also show subtasks in blocks with a "+N more" row (Swift
  PR #3) and subtasks on goal blocks (Swift PR #4).
- **F11-core Sync engine** (A): outbox, push/pull, last-write-wins, soft
  deletes, tested against a fake remote in pure Dart. The Supabase schema, Row
  Level Security, magic-link login and image upload come when the user gives
  the Supabase URL and anon key (git-ignored file, never committed). The login
  screen is built by Track A in `app/lib/ui/auth/` with Track B's theme.
- **F10-services** (A): reminders on all 4 OS (`flutter_local_notifications`),
  system tray on Mac and Windows (`tray_manager`), backup schedule. No screens.
- **F8 Tasks + Goals** (A): as in the plan. Starts after F6 is pushed. Merge
  `origin/feat/xp-screens` first, to get the theme and shell.
- **F9 Calendar + Notes** (B): as in the plan.
- **F10-screens** (B): Garden + growing plant, settings screen.
- **F12 Parity + release builds**: after both tracks are done. Whoever is free
  first starts it.
- **Swift migration 7** (A): when Swift PR #4 merges, add migration 7
  `block_subtasks` to the Flutter data layer. See `docs/assumptions.md`.

## Rules for working side by side

- Each track works only on its own branch and in its own folder. Never check out
  the other track's branch in your folder.
- To get the other track's work: `git fetch origin` then
  `git merge origin/<other branch>`. Never rebase. Never force-push.
- Edit only the folders your track owns. If you need a change in the other
  track's folder, do not make it. Write it under "Requests" in your track's
  section below, and work around it (for example, a small widget in your own
  folder).
- Shared files. Change them only when you must, in small edits:
  `app/pubspec.yaml`, `app/pubspec.lock`, `app/lib/main.dart`,
  `app/lib/ui/app.dart`, `scripts/`, `.github/workflows/`,
  `docs/cross-platform-plan.md`.
  - New packages: only the ones in the plan's "New dependencies" list. Ask the
    user about any other.
  - If `app/pubspec.lock` conflicts in a merge, keep either side, then run
    `cd app && flutter pub get` and commit the new lock file.
- `docs/assumptions.md`: Track A adds lines at the end of the
  "Cross-platform Track A" section. Track B adds lines at the end of the file
  (the "Cross-platform Track B" section). This keeps merges clean.
- Every milestone still needs: `./scripts/flutter_test.sh` green, CI green on
  all 4 OS, and a proof file `docs/acceptance/F<n>.md` (for a split milestone:
  `F10-services.md`, `F10-screens.md`, `F11-core.md`).
- Stop and report to the user after each milestone.
- Each track has one draft PR into `feat/cross-platform-flutter`. Keep it
  updated. The user merges.

## Status

### Track A — engine

- F5: not started
- Requests to Track B: none

### Track B — screens

- F6: not started
- Requests to Track A: none
