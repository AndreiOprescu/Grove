import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/goal_subtask.dart';

import 'sync_support.dart';

// The goal panel: one tap on a goal block shows its goal, its time, the
// progress of the week and the goal subtasks planned in it. A goal block
// holds only goal subtasks (ADR 0002). The block subtasks that goal blocks
// had move into their goals one time.

// 2026-10-05 is a Monday.
final monday = d('2026-10-05');
final tuesday = monday.adding(days: 1);

/// A goal "Read" with these subtasks. Gives the goal.
GoalItem goalWith(AppStore s, List<String> titles) {
  final g = s.addGoal(title: 'Read', target: 300)!;
  for (final t in titles) {
    expect(s.addGoalSubtask(to: g.id, title: t), isNotNull);
  }
  return g;
}

/// A block of the goal on Monday at 10:00. Gives its id.
String blockOf(AppStore s, GoalItem g, {DayKey? day, int start = 600}) {
  s.scheduleGoal(goalId: g.id, day: day ?? monday, start: start);
  return s.selection.single;
}

/// The subtask of the goal with this title, as the database has it now.
GoalSubtaskItem sub(AppStore s, GoalItem g, String title) =>
    s.goalSubtasks(g.id).firstWhere((x) => x.title == title);

/// A goal block that repeats each Monday from [monday], 10:00 to 11:00.
EventItem weekly(AppStore s, GoalItem g) {
  final e = EventItem(
    title: g.title,
    start: WallTime(day: monday, minute: 600),
    end: WallTime(day: monday, minute: 660),
    kind: EventKind.block,
    goalId: g.id,
    recurrence: RecurrenceRule(freq: Freq.weekly),
  );
  s.repos.events.save(e);
  return e;
}

void main() {
  group('The goal panel opens and closes', () {
    test('a tap on a goal block opens the goal panel and selects the block. '
        'No task panel opens', () {
      final s = makeStore();
      final g = goalWith(s, []);
      final id = blockOf(s, g);
      s.selection = {};
      final block = s.blocks(DayRange.single(monday)).single;

      s.selectBlock(block, extend: false);

      expect(s.selectedGoalBlockId, id);
      expect(s.selectedTaskId, isNull);
      expect(s.selection, {id});
    });

    test('a tap with the command key adds the block to the selection and '
        'leaves the panel alone', () {
      final s = makeStore();
      final g = goalWith(s, []);
      blockOf(s, g);
      s.selection = {};
      final block = s.blocks(DayRange.single(monday)).single;

      s.selectBlock(block, extend: true);

      expect(s.selectedGoalBlockId, isNull);
    });

    test('the goal panel and the task panel are never open at once', () {
      final s = makeStore();
      final g = goalWith(s, []);
      final id = blockOf(s, g);
      final task = s.quickAdd('Buy milk')!;

      s.openGoalPanel(id);
      s.selectedTaskId = task.id;
      expect(s.selectedGoalBlockId, isNull);

      s.openGoalPanel(id);
      expect(s.selectedTaskId, isNull);
      expect(s.selectedGoalBlockId, id);
    });

    test('a task block or a plain event does not open the goal panel', () {
      final s = makeStore();
      s.createFromDraft(
        title: 'Pay the bill',
        day: monday,
        start: 600,
        end: 660,
        asEvent: false,
      );
      final id = s.blocks(DayRange.single(monday)).single.id;

      s.openGoalPanel(id);

      expect(s.selectedGoalBlockId, isNull);
    });

    test('close closes it', () {
      final s = makeStore();
      final id = blockOf(s, goalWith(s, []));
      s.openGoalPanel(id);

      s.closeGoalPanel();

      expect(s.selectedGoalBlockId, isNull);
    });

    test('an import closes it', () {
      final s = makeStore();
      final id = blockOf(s, goalWith(s, []));
      s.openGoalPanel(id);

      s.resetAfterReplace();

      expect(s.selectedGoalBlockId, isNull);
    });

    test('"Edit goal" closes the panel, shows the Goals panel and asks it to '
        'open the editor of the goal', () {
      final s = makeStore();
      final g = goalWith(s, []);
      s.openGoalPanel(blockOf(s, g));
      s.leftPane = LeftPane.tasks;

      s.editGoalFromPanel(g.id);

      expect(s.selectedGoalBlockId, isNull);
      expect(s.leftPane, LeftPane.goals);
      expect(s.goalToEdit, g.id);
    });
  });

  group('A subtask planned from the panel', () {
    test('"+" on a subtask of the goal plans it in this block', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 1', 'Chapter 2']);
      final id = blockOf(s, g);

      expect(s.assignGoalSubtask(sub(s, g, 'Chapter 1').id, to: id), isTrue);

      expect(sub(s, g, 'Chapter 1').eventId, id);
      expect([for (final x in s.freeGoalSubtasks(id)) x.title], ['Chapter 2']);
    });

    test('a day of a repeating goal block becomes its own block, and the '
        'subtask goes in it. The series stays. One undo step', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 1']);
      final series = weekly(s, g);
      final day = OccurrenceId.make(series: series.id, day: monday);
      s.openGoalPanel(day);
      s.selection = {day};

      expect(s.freeGoalSubtasks(day), hasLength(1));
      expect(s.assignGoalSubtask(sub(s, g, 'Chapter 1').id, to: day), isTrue);

      final own = s
          .blocks(DayRange.single(monday))
          .singleWhere((b) => b.goalId == g.id);
      expect(OccurrenceId.parse(own.id), isNull);
      expect(sub(s, g, 'Chapter 1').eventId, own.id);
      expect(s.event(own.id)!.seriesId, series.id);
      // The next Monday is still a day of the series.
      final next = s.blocks(DayRange.single(monday.adding(days: 7))).single;
      expect(OccurrenceId.parse(next.id)?.series, series.id);
      // The panel and the selection follow the new block.
      expect(s.selectedGoalBlockId, own.id);
      expect(s.selection, {own.id});
      expect(s.undoName, 'Plan Subtask');

      s.undo();
      expect(sub(s, g, 'Chapter 1').eventId, isNull);
      expect(
        OccurrenceId.parse(s.blocks(DayRange.single(monday)).single.id),
        isNotNull,
      );
    });

    test('a new subtask from the panel goes in the goal and in this block', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 1']);
      final id = blockOf(s, g);

      final added = s.addGoalSubtaskToBlock(id, title: '  Chapter 2 ');

      expect(added, isNotNull);
      final x = sub(s, g, 'Chapter 2');
      expect(x.id, added);
      expect(x.eventId, id);
      expect(
        [for (final y in s.goalSubtasks(g.id)) y.title],
        ['Chapter 1', 'Chapter 2'],
      );
      expect(s.undoName, 'New Subtask');
      s.undo();
      expect(s.goalSubtasks(g.id), hasLength(1));
    });

    test('an empty name adds nothing', () {
      final s = makeStore();
      final g = goalWith(s, []);
      final id = blockOf(s, g);

      expect(s.addGoalSubtaskToBlock(id, title: '   '), isNull);
      expect(s.goalSubtasks(g.id), isEmpty);
    });

    test('a new subtask on a day of a repeating block splits that day off', () {
      final s = makeStore();
      final g = goalWith(s, []);
      final series = weekly(s, g);
      final day = OccurrenceId.make(series: series.id, day: monday);

      s.addGoalSubtaskToBlock(day, title: 'Chapter 1');

      final own = s.blocks(DayRange.single(monday)).single;
      expect(OccurrenceId.parse(own.id), isNull);
      expect(sub(s, g, 'Chapter 1').eventId, own.id);
    });

    test('unplan sends it back to the goal, still open. The block stays', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 1']);
      final id = blockOf(s, g);
      s.assignGoalSubtask(sub(s, g, 'Chapter 1').id, to: id);

      s.unassignGoalSubtask(sub(s, g, 'Chapter 1').id);

      expect(sub(s, g, 'Chapter 1').eventId, isNull);
      expect(sub(s, g, 'Chapter 1').isDone, isFalse);
      expect(s.event(id), isNotNull);
      expect(s.undoName, 'Unplan Subtask');
    });

    test('all subtasks ticked does not mark the block done', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 1']);
      final id = blockOf(s, g);
      s.assignGoalSubtask(sub(s, g, 'Chapter 1').id, to: id);

      s.toggleGoalSubtask(sub(s, g, 'Chapter 1').id);

      expect(s.event(id)!.doneAt, isNull);
    });
  });

  group('A subtask dropped on empty time', () {
    test('makes a new block of the goal, one hour long, with the subtask in '
        'it. One undo step', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 1']);
      final x = sub(s, g, 'Chapter 1');

      final done = s.dropGoalSubtaskOnPlanner(
        raw: DragPayload.goalSubtask(x.id),
        day: monday,
        minute: 13 * 60,
      );

      expect(done, isTrue);
      final block = s.blocks(DayRange.single(monday)).single;
      expect(block.goalId, g.id);
      expect(block.title, 'Read');
      expect(block.startMinute, 13 * 60);
      expect(block.endMinute, 14 * 60);
      expect(sub(s, g, 'Chapter 1').eventId, block.id);
      expect(s.selection, {block.id});
      expect(s.undoName, 'Plan Subtask');

      s.undo();
      expect(s.blocks(DayRange.single(monday)), isEmpty);
      expect(sub(s, g, 'Chapter 1').eventId, isNull);
    });

    test('a subtask that was in another block moves to the new one', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 1']);
      final first = blockOf(s, g);
      s.assignGoalSubtask(sub(s, g, 'Chapter 1').id, to: first);

      s.dropGoalSubtaskOnPlanner(
        raw: DragPayload.goalSubtask(sub(s, g, 'Chapter 1').id),
        day: tuesday,
        minute: 9 * 60,
      );

      final made = s.blocks(DayRange.single(tuesday)).single;
      expect(sub(s, g, 'Chapter 1').eventId, made.id);
      expect(s.plannedGoalSubtasks(first), isEmpty);
    });

    test('a done subtask, a gone subtask or other text adds nothing', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 1']);
      final x = sub(s, g, 'Chapter 1');
      s.toggleGoalSubtask(x.id);
      final undo = s.undoName;

      for (final raw in [
        DragPayload.goalSubtask(x.id),
        DragPayload.goalSubtask('gone'),
        'hello',
      ]) {
        expect(
          s.dropGoalSubtaskOnPlanner(raw: raw, day: monday, minute: 600),
          isFalse,
        );
      }
      expect(s.blocks(DayRange.single(monday)), isEmpty);
      expect(s.undoName, undo);
    });
  });

  group('A drop on a block that cannot take the subtask', () {
    test('a block of another goal or a task block says so, and nothing '
        'changes', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 1']);
      final gym = s.addGoal(title: 'Gym')!;
      final other = blockOf(s, gym);
      s.createFromDraft(
        title: 'Pay the bill',
        day: monday,
        start: 900,
        end: 960,
        asEvent: false,
      );
      final task = s
          .blocks(DayRange.single(monday))
          .firstWhere((b) => b.isTaskBlock)
          .id;
      final raw = DragPayload.goalSubtask(sub(s, g, 'Chapter 1').id);

      for (final id in [other, task]) {
        s.toast = null;
        expect(s.dropGoalSubtaskOnBlock(raw: raw, blockId: id), isFalse);
        expect(s.toast, 'Chapter 1 can go only in a block of Read.');
      }
      expect(sub(s, g, 'Chapter 1').eventId, isNull);
    });

    test('a drop on the block it is in says nothing', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 1']);
      final id = blockOf(s, g);
      s.assignGoalSubtask(sub(s, g, 'Chapter 1').id, to: id);
      s.toast = null;

      s.dropGoalSubtaskOnBlock(
        raw: DragPayload.goalSubtask(sub(s, g, 'Chapter 1').id),
        blockId: id,
      );

      expect(s.toast, isNull);
    });
  });

  group('Old block subtasks of goal blocks move into the goal', () {
    /// A database with a goal "Read" that has the subtask "Chapter 1", a
    /// single block of it on Monday with the block subtasks "Notes" (done)
    /// and "Quiz", and a weekly block with the block subtask "Review".
    ({Repos repos, GoalItem goal, EventItem single, EventItem weekly})
    oldData() {
      final repos = Repos(Database.inMemory());
      final g = GoalItem(title: 'Read');
      repos.goals.upsert(g);
      repos.goalSubtasks.save(
        GoalSubtaskItem(goalId: g.id, title: 'Chapter 1', sort: 1),
      );
      final single = EventItem(
        title: 'Read',
        start: WallTime(day: monday, minute: 600),
        end: WallTime(day: monday, minute: 660),
        kind: EventKind.block,
        goalId: g.id,
      );
      final repeat = EventItem(
        title: 'Read',
        start: WallTime(day: tuesday, minute: 600),
        end: WallTime(day: tuesday, minute: 660),
        kind: EventKind.block,
        goalId: g.id,
        recurrence: RecurrenceRule(freq: Freq.weekly),
      );
      repos.events
        ..save(single)
        ..save(repeat);
      repos.blockSubtasks
        ..save(
          BlockSubtaskItem(
            id: 'notes',
            eventId: single.id,
            title: 'Notes',
            sort: 1,
            doneAt: '2026-10-05T10:30:00',
          ),
        )
        ..save(
          BlockSubtaskItem(
            id: 'quiz',
            eventId: single.id,
            title: 'Quiz',
            sort: 2,
          ),
        )
        ..save(
          BlockSubtaskItem(
            id: 'review',
            eventId: repeat.id,
            title: 'Review',
            sort: 1,
          ),
        );
      return (repos: repos, goal: g, single: single, weekly: repeat);
    }

    test('at the start they become goal subtasks with the same ids, names, '
        'ticks and order, after the subtasks the goal had', () {
      final old = oldData();
      final s = makeStore(repos: old.repos);

      final list = s.goalSubtasks(old.goal.id);
      expect(
        [for (final x in list) x.title],
        ['Chapter 1', 'Notes', 'Quiz', 'Review'],
      );
      expect(sub(s, old.goal, 'Notes').id, 'notes');
      expect(sub(s, old.goal, 'Notes').isDone, isTrue);
      expect(sub(s, old.goal, 'Quiz').id, 'quiz');
      expect(sub(s, old.goal, 'Quiz').isDone, isFalse);
      expect(s.blockSubtasks(old.single.id), isEmpty);
      expect(s.blockSubtasks(old.weekly.id), isEmpty);
    });

    test('on a single block they stay planned in that block', () {
      final old = oldData();
      final s = makeStore(repos: old.repos);

      expect(sub(s, old.goal, 'Notes').eventId, old.single.id);
      expect(sub(s, old.goal, 'Quiz').eventId, old.single.id);
      expect(
        [
          for (final b in s.blocks(DayRange.single(monday)).single.subtasks)
            b.title,
        ],
        ['Notes', 'Quiz'],
      );
    });

    test('on a repeating block they go to the goal and are not planned', () {
      final old = oldData();
      final s = makeStore(repos: old.repos);

      expect(sub(s, old.goal, 'Review').eventId, isNull);
      expect(sub(s, old.goal, 'Review').isDone, isFalse);
    });

    test(
      'the move is not an undo step, and a second start changes nothing',
      () {
        final old = oldData();
        final s = makeStore(repos: old.repos);
        expect(s.undoName, isNull);
        final before = [for (final x in s.goalSubtasks(old.goal.id)) x.id];

        final again = makeStore(repos: old.repos);

        expect([for (final x in again.goalSubtasks(old.goal.id)) x.id], before);
      },
    );

    test('a plain block keeps its block subtasks', () {
      final repos = Repos(Database.inMemory());
      final plain = EventItem(
        title: 'Old goal',
        start: WallTime(day: monday, minute: 600),
        end: WallTime(day: monday, minute: 660),
        kind: EventKind.block,
      );
      repos.events.save(plain);
      repos.blockSubtasks.save(
        BlockSubtaskItem(eventId: plain.id, title: 'Step'),
      );

      final s = makeStore(repos: repos);

      expect(s.blockSubtasks(plain.id), hasLength(1));
    });

    test('after an import they move too', () {
      final old = oldData();
      final s = makeStore();
      final data = DataExport.export(old.repos.db);

      s.importData(data);

      final g = s.goals().single;
      expect(
        [for (final x in s.goalSubtasks(g.id)) x.title],
        ['Chapter 1', 'Notes', 'Quiz', 'Review'],
      );
      expect(s.blockSubtasks(old.single.id), isEmpty);
    });

    test('block subtasks that come in from another device move too, and '
        'both devices end with the same rows', () async {
      const me = 'me@example.com';
      final world = World();
      final a = world.device(), b = world.device();
      await signIn(a, me);
      await signIn(b, me);
      final g = goalWith(a.store, []);
      final block = blockOf(a.store, g);
      // An old version of Grove on device A still adds block subtasks to a
      // goal block.
      a.store.addBlockSubtask(to: block, title: 'Notes');
      final id = a.store.blockSubtasks(block).single.id;
      await a.store.syncNow();

      await b.store.syncNow();
      await idle(b.store);
      expect(b.store.blockSubtasks(block), isEmpty);
      expect(sub(b.store, g, 'Notes').id, id);
      expect(sub(b.store, g, 'Notes').eventId, block);

      await a.store.syncNow();
      expect(a.store.blockSubtasks(block), isEmpty);
      expect(sub(a.store, g, 'Notes').id, id);
      expect(a.store.goalSubtasks(g.id), hasLength(1));
    });
  });
}
