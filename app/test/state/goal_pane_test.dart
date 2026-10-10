// Port of Tests/GroveTests/GoalPaneTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

GoalProgress hours(int done, int planned, int target) => GoalProgress(
  kind: GoalKind.hours,
  done: done,
  planned: planned,
  target: target,
);

GoalProgress sessions(int done, int planned, int target) => GoalProgress(
  kind: GoalKind.sessions,
  done: done,
  planned: planned,
  target: target,
);

// 2026-10-05 is a Monday.
const monday = DayKey('2026-10-05');
const wednesday = DayKey('2026-10-07');
const nextMonday = DayKey('2026-10-12');

GoalProgress week(AppStore s, String id) =>
    s.goalProgress(id, weekOf: wednesday, sundayFirst: false);

void main() {
  group('the text and numbers of the Goals panel', () {
    test('hours show halves and trim zeros', () {
      expect(GoalRules.hours(0), '0');
      expect(GoalRules.hours(30), '0.5');
      expect(GoalRules.hours(60), '1');
      expect(GoalRules.hours(150), '2.5');
      expect(GoalRules.hours(300), '5');
      expect(GoalRules.hours(15), '0.25');
      expect(GoalRules.hours(90), '1.5');
      expect(GoalRules.hours(45), '0.75');
      expect(GoalRules.hours(20), '0.33');
      expect(GoalRules.hours(2400), '40');
    });

    test('progress text is hours done over target', () {
      expect(GoalRules.progressText(hours(150, 240, 300)), '2.5 / 5 h done');
      expect(GoalRules.progressText(hours(0, 0, 300)), '0 / 5 h done');
      // Over target is fine.
      expect(GoalRules.progressText(hours(420, 420, 300)), '7 / 5 h done');
    });

    test('progress text is sessions done over target', () {
      expect(GoalRules.progressText(sessions(3, 4, 5)), '3 / 5 sessions done');
      expect(GoalRules.progressText(sessions(0, 0, 1)), '0 / 1 session done');
      expect(GoalRules.progressText(sessions(7, 7, 5)), '7 / 5 sessions done');
    });

    test('planned text counts every block of the week', () {
      expect(GoalRules.plannedText(hours(60, 240, 300)), '4 h planned');
      expect(GoalRules.plannedText(hours(0, 90, 300)), '1.5 h planned');
      expect(GoalRules.plannedText(sessions(0, 1, 3)), '1 session planned');
      expect(GoalRules.plannedText(sessions(1, 2, 3)), '2 sessions planned');
      expect(GoalRules.plannedText(hours(0, 0, 300)), 'Nothing planned yet');
    });

    test('target text is per week', () {
      expect(GoalRules.targetText(GoalKind.hours, 300), '5 h / week');
      expect(GoalRules.targetText(GoalKind.hours, 150), '2.5 h / week');
      expect(GoalRules.targetText(GoalKind.sessions, 3), '3 sessions / week');
      expect(GoalRules.targetText(GoalKind.sessions, 1), '1 session / week');
    });

    test('the kinds have short names', () {
      expect(GoalRules.kindName(GoalKind.hours), 'Hours');
      expect(GoalRules.kindName(GoalKind.sessions), 'Sessions');
    });

    test('the bar is solid for done, lighter for planned, stops at full', () {
      ({double done, double planned}) bar(int d, int p, int t) =>
          GoalRules.bar(hours(d, p, t));
      expect(bar(60, 150, 300), (done: 0.2, planned: 0.5));
      expect(bar(0, 0, 300), (done: 0.0, planned: 0.0));
      expect(bar(0, 360, 300), (done: 0.0, planned: 1.0));
      expect(bar(360, 360, 300), (done: 1.0, planned: 1.0));
      expect(bar(10, 10, 0), (done: 0.0, planned: 0.0));
      expect(bar(-5, -5, 300), (done: 0.0, planned: 0.0));
      expect(bar(2, 4, 5), (done: 0.4, planned: 0.8));
    });

    test('the week label says this week or names the days', () {
      const week = DayRange(DayKey('2026-10-05'), DayKey('2026-10-11'));
      expect(GoalRules.weekLabel(week, today: d('2026-10-09')), 'This week');
      expect(GoalRules.weekLabel(week, today: d('2026-10-05')), 'This week');
      expect(GoalRules.weekLabel(week, today: d('2026-10-11')), 'This week');
      expect(GoalRules.weekLabel(week, today: d('2026-10-12')), '5–11 Oct');
      expect(GoalRules.weekLabel(week, today: d('2026-09-30')), '5–11 Oct');
      const across = DayRange(DayKey('2026-09-28'), DayKey('2026-10-04'));
      expect(
        GoalRules.weekLabel(across, today: d('2026-10-09')),
        '28 Sep–4 Oct',
      );
    });

    test('the target stepper moves in half hours', () {
      expect(GoalRules.stepTarget(300, kind: GoalKind.hours, up: true), 330);
      expect(GoalRules.stepTarget(300, kind: GoalKind.hours, up: false), 270);
      // Never below half an hour.
      expect(
        GoalRules.stepTarget(
          GoalRules.targetStep,
          kind: GoalKind.hours,
          up: false,
        ),
        GoalRules.targetStep,
      );
      expect(
        GoalRules.stepTarget(
          GoalRules.maxTarget,
          kind: GoalKind.hours,
          up: true,
        ),
        GoalRules.maxTarget,
      );
      expect(GoalRules.defaultTarget, 300);
    });

    test('the session stepper moves by one', () {
      expect(GoalRules.stepTarget(3, kind: GoalKind.sessions, up: true), 4);
      expect(GoalRules.stepTarget(3, kind: GoalKind.sessions, up: false), 2);
      expect(GoalRules.stepTarget(1, kind: GoalKind.sessions, up: false), 1);
      expect(GoalRules.stepTarget(99, kind: GoalKind.sessions, up: true), 99);
    });

    test('a goal row reads as one sentence for a screen reader', () {
      expect(
        GoalRules.accessibilityText('Read', hours(150, 240, 300)),
        'Read, 2.5 / 5 h done, 4 h planned',
      );
      expect(
        GoalRules.accessibilityText('Gym', sessions(0, 1, 3)),
        'Gym, 0 / 3 sessions done, 1 session planned',
      );
    });

    test('the duration menu offers four hours', () {
      expect(PlannerLimits.durationChoices, contains(240));
      expect(
        PlannerLimits.durationChoices,
        [...PlannerLimits.durationChoices]..sort(),
      );
    });
  });

  group('a goal dragged out of the panel', () {
    test('a goal payload is parsed back to its id', () {
      expect(DragPayload.goalPrefix, 'grove-goal:');
      expect(DragPayload.goal('ABC'), 'grove-goal:ABC');
      expect(DragPayload.goalId(DragPayload.goal('ABC')), 'ABC');
    });

    test('other payloads and text are not goals', () {
      expect(DragPayload.goalId(DragPayload.task('ABC')), isNull);
      expect(DragPayload.goalId(DragPayload.note('ABC')), isNull);
      expect(DragPayload.goalId('plain text'), isNull);
      expect(DragPayload.goalId('grove-goal:'), isNull); // no id
    });

    test('tasks and notes ignore a goal payload', () {
      final raw = DragPayload.goal('ABC');
      expect(raw.startsWith(DragPayload.taskPrefix), isFalse);
      expect(DragPayload.noteId(raw), isNull);
    });
  });

  group('drop a goal on the planner', () {
    test('drop, resize, add and next week', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read')!;

      // First drop: one hour by default. It counts at once.
      s.dropGoalOnPlanner(
        raw: DragPayload.goal(g.id),
        day: monday,
        minute: 600,
      );
      expect(week(s, g.id), hours(0, 60, 300));

      // A second block, made longer, the same week. The goal is still there.
      s.dropGoalOnPlanner(
        raw: DragPayload.goal(g.id),
        day: wednesday,
        minute: 840,
      );
      final second = s.selection.first;
      s.setDuration(blockIds: [second], minutes: 240);
      expect(week(s, g.id), hours(0, 300, 300));
      expect([for (final x in s.goals()) x.id], [g.id]);

      // Past the target is fine.
      s.dropGoalOnPlanner(
        raw: DragPayload.goal(g.id),
        day: wednesday,
        minute: 600,
      );
      expect(week(s, g.id).planned, 360);

      // Ticking a block moves it from planned to done.
      s.toggleGoalBlockDone(eventId: second);
      expect(week(s, g.id), hours(240, 360, 300));

      // A block next week does not count this week.
      s.dropGoalOnPlanner(
        raw: DragPayload.goal(g.id),
        day: nextMonday,
        minute: 600,
      );
      expect(week(s, g.id).planned, 360);
      expect(
        s.goalProgress(g.id, weekOf: nextMonday, sundayFirst: false).planned,
        60,
      );
    });

    test('a session goal counts each drop', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Gym', kind: GoalKind.sessions, target: 3)!;
      s.dropGoalOnPlanner(
        raw: DragPayload.goal(g.id),
        day: monday,
        minute: 480,
      );
      final id = s.selection.first;
      s.setDuration(blockIds: [id], minutes: 90);
      expect(week(s, g.id), sessions(0, 1, 3));
      s.dropGoalOnPlanner(
        raw: DragPayload.goal(g.id),
        day: wednesday,
        minute: 480,
      );
      expect(week(s, g.id).planned, 2);
    });

    test('a drop snaps to the minute it is given', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read')!;
      s.dropGoalOnPlanner(
        raw: DragPayload.goal(g.id),
        day: monday,
        minute: 615,
      );
      final e = s.repos.events.all().first;
      expect(e.start, const WallTime(day: monday, minute: 615));
      expect(e.durationMinutes, GoalRules.defaultBlockLength);
    });

    test('a drop that is not a goal or is gone does nothing', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read')!;
      bool drop(String raw) =>
          s.dropGoalOnPlanner(raw: raw, day: monday, minute: 600);
      expect(drop(DragPayload.task('x')), isFalse);
      expect(drop('hello'), isFalse);
      expect(drop(DragPayload.goal('gone')), isFalse);
      expect(s.repos.events.all(), isEmpty);
      expect(drop(DragPayload.goal(g.id)), isTrue);
      expect(s.repos.events.all().length, 1);
    });

    test('the progress numbers change the revision', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read')!;
      var seen = s.revision;
      s.dropGoalOnPlanner(
        raw: DragPayload.goal(g.id),
        day: monday,
        minute: 600,
      );
      expect(s.revision, greaterThan(seen));
      seen = s.revision;
      final id = s.selection.first;
      s.applyEdits(
        [BlockEdit(id: id, day: monday, start: 600, end: 720)],
        ripple: false,
        name: 'Resize Block',
      );
      expect(s.revision, greaterThan(seen));
    });

    test('a click on a goal block only selects it', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read')!;
      s.dropGoalOnPlanner(
        raw: DragPayload.goal(g.id),
        day: monday,
        minute: 600,
      );
      s.selection = {};
      final block = s.blocks(const DayRange.single(monday)).first;
      s.selectBlock(block, extend: false);
      expect(s.selection, {block.id});
      expect(s.selectedTaskId, isNull);
      expect(s.editingEvent, isNull);
    });
  });
}
