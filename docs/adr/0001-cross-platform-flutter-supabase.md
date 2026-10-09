# ADR 0001 · Cross-platform Grove with Flutter and Supabase sync

Status: Accepted (owner decision, 2026-10-09)

## Context
Grove is a Mac-only Swift/SwiftUI app with a local SQLite database.
The owner wants the same app, with the same look and behaviour, on macOS, Windows, Android and iOS.
Data must move between devices.
Memory use and runtime speed matter.

## Options
| Option | Same look everywhere | RAM / speed | Maturity on all 4 |
|---|---|---|---|
| Flutter (Dart) | Yes, own renderer (Impeller) | ~80–150 MB, AOT native code | High |
| Kotlin + Compose Multiplatform | Yes, own renderer (Skia) | Desktop on JVM: ~200+ MB, slower start | Android best, iOS newer |
| Tauri 2 + web UI | Mostly; system web views differ | Small on desktop | Mobile young |
| React Native (+ RN Windows) | No, native widgets differ | OK | Desktop is a side project |
| Swift + Skip.tools | iOS + Android only | Native | No Windows |

## Decision
- UI and logic: **Flutter**, one codebase in `app/`.
- Local data: SQLite through `drift`, with FTS5. The local database is the source of truth. The app works offline.
- Sync: **Supabase** (Postgres, auth, storage). Outbox push, pull newer rows, last write wins per row. Email magic-link login. Row Level Security per user.
- Builds: macOS, iOS, Android on the owner's Mac (Xcode + Android SDK). Windows on GitHub Actions.

## Consequences
- Full rewrite of ~15K lines of Swift. The Swift tests are the spec for the Dart port.
- PLAN.md §14 rules "no third-party packages" and "no Xcode" no longer hold for the Flutter app. New packages: `drift`, `sqlite3_flutter_libs`, `supabase_flutter`, `flutter_local_notifications`, `tray_manager`, `path_provider`, `uuid` (maybe `super_editor`).
- New costs: Supabase (free tier first), Apple developer account ($99/year) for iOS devices, Google Play ($25 once) if published.
- Data leaves the device for the first time. Supabase holds the owner's data.
- The Swift app stays in the repo until the Flutter app reaches parity (milestone F12). The owner decides when to retire it.

Full plan and milestones: `docs/cross-platform-plan.md`.
