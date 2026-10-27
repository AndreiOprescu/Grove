// A block of the planner turns from a task into an activity, and back
// (owner, 2026-10-27). One undo step, and the block keeps its id, so its
// meeting note stays linked.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Never "today", so "now" does not change the slot math.
final day = DayKey.today().adding(days: 3);

EventItem? only(AppStore s) {
  final blocks = s.blocks(DayRange.single(day));
  return blocks.isEmpty ? null : s.event(blocks.single.id);
}

/// A task block of 10:00 to 11:00 on [day].
EventItem taskBlock(AppStore s, {String title = 'Write report'}) {
  s.createFromDraft(
    title: title,
    day: day,
    start: 600,
    end: 660,
    asEvent: false,
  );
  return s.event(s.selection.single)!;
}

/// An activity of 14:00 to 15:30 on [day].
EventItem activity(AppStore s, {String title = 'Gym'}) {
  s.createFromDraft(
    title: title,
    day: day,
    start: 840,
    end: 930,
    asEvent: false,
    asActivity: true,
  );
  return s.event(s.selection.single)!;
}

void main() {
  group('what can switch', () {
    test('a task block turns into an activity, an activity into a task', () {
      final s = makeStore();
      final t = taskBlock(s);
      final a = activity(s);
      expect(s.kindSwitch(t.id), EventKind.activity);
      expect(s.kindSwitch(a.id), EventKind.block);
    });

    test('not a plain event, a deadline, an all-day event or a goal block', () {
      final s = makeStore();
      s.createFromDraft(
        title: 'Call',
        day: day,
        start: 600,
        end: 630,
        asEvent: true,
      );
      final plain = s.selection.single;
      final allDay = EventItem(
        title: 'Trip',
        start: WallTime(day: day, minute: 0),
        end: WallTime(day: day.adding(days: 1), minute: 0),
        allDay: true,
        kind: EventKind.activity,
      );
      final deadline = EventItem(
        title: 'Form',
        start: WallTime(day: day, minute: 900),
        end: WallTime(day: day, minute: 900),
        isDeadline: true,
        kind: EventKind.activity,
      );
      s.repos.events
        ..save(allDay)
        ..save(deadline);
      final g = s.addGoal(title: 'Read', target: 300)!;
      s.scheduleGoal(goalId: g.id, day: day, start: 1000);
      final goalBlock = s
          .blocks(DayRange.single(day))
          .firstWhere((b) => b.goalId != null)
          .id;

      for (final id in [plain, allDay.id, deadline.id, goalBlock, 'gone']) {
        expect(s.kindSwitch(id), isNull, reason: id);
      }
    });

    test('not a repeating activity, nor one day of it', () {
      final s = makeStore();
      final e = EventItem(
        id: 'R1',
        title: 'Swim',
        start: WallTime(day: day, minute: 420),
        end: WallTime(day: day, minute: 480),
        kind: EventKind.activity,
        recurrence: RecurrenceRule(freq: Freq.weekly),
      );
      s.repos.events.save(e);
      final ids = [for (final b in s.blocks(DayRange.single(day))) b.id];
      expect(ids, isNotEmpty);
      for (final id in [e.id, ...ids]) {
        expect(s.kindSwitch(id), isNull, reason: id);
      }
    });

    test('not an activity that still has block subtasks', () {
      // It was a goal block and its goal was deleted: a task block would
      // hide those subtasks.
      final s = makeStore();
      final a = activity(s);
      s.repos.blockSubtasks.save(
        BlockSubtaskItem(eventId: a.id, title: 'Warm up'),
      );
      expect(s.kindSwitch(a.id), isNull);
    });

    test('not the block of a done task, nor of a repeating task', () {
      final s = makeStore();
      final done = taskBlock(s, title: 'Done one');
      s.toggleDone(taskId: done.taskId!);
      expect(s.task(done.taskId!)!.status, TaskStatus.done);
      expect(s.kindSwitch(done.id), isNull);

      final again = taskBlock(s, title: 'Every week');
      final t = s.task(again.taskId!)!;
      s.repos.tasks.save(
        t.copyWith(recurrence: RecurrenceRule(freq: Freq.weekly)),
      );
      expect(s.kindSwitch(again.id), isNull);
    });
  });

  group('a task block turns into an activity', () {
    test('the task goes with it: one undo step brings both back', () {
      final s = makeStore();
      final b = taskBlock(s);
      final taskId = b.taskId!;
      s.selectedTaskId = taskId;

      s.toggleKind(b.id);

      final e = s.event(b.id)!;
      expect(e.kind, EventKind.activity);
      expect(e.taskId, isNull);
      expect(e.title, 'Write report');
      expect(e.start, b.start);
      expect(e.end, b.end);
      expect(s.task(taskId), isNull);
      expect(s.repos.tasks.all(), isEmpty);
      expect(s.undoName, 'Turn into Activity');
      expect(s.selection, {b.id});
      expect(s.selectedTaskId, isNull);

      s.undo();
      expect(s.event(b.id)!.kind, EventKind.block);
      expect(s.event(b.id)!.taskId, taskId);
      expect(s.task(taskId)!.title, 'Write report');

      s.redo();
      expect(s.event(b.id)!.kind, EventKind.activity);
      expect(s.task(taskId), isNull);
    });

    test('the notes of the task are kept in the activity', () {
      final s = makeStore();
      final b = taskBlock(s);
      final t = s.task(b.taskId!)!;
      s.repos.tasks.save(t.copyWith(summary: 'For Ana', notes: 'Two pages'));
      s.repos.events.save(s.event(b.id)!.copyWith(notes: 'Room 4'));

      s.toggleKind(b.id);

      expect(s.event(b.id)!.notes, 'Room 4\n\nFor Ana\n\nTwo pages');
    });

    test('a task with more blocks stays: only this block changes', () {
      final s = makeStore();
      final b = taskBlock(s);
      final t = s.task(b.taskId!)!;
      final other = s.blockEvent(
        t,
        day: day.adding(days: 1),
        start: 600,
        end: 660,
      );
      s.repos.events.save(other);

      // The question about the loss is not asked: nothing is lost.
      expect(s.kindSwitchLoss(b.id), isNull);
      s.toggleKind(b.id);

      expect(s.event(b.id)!.kind, EventKind.activity);
      expect(s.event(b.id)!.taskId, isNull);
      expect(s.task(t.id), isNotNull);
      expect(s.blocksOfTask(t.id).map((e) => e.id), [other.id]);
      // The notes of the task stay with the task.
      expect(s.event(b.id)!.notes, '');
      s.undo();
      expect(s.blocksOfTask(t.id).length, 2);
    });

    test('a task with subtasks or points asks first, and loses them', () {
      final s = makeStore();
      final b = taskBlock(s);
      final taskId = b.taskId!;
      expect(s.kindSwitchLoss(b.id), isNull);

      final sub = s.addSubtask(to: taskId, title: 'Outline')!;
      expect(s.kindSwitchLoss(b.id), (subtasks: 1, rewards: 0));
      final skill = s.addSkill('Writing')!;
      s.setTaskReward(taskId: taskId, skillId: skill, points: 5);
      expect(s.kindSwitchLoss(b.id), (subtasks: 1, rewards: 1));

      s.toggleKind(b.id);
      expect(s.task(taskId), isNull);
      expect(s.task(sub), isNull);
      expect(s.taskRewards(taskId), isEmpty);
      expect(s.event(b.id)!.kind, EventKind.activity);

      s.undo();
      expect(s.task(sub)!.parentId, taskId);
      expect(s.taskRewards(taskId).length, 1);
    });

    test('the meeting note stays linked to the block', () {
      final s = makeStore();
      final b = taskBlock(s);
      final note = s.createMeetingNote(b)!;

      s.toggleKind(b.id);

      expect(s.meetingNote(s.event(b.id)!)?.id, note.id);
    });
  });

  group('an activity turns into a task', () {
    test('a new task on that day with its length and notes', () {
      final s = makeStore();
      final a = activity(s);
      s.repos.events.save(s.event(a.id)!.copyWith(notes: 'Bring shoes'));

      s.toggleKind(a.id);

      final e = s.event(a.id)!;
      expect(e.kind, EventKind.block);
      final t = s.task(e.taskId!)!;
      expect(t.title, 'Gym');
      expect(t.bucket, TaskBucket.day);
      expect(t.planDate, day);
      expect(t.estimateMin, 90);
      expect(t.notes, 'Bring shoes');
      expect(t.status, TaskStatus.open);
      // The notes are in the task now, not twice.
      expect(e.notes, '');
      expect(e.start, a.start);
      expect(e.end, a.end);
      expect(s.undoName, 'Turn into Task');
      expect(s.selection, {a.id});
      expect(s.selectedTaskId, t.id);

      s.undo();
      expect(s.event(a.id)!.kind, EventKind.activity);
      expect(s.event(a.id)!.taskId, isNull);
      expect(s.event(a.id)!.notes, 'Bring shoes');
      expect(s.repos.tasks.all(), isEmpty);
    });

    test('and back again: the same block, one task', () {
      final s = makeStore();
      final a = activity(s);
      final note = s.createMeetingNote(a)!;
      s.toggleKind(a.id);
      s.toggleKind(a.id);
      expect(s.event(a.id)!.kind, EventKind.activity);
      expect(s.repos.tasks.all(), isEmpty);
      expect(s.meetingNote(s.event(a.id)!)?.id, note.id);
      s.toggleKind(a.id);
      expect(s.repos.tasks.all().length, 1);
    });

    test('a block that cannot switch is left alone', () {
      final s = makeStore();
      s.createFromDraft(
        title: 'Call',
        day: day,
        start: 600,
        end: 630,
        asEvent: true,
      );
      final id = s.selection.single;
      final before = s.undoName;
      s.toggleKind(id);
      expect(s.event(id)!.kind, EventKind.event);
      expect(s.undoName, before);
    });
  });
}
