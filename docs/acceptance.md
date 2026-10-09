# Acceptance proof for PLAN §1.1

Checked on 2026-10-05 at commit `3bf5447` with `./scripts/test.sh`: 845 tests in 73 suites, 0 failures.
P = proven by automated tests. PT = logic is tested, the screen or gesture is not. M = only a person can check it.
"Click" says what to do by hand. Test names are `Suite.test`.

| # | Line | Proof | Test names / what to click |
|---|------|-------|----------------------------|
| 1 | Install + Desktop icon | M | `~/Applications/Grove.app` exists, signed (`codesign -v` ok), `~/Desktop/Grove` links to it. Click: double-click the Desktop icon. |
| 2 | Custom icon | M | `AppIcon.icns` in the bundle, `CFBundleIconFile = AppIcon`. Look: Finder, Dock, Desktop. |
| 3 | Create block (drag, double-click, task drop) | PT | `PlannerStoreTests.draftCreatesTaskAndBlockAndUndoRemovesBoth`, `dropTaskFromTrayUsesEstimate`. Click: the three gestures. |
| 4 | Move, 15-min grid | PT | `PlannerMathTests.snapsToNearestStepBothWays`, `theGridStepAndTheShortestBlockAreFifteenMinutes`. Click: drag a block. |
| 5 | Resize both edges, min 15 min | PT | `PlannerMathTests.resizeKeepsAFifteenMinuteMinimumOnBothEdges`. Click: drag top and bottom edge. |
| 6 | Overlap shown side by side | PT | `PlannerStoreTests.overlapIsAllowed`, `PlannerMathTests.chainOfOverlapsStepsDownOneLevelEach`. The layout is cascaded, not columns (see `docs/assumptions.md`). |
| 7 | Drag block to another day | PT | `PlannerStoreTests.movingTaskBlockToAnotherDayUpdatesTaskPlanDate`. Click: Week mode, drag sideways. |
| 8 | Live drag label | PT | `PlannerMathTests.labelFormatsDuration` ("11:15 – 12:45 · 1h 30m"). Click: watch it while dragging. |
| 9 | ⌘Z / ⇧⌘Z | PT | `PlannerStoreTests.moveAndResizeAreUndoable`, `rippleWithShiftPushesLaterBlocks`. Not tested: undo of unschedule, duplicate, split. |
| 10 | Keyboard moves | PT | `PlannerMathTests.steppingGoesToTheNextGridLine`, `PlannerStoreTests.duplicateSplitAndDuration`. Click: select a block, press the keys of §5.1.6. |
| 11 | ⇧ ripple | PT | `PlannerStoreTests.rippleWithShiftPushesLaterBlocks`, `PlannerMathTests.rippleCascadesThroughThreeBlocks`. Click: ⇧-drop. |
| 12 | Fit | P | `PlannerStoreTests.fitUsesFirstFreeGap`, `PlannerMathTests.firstFreeSlotFindsGap` |
| 13 | Quick add | P | `QuickAddParserTests.callMum`, `TaskStoreTests.quickAddMakesTaskAndBlockAndUndoRemovesAll` |
| 14 | Buckets, lists, tags, subtasks, repeats | P | `AllTasksTests.noDayYetRunsInboxThenWeeksThenSomeday`, `TaskStoreTests.addSubtask`, `completingARepeatingTaskMakesTheNextOne`, `InspectorOptionsTests.presetRules` |
| 15 | Calendar views, event repeats | PT | `RecurrenceTests`, `RecurringEventStoreTests.aWeeklyEventShowsOnEveryWeek`, `CalendarRulesTests.monthGridStartsOnTheMondayOfTheFirstWeek`. Click: Day, 3 Days, Week, Month. |
| 16 | Note editor | PT | `MarkdownSpansTests`, `EditorViewTests.boldWrapsTheSelection`, `NoteStoreTests.aTaskThatMentionsANoteIsABacklink`. Look: heading, bold, italic styles. |
| 17 | `- [ ]` makes a synced task | P | `NoteTaskStoreTests.openBoxesMakeTasksInOrderAndGetMarks`, `tickingTheBoxFinishesTheTaskAndClearingItReopensIt` |
| 18 | `@fri 9am` offers an event | P | `AtDateParserTests.aWeekdayAndATime`, `AtDateStoreTests.aPlainLineMakesAnHourLongEventLinkedToTheNote` |
| 19 | Daily and weekly notes | P | `NoteStoreTests.aDailyNoteIsMadeOnceFromTheTemplate`, `aWeeklyNoteUsesTheMonday`, `DayStoreTests.theAgendaHoldsEventsBlocksAndLooseTasks` |
| 20 | §5.5 links 1–12 | PT | `ReferenceIndexerTests`, `MeetingNoteTests`, `NoteDropTests`, `DayStoreTests`, `PaletteStoreTests`. Click: ⇧⌘T, drag a note to the grid, mood icons, weekly panel. |
| 21 | Four themes, light/dark | PT | `ThemeSpecTests.fourThemesInTheOrderOfThePlan`, `groveAndMinimalFollowTheSystem`, `ThemeStoreTests.theThemeIsLiveInTheStore`. Look: each theme, then macOS light/dark. |
| 22 | Motion toggle, Reduce Motion | PT | `ThemeSpecTests.motionNeedsTheSwitchAndNoReduceMotion`. Click: System Settings ▸ Accessibility ▸ Reduce Motion. |
| 23 | ⌘K full-text search | P | `PaletteStoreTests.aSearchFindsTasksEventsAndNotes`, `DatabaseTests.searchFindsWordsAndPrefixes` |
| 24 | Notifications | PT | `ReminderPlannerTests` (16), `ReminderStoreTests` (25) use a fake. Click: allow notifications, add a block about 6 minutes ahead. |
| 25 | Menu bar item | PT | `MenuBarTests.theNextBlockShowsHowLongItTakes`, `quickAddFromTheMenuBarGoesToToday`. Click: open the menu bar leaf. |
| 26 | Survive relaunch, backup, JSON | P / PT | `DatabaseTests.migrationsAreIdempotent`, `dailyBackupIsCreatedOnceAndTrimmed`, `DataExportTests.importGivesBackEverythingThatWasExported`. Click: Settings ▸ Data ▸ Export, change, Import. |
| 27 | `scripts/test.sh` passes | P | 845 / 845 |
| 28 | Today = today only; Planner = week only; Calendar = month only | P | `PlannerKindTests.todayShowsOnlyToday`, `weekShowsSevenDaysFromMonday`, `monthShowsTheSixWeekGrid` |
| 29 | Goals: weekly-hour recurring items, drag a goal into a day, tick to add hours. Migration 5 (goals table, events.goal_id, events.done_at) | P | `GoalStoreTests.draggingAGoalIntoADayMakesAGoalBlock`, `markingABlockDoneAddsItsHoursAndMarkingAgainTakesThemBack`, `GoalTests.upgradingAVersionFourDatabaseKeepsItsData` |
| 30 | Left dock: Notes, Tasks, Goals panels. One open at a time | P | `LeftPaneTests.aTapOnTheOpenPanelClosesIt`, `aTapOnAnotherPanelSwitchesToItSoOnlyOneIsOpen`, `onlyTodayAndThePlannerHaveTheButtons` |
| 31 | Tasks panel shows unscheduled + overdue only. Drop task on calendar moves it (one block, old slot removed) | PT | `AllTasksRulesTests.noDayYetRunsInboxThenWeeksThenSomeday`, `PlannerStoreTests.movingTaskBlockToAnotherDayUpdatesTaskPlanDate`. Click: drag task to another day. |
| 32 | "Time blocks" section removed from task panel | M | Click: select a task, look in the inspector. Time blocks are gone. |
| 33 | New task kept when clicked away (quick add and planner draft) | P | `InlineTitleRulesTests.textLeftInTheFieldIsKept`, `emptyOrBlankTextIsDropped`. Blur with non-empty text saves, empty text cancels. |
| 34 | Subtasks with name, description, duration, own done | P | `InspectorStoreTests.addingASubtaskReturnsItAndKeepsTheName`, `aSubtaskKeepsItsOwnDescriptionAndDuration`, `doneOnOneSubtaskLeavesTheOthersAndTheParentAlone` |

Not covered by any test: planner gestures and the key handler (lines 3, 4, 5, 7, 10, 11), the ⌘Z key itself, and all looks.
