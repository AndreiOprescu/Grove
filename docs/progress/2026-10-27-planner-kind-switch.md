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
- [x] 5. Docs: docs/assumptions.md (update line about "no menu line"), CHANGELOG 1.3.0 lines, blog post if docs/blog/ exists.
- [x] 6. `./scripts/flutter_test.sh` green; goldens regenerated and pixel-compared.
- [x] 7. Review (correctness + UI) + fixes.
- [ ] 8. Push; draft PR into feat/next-version ("merge #50 first").

## Goldens (box 6)
33 goldens regenerated (goals, error, palette, planner, day_lines, focus_done, linked_note, subtasks). Pixel compare old vs new (>12/255): every change is in the header band (desktop y40-70, phone y88-115, Today timeline row y96-119): the "+" is gone and the buttons close up. Nothing else moved. `./scripts/flutter_test.sh`: +3762, all passed.

## Review (box 7)
- Fixed: an activity with block subtasks no longer offers the switch (they would be hidden on a task block).
- Fixed: the editor message covers repeat, all day and past midnight; test for a draft made all day just before the switch.
- Fixed in box 6: the switch line sits below the linked note line, so the note line stays right after "Split in Two".
- `./scripts/flutter_test.sh`: +3764, all passed.
- Box 8 (push, draft PR) is not done here: this job may not push or open PRs.

## Review round 2 (2026-10-27)
- [x] Meeting note of a renamed task stays linked after the switch (note renamed in the same undo step).
- [x] Activity keeps the colour of the task.
- [x] Only block of a task with an agent job does not switch (job and chat would be lost).
- [x] Activity to task drops the links of the activity notes (no double backlink).
