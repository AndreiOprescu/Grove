// Port of Tests/GroveTests/GoalStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Goals in the store: a weekly target of hours or sessions, blocks dragged
// into days. Every block in the week counts.

// 2026-10-05 is a Monday. The Monday-first week runs to Sunday 2026-10-11.
final monday = d('2026-10-05');
final sunday = d('2026-10-11');
final mondayOnly = DayRange.single(monday);

GoalProgress progress(AppStore s, String id, {bool sundayFirst = false}) =>
    s.goalProgress(id, weekOf: d('2026-10-07'), sundayFirst: sundayFirst);

GoalItem makeGoal(AppStore s, {String title = 'Read', int target = 300}) =>
    s.addGoal(title: title, target: target)!;

GoalProgress hours({int done = 0, required int planned, int target = 300}) =>
    GoalProgress(
      kind: GoalKind.hours,
      done: done,
      planned: planned,
      target: target,
    );

GoalProgress sessions({
  int done = 0,
  required int planned,
  required int target,
}) => GoalProgress(
  kind: GoalKind.sessions,
  done: done,
  planned: planned,
  target: target,
);

PlannerBlock? blockOn(AppStore s, String id) =>
    s.blocks(mondayOnly).where((b) => b.id == id).firstOrNull;

void main() {
  group('GoalStore', () {
    // Goals

    test('adding a goal saves it and lists it in order', () {
      final s = makeStore();
      final a = makeGoal(s, title: 'Read', target: 360);
      final b = makeGoal(s, title: 'Run', target: 120);
      expect(a.targetMin, 360);
      expect(a.title, 'Read');
      expect(a.color, '');
      expect(a.kind, GoalKind.hours);
      expect(s.goals().map((g) => g.title), ['Read', 'Run']);
      expect(b.sort, greaterThan(a.sort));
      expect(s.undoName, 'New Goal');
    });

    test('a goal without a title is not added', () {
      final s = makeStore();
      expect(s.addGoal(title: '   ', target: 300), isNull);
      expect(s.goals(), isEmpty);
      expect(s.undoName, isNull);
    });

    test(
      'the title is trimmed and the target stays inside sensible limits',
      () {
        final s = makeStore();
        final a = makeGoal(s, title: '  Read  ', target: 0);
        final b = makeGoal(s, title: 'Run', target: 99999);
        expect(a.title, 'Read');
        expect(a.targetMin, GoalRules.minTarget);
        expect(b.targetMin, GoalRules.maxTarget);
      },
    );

    test('a session goal keeps its count and the default hours', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Gym', kind: GoalKind.sessions, target: 4)!;
      expect(g.kind, GoalKind.sessions);
      expect(g.targetCount, 4);
      expect(g.targetMin, GoalRules.defaultTarget);
      final swim = s.addGoal(title: 'Swim', kind: GoalKind.sessions)!;
      expect(swim.targetCount, GoalRules.defaultCount);
      final low = s.addGoal(title: 'Yoga', kind: GoalKind.sessions, target: 0)!;
      final high = s.addGoal(
        title: 'Walk',
        kind: GoalKind.sessions,
        target: 500,
      )!;
      expect(low.targetCount, GoalRules.minCount);
      expect(high.targetCount, GoalRules.maxCount);
    });

    test('changing the kind and count is one undo step each', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.updateGoal(g.id, kind: GoalKind.sessions);
      expect(s.goal(g.id)?.kind, GoalKind.sessions);
      expect(s.undoName, 'Edit Goal');
      s.updateGoal(g.id, targetCount: 5);
      expect(s.goal(g.id)?.targetCount, 5);
      s.updateGoal(g.id, targetCount: 1000);
      expect(s.goal(g.id)?.targetCount, GoalRules.maxCount);
      s.undo();
      expect(s.goal(g.id)?.targetCount, 5);
      s.undo();
      expect(s.goal(g.id)?.targetCount, 3);
      s.undo();
      expect(s.goal(g.id)?.kind, GoalKind.hours);
    });

    test('adding a goal bumps the revision', () {
      final s = makeStore();
      final before = s.revision;
      makeGoal(s);
      expect(s.revision, greaterThan(before));
    });

    test('adding a goal can be undone and redone', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.undo();
      expect(s.goals(), isEmpty);
      expect(s.repos.goals.get(g.id), isNull);
      s.redo();
      expect(s.goals().map((x) => x.id), [g.id]);
      expect(s.repos.goals.get(g.id)?.targetMin, 300);
    });

    test('updating a goal changes only what is given and can be undone', () {
      final s = makeStore();
      final g = makeGoal(s, title: 'Read', target: 300);
      s.updateGoal(g.id, title: 'Read books', color: 'teal', targetMin: 420);
      final now = s.goal(g.id)!;
      expect(now.title, 'Read books');
      expect(now.targetMin, 420);
      expect(now.color, 'teal');
      expect(now.notes, '');
      s.updateGoal(g.id, notes: 'Novels');
      expect(s.goal(g.id)?.notes, 'Novels');
      expect(s.goal(g.id)?.title, 'Read books');
      s.undo();
      expect(s.goal(g.id)?.notes, '');
      s.undo();
      expect(s.goal(g.id)?.title, 'Read');
      expect(s.goal(g.id)?.targetMin, 300);
      expect(s.goal(g.id)?.color, '');
      s.redo();
      expect(s.goal(g.id)?.title, 'Read books');
    });

    test('a colour that is not one of the eight is ignored', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.updateGoal(g.id, color: 'mauve');
      expect(s.goal(g.id)?.color, '');
      s.updateGoal(g.id, title: '   ');
      expect(s.goal(g.id)?.title, 'Read');
    });

    test('an archived goal leaves the list but keeps its blocks', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      s.updateGoal(g.id, archived: true);
      expect(s.goals(), isEmpty);
      expect(s.goals(includeArchived: true).length, 1);
      expect(s.blocks(mondayOnly).length, 1);
    });

    // Scheduling

    test('dragging a goal into a day makes a goal block', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.updateGoal(g.id, color: 'teal');
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 90);
      final e = s.repos.events.all().first;
      expect(e.kind, EventKind.block);
      expect(e.goalId, g.id);
      expect(e.doneAt, isNull);
      expect(e.taskId, isNull);
      expect(e.title, 'Read');
      expect(e.color, 'teal');
      expect(e.start, WallTime(day: monday, minute: 600));
      expect(e.end, WallTime(day: monday, minute: 690));
      expect(s.selection, {e.id});
      expect(s.repos.tasks.all(), isEmpty); // a goal block has no task
    });

    test('a goal without a colour gives the block the accent colour', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      expect(s.repos.events.all().first.color, 'accent');
    });

    test('the default block length is one hour', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      expect(s.repos.events.all().first.durationMinutes, 60);
    });

    test('a block dropped near midnight is moved up to fit the day', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 1430, length: 60);
      final e = s.repos.events.all().first;
      expect(e.end.minute, lessThanOrEqualTo(1440));
      expect(e.durationMinutes, 60);
      expect(e.start.day, monday);
      expect(e.end.day, monday);
    });

    test('scheduling a goal can be undone and redone', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      expect(s.undoName, 'Schedule Goal');
      s.undo();
      expect(s.repos.events.all(), isEmpty);
      s.redo();
      expect(s.repos.events.all().length, 1);
      expect(s.goal(g.id), isNotNull);
    });

    test('scheduling a goal that is gone does nothing', () {
      final s = makeStore();
      s.scheduleGoal(goalId: 'nope', day: monday, start: 600);
      expect(s.repos.events.all(), isEmpty);
    });

    test('the goal stays and another block can be added in the same week', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      s.scheduleGoal(
        goalId: g.id,
        day: monday.adding(days: 2),
        start: 600,
        length: 30,
      );
      expect(s.repos.events.all().length, 2);
      expect(s.goals().length, 1);
      expect(progress(s, g.id).planned, 90);
    });

    // Progress

    test('a new goal has no progress and shows its target', () {
      final s = makeStore();
      final g = makeGoal(s, target: 300);
      expect(progress(s, g.id), hours(planned: 0));
    });

    test('a block counts as soon as it is in the week', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 120);
      expect(progress(s, g.id), hours(planned: 120));
      expect(s.repos.events.all().first.doneAt, isNull);
    });

    test('a session goal counts one for each block', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Gym', kind: GoalKind.sessions, target: 2)!;
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 30);
      s.scheduleGoal(goalId: g.id, day: sunday, start: 600, length: 240);
      expect(progress(s, g.id), sessions(planned: 2, target: 2));
      s.scheduleGoal(goalId: g.id, day: sunday, start: 900, length: 60);
      expect(progress(s, g.id).planned, 3); // over the target is fine
    });

    test('switching the kind keeps the blocks and changes what is counted', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 90);
      s.scheduleGoal(goalId: g.id, day: monday, start: 800, length: 30);
      expect(progress(s, g.id), hours(planned: 120));
      s.updateGoal(g.id, kind: GoalKind.sessions);
      expect(progress(s, g.id), sessions(planned: 2, target: 3));
      expect(s.repos.events.all().length, 2);
    });

    test('hours can go over the target', () {
      final s = makeStore();
      final g = makeGoal(s, target: 60);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 240);
      expect(progress(s, g.id).planned, 240);
    });

    test('ticking a goal block moves it from planned to done', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 90);
      s.scheduleGoal(goalId: g.id, day: monday, start: 800, length: 30);
      final id = s.selection.first;
      s.toggleGoalBlockDone(eventId: id);
      expect(progress(s, g.id), hours(done: 30, planned: 120));
      expect(blockOn(s, id)?.isDone, isTrue);
      expect(s.undoName, 'Complete Goal Block');
      s.toggleGoalBlockDone(eventId: id);
      expect(progress(s, g.id).done, 0);
      expect(blockOn(s, id)?.isDone, isFalse);
    });

    test('ticking is one undo step', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60);
      final id = s.selection.first;
      s.toggleGoalBlockDone(eventId: id);
      s.undo();
      expect(progress(s, g.id).done, 0);
      s.redo();
      expect(progress(s, g.id).done, 60);
    });

    test('a session goal counts done blocks', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Gym', kind: GoalKind.sessions, target: 3)!;
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 30);
      final id = s.selection.first;
      s.scheduleGoal(goalId: g.id, day: sunday, start: 600, length: 240);
      s.toggleGoalBlockDone(eventId: id);
      expect(progress(s, g.id), sessions(done: 1, planned: 2, target: 3));
    });

    test('ticking does nothing on a block without a goal', () {
      final s = makeStore();
      final e = EventItem(
        title: 'Lunch',
        start: WallTime(day: monday, minute: 720),
        end: WallTime(day: monday, minute: 780),
      );
      s.repos.events.save(e);
      s.toggleGoalBlockDone(eventId: e.id);
      expect(s.repos.events.get(e.id)?.doneAt, isNull);
      expect(s.undoName, isNull);
    });

    test('a goal stays in the list when all its blocks are done', () {
      final s = makeStore();
      final g = makeGoal(s, target: 60);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60);
      s.toggleGoalBlockDone(eventId: s.selection.first);
      expect(progress(s, g.id).done, 60);
      expect(s.goals().map((x) => x.id), [g.id]);
    });

    test('a duplicate of a done block is planned, not done', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60);
      final id = s.selection.first;
      s.toggleGoalBlockDone(eventId: id);
      s.duplicate(blockIds: [id]);
      expect(progress(s, g.id), hours(done: 60, planned: 120));
    });

    test('resizing a block changes the hours', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60);
      final id = s.selection.first;
      s.applyEdits(
        [BlockEdit(id: id, day: monday, start: 600, end: 750)],
        ripple: false,
        name: 'Resize Block',
      );
      expect(progress(s, g.id).planned, 150);
      s.applyEdits(
        [BlockEdit(id: id, day: monday, start: 600, end: 630)],
        ripple: false,
        name: 'Resize Block',
      );
      expect(progress(s, g.id).planned, 30);
    });

    test('a new week starts at zero by itself', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60);
      expect(
        s.goalProgress(g.id, weekOf: d('2026-10-14'), sundayFirst: false),
        hours(planned: 0),
      );
      expect(
        s
            .goalProgress(g.id, weekOf: d('2026-09-30'), sundayFirst: false)
            .planned,
        0,
      );
    });

    test('moving a block to another week moves its hours', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60);
      final id = s.selection.first;
      final later = monday.adding(days: 7);
      s.applyEdits(
        [BlockEdit(id: id, day: later, start: 600, end: 660)],
        ripple: false,
        name: 'Move Block',
      );
      expect(progress(s, g.id).planned, 0);
      expect(
        s.goalProgress(g.id, weekOf: later, sundayFirst: false).planned,
        60,
      );
    });

    test('the week runs Monday to Sunday or Sunday to Saturday', () {
      final s = makeStore();
      final g = makeGoal(s);
      final sundayBefore = monday.adding(days: -1); // 2026-10-04
      s.scheduleGoal(goalId: g.id, day: sundayBefore, start: 600, length: 60);
      s.scheduleGoal(goalId: g.id, day: sunday, start: 600, length: 30);
      // Monday first: 10-04 belongs to the week before, 10-11 closes this one.
      expect(progress(s, g.id, sundayFirst: false).planned, 30);
      // Sunday first: 10-04 opens this week, 10-11 opens the next.
      expect(progress(s, g.id, sundayFirst: true).planned, 60);
      expect(
        s
            .goalProgress(g.id, weekOf: d('2026-10-12'), sundayFirst: true)
            .planned,
        30,
      );
    });

    // Swift reads `UserDefaults.standard`. Here the store has its own Prefs.
    test('the week setting is read from the same key as the planner', () {
      const key = 'calendar.weekStartsSunday';
      final prefs = MemoryPrefs();
      final s = makeStore(prefs: prefs);
      final g = makeGoal(s);
      s.scheduleGoal(
        goalId: g.id,
        day: monday.adding(days: -1),
        start: 600,
        length: 60,
      );
      prefs.set(key, false);
      expect(s.goalProgress(g.id, weekOf: d('2026-10-07')).planned, 0);
      prefs.set(key, true);
      expect(s.goalProgress(g.id, weekOf: d('2026-10-07')).planned, 60);
    });

    // Deleting a goal

    test('deleting a goal keeps its blocks as plain blocks', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60);
      s.scheduleGoal(goalId: g.id, day: monday, start: 720, length: 60);
      s.deleteGoal(g.id);
      expect(s.goals(), isEmpty);
      expect(s.goal(g.id), isNull);
      final events = s.repos.events.all();
      expect(events.length, 2);
      expect(
        events.every((e) => e.goalId == null && e.kind == EventKind.block),
        isTrue,
      );
      expect(s.blocks(mondayOnly).length, 2);
      expect(
        s.blocks(mondayOnly).every((b) => b.goalId == null && !b.isDone),
        isTrue,
      );
    });

    test('deleting a goal can be undone and the blocks come back to it', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60);
      final id = s.selection.first;
      s.deleteGoal(g.id);
      expect(s.undoName, 'Delete Goal');
      s.undo();
      expect(s.goal(g.id)?.title, 'Read');
      expect(s.repos.events.get(id)?.goalId, g.id);
      expect(progress(s, g.id).planned, 60);
      s.redo();
      expect(s.goal(g.id), isNull);
      expect(s.repos.events.get(id)?.goalId, isNull);
    });

    // Planner

    test('a goal block counts as planned time but not as a task', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60);
      s.createFromDraft(
        title: 'Write',
        day: monday,
        start: 720,
        end: 780,
        asEvent: false,
      );
      final totals = s.dayTotals(
        monday,
        blocks: s.blocks(mondayOnly),
        workStart: 540,
        workEnd: 1020,
      );
      expect(totals.planned, 120);
      expect(totals.total, 1); // only the task block
      expect(totals.done, 0);
      expect(s.plannedMinutes(monday), 120);
    });

    test('duplicating a goal block adds its hours again', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60);
      final id = s.selection.first;
      s.duplicate(blockIds: [id]);
      final events = s.repos.events.all();
      expect(events.length, 2);
      expect(events.every((e) => e.goalId == g.id), isTrue);
      expect(progress(s, g.id).planned, 120);
    });

    test('splitting a goal block keeps the hours and adds a session', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 120);
      final id = s.selection.first;
      s.split(blockId: id);
      expect(progress(s, g.id).planned, 120);
      s.updateGoal(g.id, kind: GoalKind.sessions);
      expect(progress(s, g.id).planned, 2);
    });

    test('deleting a goal block removes its hours', () {
      final s = makeStore();
      final g = makeGoal(s);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60);
      final id = s.selection.first;
      s.deleteBlocks([id]);
      expect(progress(s, g.id).planned, 0);
      expect(s.goal(g.id), isNotNull);
    });
  });

  // The small rules behind goals.
  group('GoalRules', () {
    test('a target stays between one step and a week', () {
      expect(GoalRules.clampTarget(0), 15);
      expect(GoalRules.clampTarget(-30), 15);
      expect(GoalRules.clampTarget(300), 300);
      expect(GoalRules.clampTarget(100000), 10080);
    });

    test('the week is seven days from Monday or from Sunday', () {
      final wednesday = d('2026-10-07');
      final monday = GoalRules.week(wednesday, sundayFirst: false);
      expect(monday.first, d('2026-10-05'));
      expect(monday.last, d('2026-10-11'));
      final sunday = GoalRules.week(wednesday, sundayFirst: true);
      expect(sunday.first, d('2026-10-04'));
      expect(sunday.last, d('2026-10-10'));
    });

    test('a Sunday closes a Monday week and opens a Sunday week', () {
      final day = d('2026-10-11');
      expect(GoalRules.week(day, sundayFirst: false).first, d('2026-10-05'));
      expect(GoalRules.week(day, sundayFirst: true).first, day);
    });

    test('a count stays between one and ninety-nine', () {
      expect(GoalRules.clampCount(0), 1);
      expect(GoalRules.clampCount(3), 3);
      expect(GoalRules.clampCount(500), 99);
      expect(GoalRules.defaultCount, 3);
    });

    test('the target of a goal is its hours or its count', () {
      final g = GoalItem(title: 'x', targetMin: 240);
      expect(GoalRules.target(g), 240);
      expect(
        GoalRules.target(g.copyWith(kind: GoalKind.sessions, targetCount: 4)),
        4,
      );
    });

    test('a block uses the goal colour or the accent', () {
      expect(GoalRules.blockColor(GoalItem(title: 'x')), 'accent');
      expect(GoalRules.blockColor(GoalItem(title: 'x', color: 'teal')), 'teal');
    });
  });
}
