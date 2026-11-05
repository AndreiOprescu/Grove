# Goal map: acceptance

Spec: `PLAN.md` §5.9. Decision: `docs/adr/0008-goal-map.md`.

The owner must run `supabase/migrations/20261105000000_grove_sync_goal_map.sql` at the same time as the release. A schema mismatch stops sync.

## Automatic proof

| Item | Proof |
|---|---|
| Habit and Project; old goals read as Habits | `test/data/goal_square_repo_test.dart`, `test/sync/goal_map_sync_test.dart` |
| Loops and orphans from a sync merge do not crash | `test/core/goals/` (random graphs), `test/sync/goal_map_sync_test.dart` |
| Ready, wait state, link rules, delete joins children to parents | `test/core/goals/`, `test/state/goal_map_store_test.dart` |
| Layout does not depend on input order | `test/core/goals/` |
| Map draws, glides, keeps the camera steady, opens readable on a phone | `test/ui/goal_map/goal_map_view_test.dart` |
| Goals screen, form, sheet, tool bar, keys | `test/ui/goal_map/goals_screen_test.dart` |
| Block tick question, finish early | `test/ui/goal_map/block_tick_question_test.dart` |
| Goals panel: Ready, waiting, Later steps, drag, right-click menu | `test/ui/goals/project_row_test.dart` |
| Deadlines panel: project row opens the map | `test/ui/deadlines/deadlines_pane_test.dart` |
| Phone bar with the new tab | `test/ui/shell/root_view_test.dart` |
| Look in light, dark, a theme, phone | `test/ui/goal_map/goal_map_golden_test.dart` |
| Whole flow with real pointers and animation on, data in memory | `integration_test/goal_map_test.dart`, passed on the Mac and on the arm64 Android emulator |

## By hand, on the Mac and the Samsung phone

Use a copy of "Delft AI Hub work".

- [ ] Smooth map: `cd app && flutter run --profile -t tool/goal_map_bench.dart -d RZCY80AVTDT` (50 squares, 70 lines).
- [ ] Type a square's name on the phone. See the square and its "+" above the sheet. Close the sheet. See the keyboard go away.
- [ ] Make a Project with squares, a shared square and a wait.
- [ ] Drag a Ready square onto a day and tick the block. See the question.
- [ ] Start a wait. See the countdown, then "1 day over".
- [ ] Delete a square. See its child join the parent.
- [ ] Convert a Habit. See the blocks stay.
- [ ] Finish early. Remove the tick. See the Project open.
- [ ] See the date in the Deadlines panel. Tap it.
- [ ] Sync between Mac and phone.
- [ ] Try reduce motion.
