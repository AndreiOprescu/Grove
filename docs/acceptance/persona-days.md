# Persona days — proof

Branch `feat/persona-days`, into `feat/cross-platform-flutter`. Flutter app only. No new package. No change to the Supabase SQL.
The owner's words: "Create the infrastructure for collecting how many good/bad days the user has had. Create 3 bars for the types of days the user can record. This should be seen in the persona tab. I want this page to change in look."
The owner's choices (2026-10-16): layout "A · Two columns"; a switch "This month / All time", this month first.
Check: `./scripts/flutter_test.sh` (2026-10-16: 2887 tests passed, analyze clean, format clean).

## What was built

| Part | File |
|---|---|
| Count of daily notes per mood, in a span of days | `app/lib/data/repos.dart` (`NoteRepo.moodCounts`) |
| `DayCounts` (counts and bar fill) and `DaySpan` (this month / all time) | `app/lib/state/rules/mood.dart` |
| The store: `dayCounts`, `daySpan`, `setDaySpan`, `todayMood`, `setTodayMood` | `app/lib/state/store_persona.dart` |
| The "Your days" card: 3 bars, the switch, "How was today?" | `app/lib/ui/persona/day_bars.dart` (new) |
| The mood picker takes a mood and a callback, so the card can use it | `app/lib/ui/notes/day_panel.dart` (`MoodPicker.of`) |
| Two columns when there is room, one column when not | `app/lib/ui/persona/persona_view.dart` |

## Proof

| Item | Test |
|---|---|
| Only daily notes with a mood count; the span keeps its first and last day | `app/test/data/note_mood_counts_test.dart` |
| The biggest bar is full; no days gives empty bars; month edges (Dec, leap Feb) | `app/test/state/rules/day_counts_test.dart` |
| The store counts per span; today's mood from the Persona screen; undo; the span is kept | `app/test/state/persona_store_test.dart` (group "Days") |
| 3 bars with counts and fills; the switch; the empty line; the picker sets today; wide = beside, narrow = below | `app/test/ui/persona/persona_view_test.dart` (group "Your days") |
| Moods sync between devices | No new code: `notes.mood` already syncs |
