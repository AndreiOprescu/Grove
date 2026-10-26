import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// "Reorganise rest of day": the open tasks and goal blocks of today go after
// now, in one undo step. Each one can say how much of it is done.

// 2026-10-26 is a Monday. Now is 10:30.
final today = d('2026-10-26');

AppStore store({int now = 630}) => makeStore(
  clock: WallTime(day: today, minute: now),
);

TaskItem addTask(
  AppStore s,
  String title, {
  int estimate = 30,
  String? due,
  RecurrenceRule? recurrence,
}) {
  final t = TaskItem(
    title: title,
    bucket: TaskBucket.day,
    planDate: today,
    estimateMin: estimate,
    due: due,
    recurrence: recurrence,
  );
  s.repos.tasks.save(t);
  return t;
}

EventItem addBlock(AppStore s, TaskItem t, int start, int end) {
  final e = s.blockEvent(t, day: today, start: start, end: end);
  s.repos.events.save(e);
  return e;
}

EventItem addEvent(
  AppStore s,
  String title,
  int start,
  int end, {
  EventKind kind = EventKind.event,
  bool allDay = false,
  bool isDeadline = false,
  RecurrenceRule? recurrence,
}) {
  final e = EventItem(
    title: title,
    start: WallTime(day: today, minute: start),
    end: WallTime(day: today, minute: end),
    kind: kind,
    allDay: allDay,
    isDeadline: isDeadline,
    recurrence: recurrence,
  );
  s.repos.events.save(e);
  return e;
}

/// A goal "Read" with a block from [start], [length] minutes long. Gives the
/// goal and the id of the block.
(GoalItem, String) addGoalBlock(AppStore s, int start, int length) {
  final g = s.addGoal(title: 'Read', target: 300)!;
  s.scheduleGoal(goalId: g.id, day: today, start: start, length: length);
  return (g, s.selection.single);
}

/// The stored blocks of a task today, earliest first.
List<EventItem> blocksOf(AppStore s, String taskId) => [
  for (final e in s.blocksOfTask(taskId))
    if (e.start.day == today) e,
];

(int, int) at(EventItem e) => (e.start.minute, e.end.minute);

void main() {
  group('the input', () {
    test('lists the open tasks of today and the goal blocks', () {
      final s = store();
      final a = addTask(s, 'Blocked', estimate: 45);
      addBlock(s, a, 540, 600);
      addBlock(s, a, 700, 730);
      final b = addTask(s, 'Timeless', estimate: 30, due: '2026-10-28');
      final done = addTask(s, 'Done');
      addBlock(s, done, 480, 510);
      s.toggleDone(taskId: done.id);
      final (_, goalBlock) = addGoalBlock(s, 800, 60);
      final meeting = addEvent(s, 'Meeting', 660, 690);
      addEvent(s, 'Holiday', 0, 1440, allDay: true);
      s.addDayMarker(DayMarkerKind.sleep, today, at: 1320);

      final input = s.replanInput();
      expect(input.day, today);
      expect(input.now, 630);
      expect(input.until, 1320);
      final byId = {for (final i in input.items) i.id: i};
      expect(byId.keys, unorderedEquals([a.id, b.id, goalBlock]));
      expect(byId[a.id]!.base, 90);
      expect(byId[a.id]!.group, ReplanGroup.task);
      expect(byId[a.id]!.blocks.map((x) => x.start), [540, 700]);
      expect(byId[b.id]!.base, 30);
      expect(byId[b.id]!.group, ReplanGroup.deadline);
      expect(byId[b.id]!.blocks, isEmpty);
      expect(byId[goalBlock]!.group, ReplanGroup.goal);
      expect(byId[goalBlock]!.base, 60);
      expect(byId[goalBlock]!.title, 'Read · 13:20');
      final fixed = {for (final f in input.fixed) f.id};
      expect(fixed, contains(meeting.id));
      expect(fixed, contains(s.blocksOfTask(done.id).single.id));
      expect(fixed.length, 2);
    });

    test('two blocks of one goal have the time in their name', () {
      final s = store();
      final g = s.addGoal(title: 'Spanish', target: 300)!;
      s.scheduleGoal(goalId: g.id, day: today, start: 540, length: 30);
      s.scheduleGoal(goalId: g.id, day: today, start: 960, length: 30);
      expect(
        s.replanInput().items.map((i) => i.title),
        unorderedEquals(['Spanish · 09:00', 'Spanish · 16:00']),
      );
    });

    test('an event from yesterday that runs into today is busy', () {
      final s = store(now: 20);
      final late = EventItem(
        title: 'Party',
        start: WallTime(day: today.adding(days: -1), minute: 1320),
        end: WallTime(day: today, minute: 120),
        kind: EventKind.activity,
      );
      s.repos.events.save(late);
      final t = addTask(s, 'Write', estimate: 30);

      final input = s.replanInput();
      expect(input.items.map((i) => i.id), [t.id]);
      expect(input.fixed, [Span(id: late.id, start: 0, end: 120)]);
      s.applyReplan(const {});
      expect(at(blocksOf(s, t.id).single), (120, 150));
      expect(s.event(late.id), late);
    });

    test('the minute to plan from can be given', () {
      final s = store();
      expect(s.replanInput(now: 884).from, 885);
      final t = addTask(s, 'Write', estimate: 30);
      s.applyReplan(const {}, now: 884);
      expect(at(blocksOf(s, t.id).single), (885, 915));
    });

    test('with no sleep line the plan runs to midnight', () {
      final s = store();
      expect(s.replanInput().until, 1440);
    });
  });

  group('applying', () {
    test('puts each one after now, and one undo puts all back', () {
      final s = store();
      addEvent(s, 'Meeting', 630, 690);
      final a = addTask(s, 'A', estimate: 60);
      final aBlock = addBlock(s, a, 540, 600);
      final b = addTask(s, 'B', estimate: 30, due: '2026-10-26');
      final tasksBefore = s.repos.tasks.all();

      s.applyReplan(const {});

      // The deadline first, then the other task.
      expect(at(blocksOf(s, b.id).single), (690, 720));
      final moved = blocksOf(s, a.id).single;
      expect(moved.id, aBlock.id);
      expect(at(moved), (720, 780));
      expect(s.undoName, 'Reorganise Day');
      expect(s.toast, 'Placed 2');

      s.undo();
      expect(at(blocksOf(s, a.id).single), (540, 600));
      expect(blocksOf(s, b.id), isEmpty);
      expect(s.repos.tasks.all(), tasksBefore);
    });

    test(
      '100% checks the task off, and a repeating task gets its next copy',
      () {
        final s = store();
        final r = addTask(
          s,
          'Stretch',
          recurrence: RecurrenceRule(freq: Freq.daily),
        );
        final block = addBlock(s, r, 540, 570);

        s.applyReplan({r.id: 100});

        expect(s.task(r.id)!.isDone, isTrue);
        expect(at(s.event(block.id)!), (540, 570));
        final next = s.repos.tasks.all().where(
          (t) => t.title == 'Stretch' && t.id != r.id,
        );
        expect(next.single.status, TaskStatus.open);
        expect(next.single.planDate, today.adding(days: 1));
        s.undo();
        expect(s.task(r.id)!.isDone, isFalse);
        expect(s.repos.tasks.all().length, 1);
      },
    );

    test(
      'a part done keeps the worked part and plans a block for the rest',
      () {
        final s = store();
        addEvent(s, 'Call', 630, 660);
        final p = addTask(s, 'Grove', estimate: 60);
        final block = addBlock(s, p, 600, 660);

        s.applyReplan({p.id: 50});

        final all = blocksOf(s, p.id);
        expect(all.length, 2);
        final record = all.firstWhere((e) => e.id == block.id);
        expect(at(record), (600, 630));
        expect(record.doneAt, isNotNull);
        final rest = all.firstWhere((e) => e.id != block.id);
        expect(at(rest), (660, 690));
        expect(rest.doneAt, isNull);
        expect(rest.taskId, p.id);
        expect(s.task(p.id)!.estimateMin, 30);
        expect(s.task(p.id)!.isDone, isFalse);

        // A second run leaves the worked part alone: only the rest counts.
        final again = s.replanInput();
        expect(again.items.single.base, 30);
        expect(again.items.single.blocks.single.id, rest.id);
        expect({for (final f in again.fixed) f.id}, contains(record.id));
        s.applyReplan({p.id: 0});
        // The rest is in the first free place already: nothing to change.
        expect(s.event(record.id), record);
        expect(at(s.event(rest.id)!), (660, 690));
        expect(s.undoStack.length, 1);

        s.undo();
        expect(at(s.event(block.id)!), (600, 660));
        expect(s.event(block.id)!.doneAt, isNull);
        expect(blocksOf(s, p.id).length, 1);
        expect(s.task(p.id)!.estimateMin, 60);
      },
    );

    test(
      'a task whose rest block is gone is back in the list and the plan',
      () {
        final s = store(now: 840);
        final p = addTask(s, 'Grove', estimate: 60);
        addBlock(s, p, 540, 600);
        s.applyReplan({p.id: 80});
        final rest = blocksOf(s, p.id).firstWhere((e) => e.doneAt == null);
        expect(at(rest), (840, 855));

        s.deleteBlocks([rest.id]);

        expect(ids(s.timeless([today])[today]!), [p.id]);
        expect(ids(s.unscheduled(today)), contains(p.id));
        final again = s.replanInput().items.single;
        expect(again.id, p.id);
        expect(again.base, 15);
        expect(again.blocks, isEmpty);
      },
    );

    test('a goal block done in part: the open subtasks go to the rest', () {
      final s = store();
      final (g, blockId) = addGoalBlock(s, 600, 120);
      final open = s.addGoalSubtaskToBlock(blockId, title: 'Open')!;
      final done = s.addGoalSubtaskToBlock(blockId, title: 'Done')!;
      s.toggleGoalSubtask(done);
      final mine = s.addBlockSubtask(to: blockId, title: 'Mine')!;
      final ticked = s.addBlockSubtask(to: blockId, title: 'Ticked')!;
      s.toggleBlockSubtask(ticked);

      s.applyReplan({blockId: 50});

      // Half of two hours: the hour before now is the worked part.
      final record = s.event(blockId)!;
      expect(at(record), (570, 630));
      expect(record.doneAt, isNotNull);
      final rest = s.repos.events
          .blocksForGoal(g.id)
          .where((e) => e.id != blockId)
          .single;
      expect(at(rest), (630, 690));
      expect(rest.doneAt, isNull);
      expect(s.repos.goalSubtasks.get(open)!.eventId, rest.id);
      expect(s.repos.goalSubtasks.get(done)!.eventId, blockId);
      expect(s.repos.blockSubtasks.get(mine)!.eventId, rest.id);
      expect(s.repos.blockSubtasks.get(ticked)!.eventId, blockId);

      s.undo();
      expect(at(s.event(blockId)!), (600, 720));
      expect(s.event(blockId)!.doneAt, isNull);
      expect(s.repos.events.blocksForGoal(g.id).length, 1);
      expect(s.repos.goalSubtasks.get(open)!.eventId, blockId);
      expect(s.repos.blockSubtasks.get(mine)!.eventId, blockId);
    });

    test('the worked part of a goal block pays its points', () {
      final s = store();
      final skill = s.addSkill('Focus')!;
      final (g, blockId) = addGoalBlock(s, 600, 120);
      s.setGoalReward(goalId: g.id, skillId: skill, points: 60);

      s.applyReplan({blockId: 50});

      // Half of two hours worked: one hour of 60 points an hour.
      expect(s.skillPoints[skill], 60);
      s.undo();
      expect(s.skillPoints[skill] ?? 0, 0);
    });

    test('100% ticks a goal block where it is', () {
      final s = store();
      final (_, blockId) = addGoalBlock(s, 540, 60);
      s.applyReplan({blockId: 100});
      final e = s.event(blockId)!;
      expect(at(e), (540, 600));
      expect(e.doneAt, isNotNull);
    });

    test('a task that does not fit goes back to the list of today', () {
      final s = store();
      s.addDayMarker(DayMarkerKind.sleep, today, at: 660);
      final o = addTask(s, 'Big', estimate: 120);
      addBlock(s, o, 600, 720);

      s.applyReplan({o.id: 25});

      expect(blocksOf(s, o.id), isEmpty);
      expect(ids(s.timeless([today])[today]!), [o.id]);
      expect(s.task(o.id)!.estimateMin, 90);
      expect(s.toast, '1 did not fit');
    });

    test('a goal block that does not fit gives its subtasks back', () {
      final s = store();
      s.addDayMarker(DayMarkerKind.sleep, today, at: 660);
      final (g, blockId) = addGoalBlock(s, 600, 120);
      final open = s.addGoalSubtaskToBlock(blockId, title: 'Open')!;

      s.applyReplan({blockId: 25});

      final record = s.event(blockId)!;
      expect(at(record), (600, 630));
      expect(record.doneAt, isNotNull);
      expect(s.repos.events.blocksForGoal(g.id).length, 1);
      expect(s.repos.goalSubtasks.get(open)!.eventId, isNull);
    });

    test('a goal block at 0% that does not fit is removed', () {
      final s = store();
      s.addDayMarker(DayMarkerKind.sleep, today, at: 660);
      final (g, blockId) = addGoalBlock(s, 600, 120);
      final open = s.addGoalSubtaskToBlock(blockId, title: 'Open')!;
      s.selection = {blockId};

      s.applyReplan(const {});

      expect(s.event(blockId), isNull);
      expect(s.repos.events.blocksForGoal(g.id), isEmpty);
      expect(s.repos.goalSubtasks.get(open)!.eventId, isNull);
      expect(s.selection, isEmpty);
      s.undo();
      expect(s.event(blockId), isNotNull);
      expect(s.repos.goalSubtasks.get(open)!.eventId, blockId);
    });

    test('other items of the day do not move, and are busy', () {
      final s = store();
      final activity = addEvent(s, 'Lunch', 630, 660, kind: EventKind.activity);
      final deadline = addEvent(s, 'Report due', 660, 675, isDeadline: true);
      final allDay = addEvent(s, 'Holiday', 0, 1440, allDay: true);
      final repeating = addEvent(
        s,
        'Standup',
        675,
        690,
        recurrence: RecurrenceRule(freq: Freq.daily),
      );
      final finished = addTask(s, 'Finished');
      final finishedBlock = addBlock(s, finished, 690, 720);
      s.toggleDone(taskId: finished.id);
      final t = addTask(s, 'Write', estimate: 30);
      final before = {for (final e in s.repos.events.all()) e.id: e};

      s.applyReplan(const {});

      expect(at(blocksOf(s, t.id).single), (720, 750));
      final after = {for (final e in s.repos.events.all()) e.id: e};
      for (final e in [activity, deadline, allDay, repeating, finishedBlock]) {
        expect(after[e.id], before[e.id]);
      }
      expect(after.length, before.length + 1);
    });

    test('with nothing to do, nothing changes', () {
      final s = store();
      addEvent(s, 'Meeting', 630, 690);
      s.applyReplan(const {});
      expect(s.undoName, isNull);
    });
  });
}
