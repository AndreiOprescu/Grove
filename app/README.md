# Grove (Flutter)

The Grove app for macOS, Windows, Android and iOS.
How to install it: the [README](../README.md#-install) of the repo.
Plan and milestones: `../docs/cross-platform-plan.md`. Decision: `../docs/adr/0001-cross-platform-flutter-supabase.md`.

## Layout
- `lib/core/` — pure Dart: models, planner math, parsers, recurrence, garden. No Flutter imports.
- `lib/data/` — local SQLite database (package `sqlite3`, no ORM), migrations, repositories, search, backup, export/import. No Flutter imports.
- `lib/state/` — app state and undo (`AppStore`, `Mutation`).
- `lib/sync/` — the sync engine: outbox, push and pull, last write wins. No Flutter imports.
- `lib/services/` — the system: reminders, tray, window, Supabase.
- `lib/ui/` — widgets, themes, screens.
- `config/supabase.example.json` — copy it to `config/supabase.json` (git-ignored) to build with sync.

## Commands (from the repo root)
- Tests (format check, analyzer, tests): `./scripts/flutter_test.sh`
- Build: `./scripts/flutter_build.sh macos|ios|android|appbundle|windows`
- Release files in `app/build/dist/`: `./scripts/flutter_release.sh macos|windows|android|ios`
- App icons, only when the logo changes: `swift scripts/make_flutter_icons.swift`
