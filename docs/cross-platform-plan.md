# Grove on Windows, Android, iOS (and Mac) — plan

## Context
Grove is a Mac-only app today: Swift + SwiftUI + AppKit, SQLite, local-only. About 15K lines of code and 10K lines of tests.
The user wants the same app, with the same look and behaviour, on Windows, Android and iOS. Data must sync between devices.
Swift/SwiftUI cannot run on Windows or Android, so we rewrite the app in one cross-platform stack.

## Stack options (asked for by the user)
| Option | Same look everywhere | RAM / speed | Maturity on all 4 | Verdict |
|---|---|---|---|---|
| **Flutter (Dart)** | Yes, draws every pixel (Impeller) | ~80–150 MB, AOT native code, 60–120 fps | High | **Chosen** |
| Kotlin + Compose Multiplatform | Yes, draws every pixel (Skia) | Desktop runs on JVM: ~200+ MB, slower start | Android best, iOS newer | Runner-up |
| Tauri 2 + web UI (Svelte) | Mostly; system web views differ per OS | Small on desktop, web view on mobile | Mobile still young | No |
| React Native (+ RN Windows) | No, native widgets differ per OS | OK | Windows/Mac are side projects | No |
| Keep Swift (Skip.tools) | iOS + Android only | Native | No Windows | No |

User decisions (2026-10-09): **Flutter**, **sync via Supabase**, **install Xcode on this Mac + GitHub Actions for Windows builds**.

## Approach
1. **New branch** `feat/cross-platform-flutter` from `main`. New Flutter project in `app/` in this repo. The Swift app stays until the Flutter app matches it.
2. **Port the core first, tests first.** The Swift tests in `Tests/GroveCoreTests` and `Tests/GroveTests` are the spec. Port each test to Dart, see it fail, then port the code:
   - `Sources/GroveCore/Planner/PlannerMath.swift` → `app/lib/core/planner/planner_math.dart` (snap, overlap columns, ripple, free slots).
   - `Sources/GroveCore/Parsing/*` (QuickAddParser, AtDateParser, NoteParser, ReferenceParser) → `app/lib/core/parsing/`.
   - `Sources/GroveCore/Recurrence/RecurrenceEngine.swift`, `Services/*` (search, backup, export/import, reminders, focus rules) → `app/lib/core/`.
   - `Sources/GroveCore/Model/*` → plain Dart classes. Keep the same field names.
   - `Sources/Grove/AppStore*.swift` (state, custom undo with before/after snapshots) → `app/lib/state/` with the same `Mutation` idea.
3. **Database:** `drift` on SQLite with FTS5, same tables as `Sources/GroveCore/Database/` migrations. Add to every synced row: `uuid`, `updated_at`, `deleted`, `user_id`. Import from the current Mac app via the existing JSON export.
4. **Sync (Supabase):** local DB stays the source of truth, app works offline. An outbox table holds local changes. Push outbox, pull rows newer than last pull. Conflict rule: last write wins per row. Login: email magic link. Row Level Security: a user only sees their own rows. Images go to Supabase Storage.
5. **UI:** port screen by screen in PLAN.md order. Day Planner (§5.1) first. Then Tasks, Calendar, Notes, Goals, Garden, Themes, Settings.
   - Planner grid, Garden, plant, ambient background: `CustomPainter` (replaces SwiftUI `Canvas`). Drag/resize: `GestureDetector` + long-press on touch.
   - Rich text editor (markdown, images, mentions, `[[` links): build on Flutter `TextField` + custom spans; fall back to `super_editor` if needed.
   - Liquid Glass look: `BackdropFilter` blur so it looks the same on every OS.
   - Menu bar extra → system tray on Mac/Windows (`tray_manager`). Not on phones.
   - Notifications: `flutter_local_notifications` on all 4.
   - Phones: same screens, same theme, same colours. Narrow screens show one day column instead of the spread. Log this in `docs/assumptions.md`.
6. **Builds:** Mac, iOS, Android build on this Mac (after Xcode + Android SDK install). GitHub Actions builds and tests Windows. New scripts: `scripts/flutter_build.sh`, `scripts/flutter_test.sh`.
7. **Docs:** update `PLAN.md` §0 and §14 (new stack, new dependencies, sync). Add ADR for the stack and sync choice. Log small choices in `docs/assumptions.md`.

## New dependencies (need user OK — this plan is that ask)
Flutter SDK, `drift` + `sqlite3_flutter_libs`, `supabase_flutter`, `flutter_local_notifications`, `tray_manager`, `path_provider`, `uuid`. Maybe `super_editor`.
New services/costs: Supabase (free tier), Apple developer account ($99/year) for iOS on a real phone, Google Play ($25 once) if published.

## Setup the user must do
- Install Xcode from the App Store.
- `brew install --cask flutter android-studio` (then accept Android SDK licences).
- Create a Supabase project. Give me the project URL and anon key (stored in a git-ignored file, never committed).

## Milestones
Each milestone is one commit series on `feat/cross-platform-flutter`, ends green on CI, and has a proof file `docs/acceptance/F<n>.md`. I stop after each one and report.

| # | Milestone | What is in it | Done when |
|---|---|---|---|
| F1 | Skeleton + CI | Flutter project in `app/`, folder layout (`core/`, `data/`, `state/`, `ui/`, `sync/`), lint rules, `scripts/flutter_build.sh`, `scripts/flutter_test.sh`, GitHub Actions for Mac/Windows/Android/iOS | Empty app opens on all 4. CI green. |
| F2 | Core models + planner math | Models, `DayKey`, `PlannerMath` (snap, overlap columns, ripple, free slots) + ported tests | All ported tests green. |
| F3 | Parsers + recurrence | QuickAdd, AtDate, Note, Reference, Markdown parsers, `RecurrenceEngine` + ported tests | All ported tests green. |
| F4 | Local database | `drift` schema = current SQLite tables + sync columns, migrations, repos, FTS5 search, backup, JSON export/import | Repo + search + export tests green. JSON from Mac app imports. |
| F5 | App state + undo | `AppStore` port: state, `Mutation` before/after undo, selection, revisions + ported `GroveTests` logic tests | Store tests green. |
| F6 | Theme system + app shell | 4 themes, colours, fonts, glass blur, ambient background, left dock, navigation, phone vs desktop layout | Golden screenshots match on all 4 for each theme. |
| F7 | **Day Planner** | Grid, blocks, create/move/resize by mouse and touch, cross-day drag, overlaps, keyboard, undo | Matches `design/layouts.html` demo. Integration test passes on all 4. |
| F8 | Tasks + Goals | Task lists, rows, priority outline, 8 colours, subtasks, inspector, quick-add, unscheduled tasks, goals, workload bar | Feature tests + goldens green. |
| F9 | Calendar + Notes | Calendar views, rich text editor (markdown, images, mentions, `[[` links), daily/weekly notes, backlinks | Feature tests + goldens green. |
| F10 | Garden, notifications, tray, settings | Garden + growing plant, reminders on all 4, system tray on Mac/Windows, settings screen | Notifications fire on each OS. Goldens green. |
| F11 | Login + sync | Supabase project schema + Row Level Security, magic-link login, outbox push/pull, last-write-wins, image upload | Two-device offline-edit test syncs to same data. |
| F12 | Parity + release builds | Feature checklist vs PLAN.md, perf check (startup, RAM, 60 fps scroll), signed builds per OS, docs + ADR | Every PLAN.md feature has proof. You decide when to retire the Swift app. |

F1–F5 have no UI risk and are fast. F7 is the hardest and most important. F11 needs your Supabase keys before it starts.

## Verification
- `flutter analyze` and `flutter test` (all ported unit tests) green, on CI for all 4 OS.
- Golden screenshot tests: same screen rendered on each platform must match the reference image. This proves "looks the same".
- `integration_test` runs of the Day Planner (create, drag, resize, overlap, undo) on iOS simulator, Android emulator, Mac, Windows (CI).
- Sync test: two devices (e.g. Mac + Android emulator), edit offline on both, reconnect, check both show the same data.
- Map each PLAN.md feature to proof in `docs/acceptance/`.
