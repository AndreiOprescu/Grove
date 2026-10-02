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
