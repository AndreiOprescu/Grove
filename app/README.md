# Grove (Flutter)

The cross-platform Grove app: macOS, Windows, Android, iOS.
Plan and milestones: `../docs/cross-platform-plan.md`.

## Layout
- `lib/core/` — pure Dart: models, planner math, parsers, recurrence. No Flutter imports.
- `lib/data/` — local SQLite database (drift), repositories, search, export/import.
- `lib/state/` — app state and undo (port of `AppStore`).
- `lib/ui/` — widgets, themes, screens.
- `lib/sync/` — Supabase login and sync.

## Commands (from the repo root)
- Tests: `./scripts/flutter_test.sh`
- Build: `./scripts/flutter_build.sh macos|ios|android|windows`
