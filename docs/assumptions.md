# Assumptions and decisions

Format: date · decision · why · how to undo

- 2026-10-02 · Native SwiftUI app built with Swift Package Manager (no Xcode installed) · best Mac feel, no dependencies · switch to Xcode project later if Xcode is installed
- 2026-10-02 · SQLite (system library) instead of SwiftData · SwiftData macros are missing from Command Line Tools · none needed
- 2026-10-02 · Target macOS 26 only · it is the owner's Mac (26.3); allows Liquid Glass · lower `platforms` in Package.swift
- 2026-10-02 · Local wall-clock times, no time zones · single-device personal app · add a TZ column later
- 2026-10-02 · App name "Grove", bundle id `local.grove.app` · placeholder · edit PLAN.md §0
- 2026-10-02 · Four themes: Grove (natural, default), Minimal, Futuristic, Vintage · owner asked for natural + 3 named themes · —
- 2026-10-02 · Desktop icon = symlink `~/Desktop/Grove` → `~/Applications/Grove.app` · no permission prompts needed · delete the symlink
- 2026-10-02 · Day Planner is the top priority feature (owner said so) · built in milestone M2 · —
- 2026-10-02 · Apple/Google Calendar sync is out of scope for v1 · touches data outside the app; needs owner OK · —
- 2026-10-02 · Default layout B (Day Spread) · shows planner, tasks and notes together · edit PLAN.md §0
- 2026-10-02 · Task model is named `TaskItem` · Swift already has a `Task` type · rename in Model/Task.swift
- 2026-10-02 · Saves use upsert (`ON CONFLICT DO UPDATE`), not `INSERT OR REPLACE` · REPLACE deletes the row first and would wipe subtasks and blocks by cascade · none needed
- 2026-10-02 · Daily backup: `VACUUM INTO` a `grove-YYYY-MM-DD.sqlite` copy, keep newest 14 · cheap safety net for local data · change `keep` in Backup.runDaily
- 2026-10-02 · Added test target `GroveTests` (depends on `Grove`) in Package.swift · lets us unit-test AppStore planner logic (create, move, ripple, undo) without a UI · remove the target; the tests in Tests/GroveTests go with it
- 2026-10-02 · Undo is an own stack of before/after snapshots (`Mutation` in AppStore), not `NSUndoManager` · one undo step can touch tasks and blocks together, and it is unit-testable · M5 must make ⌘Z go to the text editor when a note has focus
- 2026-10-02 · Planner view settings (zoom, snap, work hours, day/3-day/week, tray open) live in UserDefaults via `@AppStorage`, not the `settings` table · they are per-Mac view prefs, no need to export them · move to SettingsRepo
- 2026-10-02 · Release over the tray unschedules task blocks only; plain events are never deleted by a tray drop · avoids silent event loss · —
- 2026-10-02 · Not yet built in the planner (planned later): "only this / all events" dialog for repeats (M4), "Open/create linked note" menu item (M6), Focus mode (M8), drag block onto Week strip / Month day (M4) · they need features that do not exist yet · —
- 2026-10-02 · "Today" button shortcut is ⇧⌘T; ⌘T inside the grid also jumps to now · ⌘T alone is taken by the system tab command · change in PlannerView
- 2026-10-02 · Busy-day alert: planned time = minutes covered by any block (overlaps count once); alert fires once when a change takes a day from ≤ 9h to > 9h; limit read from UserDefaults `planner.dailyLimitMin` (default 540) · owner asked to be alerted past 9 hours · Settings screen in M8 should expose the limit
- 2026-10-02 · Planner content starts 34pt below the window top so the window buttons (hidden title bar) never cover the sidebar toggle · owner reported the left sidebar "does not come out fully" (best guess at the cause) · change `.padding(.top, 34)` in PlannerView
