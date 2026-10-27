# Progress: remove wake/sleep "+", task ⇄ activity switch (branch feat/planner-kind-switch)

Plan: `/Users/andrei/.claude/plans/you-are-on-ultracode-vast-petal.md` (PR B part).
Base: origin/feat/reorganise-day (draft PR #50). PR B goes into feat/next-version; merge #50 first.
Owner answers 2026-10-27: remove the "+" fully; task → activity = the block stays in the same place, as an activity.
Resume rule: continue from the first open box. Commit after each box.

## Boxes
- [x] 1. Tests first: day menu wake/sleep items; no `day-marker-add` in either header; store `toggleKind` both ways (undo, same event id, multi-block, subtask/goal confirm, not offered for done / recurring / goal block / plain event, notes kept); widget tests for block menu, task inspector chips, activity editor chips.
- [x] 2. Remove the "+" (`planner_view.dart` `_showDayMarkers` + button in both headers; drop `showDayMarkerMenu` if unused). Add Add/Remove wake-up and sleep lines to the day menu (`app/lib/ui/calendar/day_menu.dart`), default time from `newDayMarkerMinute`. Check the phone opens the day menu.
- [x] 3. Store `toggleKind` in `app/lib/state/store_planner.dart` (one Mutation).
- [x] 4. UI: block menu lines, shared Task · Activity chip widget (from `_kindRow`), task inspector, event editor.
- [ ] 5. Docs: docs/assumptions.md (update line about "no menu line"), CHANGELOG 1.3.0 lines, blog post if docs/blog/ exists.
- [ ] 6. `./scripts/flutter_test.sh` green; goldens regenerated and pixel-compared.
- [ ] 7. Review (correctness + UI) + fixes.
- [ ] 8. Push; draft PR into feat/next-version ("merge #50 first").
