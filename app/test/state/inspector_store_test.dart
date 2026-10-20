// Port of Tests/GroveTests/InspectorStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

TaskItem sub(int minutes, {bool done = false}) => TaskItem(
  title: 's',
  estimateMin: minutes,
  status: done ? TaskStatus.done : TaskStatus.open,
);

void main() {
  // The store side of the task inspector: saving a body, and undo of typing.
  group('InspectorStore', () {
    test('saving a body stores it and keeps links', () {
      final s = makeStore();
      final a = s.quickAdd('A')!;
      final b = s.quickAdd('B')!;
      s.setNotes(a.id, 'see [[B]]');
      expect(s.task(a.id)?.notes, 'see [[B|${b.id}]]');
      expect(s.repos.links.backlinks(ItemRef(ItemType.task, b.id)), [
        ItemRef(ItemType.task, a.id),
      ]);
    });

    test('typing in one body is one undo step', () {
      final s = makeStore();
      final a = s.quickAdd('A')!;
      s.setNotes(a.id, 'h');
      s.setNotes(a.id, 'he');
      s.setNotes(a.id, 'hello');
      s.undo();
      expect(s.task(a.id)?.notes, '');
      s.redo();
      expect(s.task(a.id)?.notes, 'hello');
    });

    test('a pause of a minute starts a new undo step', () {
      final s = makeStore();
      final a = s.quickAdd('A')!;
      s.setNotes(
        a.id,
        'one',
        now: DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
      );
      s.setNotes(
        a.id,
        'two',
        now: DateTime.fromMillisecondsSinceEpoch(1090 * 1000),
      );
      s.undo();
      expect(s.task(a.id)?.notes, 'one');
    });

    test('other changes break the merge', () {
      final s = makeStore();
      final a = s.quickAdd('A')!;
      s.setNotes(a.id, 'one');
      s.editTask(a.id, name: 'Set Priority', (t) => t.copyWith(priority: 2));
      s.setNotes(a.id, 'two');
      s.undo();
      expect(s.task(a.id)?.notes, 'one');
      expect(s.task(a.id)?.priority, 2);
      s.undo();
      expect(s.task(a.id)?.priority, 0);
    });

    test('bodies of different tasks are not merged', () {
      final s = makeStore();
      final a = s.quickAdd('A')!;
      final b = s.quickAdd('B')!;
      s.setNotes(a.id, 'aaa');
      s.setNotes(b.id, 'bbb');
      s.undo();
      expect(s.task(b.id)?.notes, '');
      expect(s.task(a.id)?.notes, 'aaa');
    });

    test('saving the same body again changes nothing', () {
      final s = makeStore();
      final a = s.quickAdd('A')!;
      s.setNotes(a.id, 'same');
      final before = s.undoName;
      s.setNotes(a.id, 'same');
      s.undo();
      expect(s.task(a.id)?.notes, '');
      expect(before, 'Edit Notes');
    });

    // Subtasks

    test('adding a subtask returns it and keeps the name', () {
      final s = makeStore();
      final a = s.quickAdd('Trip')!;
      final id = s.addSubtask(to: a.id, title: '  Book hotel ')!;
      expect(s.addSubtask(to: a.id, title: '   '), isNull);
      final sub = s.task(id)!;
      expect(sub.title, 'Book hotel');
      expect(sub.parentId, a.id);
      expect(ids(s.subtasks(a.id)), [id]);
    });

    test('a subtask keeps its own description and duration', () {
      final s = makeStore();
      final a = s.quickAdd('Trip')!;
      final id = s.addSubtask(to: a.id, title: 'Book hotel')!;
      s.setNotes(id, 'Near the station, with breakfast');
      s.editTask(id, name: 'Set Length', (t) => t.copyWith(estimateMin: 15));
      final sub = s.task(id)!;
      expect(sub.notes, 'Near the station, with breakfast');
      expect(sub.estimateMin, 15);
      expect(s.task(a.id)?.notes, '');
      expect(s.task(a.id)?.estimateMin, isNot(15));
    });

    test('done on one subtask leaves the others and the parent alone', () {
      final s = makeStore();
      final a = s.quickAdd('Trip')!;
      final one = s.addSubtask(to: a.id, title: 'One')!;
      final two = s.addSubtask(to: a.id, title: 'Two')!;
      s.toggleDone(taskId: one);
      expect(s.task(one)?.isDone, isTrue);
      expect(s.task(one)?.completedAt, isNotNull);
      expect(s.task(two)?.isDone, isFalse);
      expect(s.task(a.id)?.isDone, isFalse);
      s.toggleDone(taskId: one);
      expect(s.task(one)?.isDone, isFalse);
      expect(s.task(one)?.completedAt, isNull);
    });

    test('the parent stays open when every subtask is done', () {
      final s = makeStore();
      final a = s.quickAdd('Trip')!;
      final one = s.addSubtask(to: a.id, title: 'One')!;
      final two = s.addSubtask(to: a.id, title: 'Two')!;
      s.toggleDone(taskId: one);
      s.toggleDone(taskId: two);
      expect(s.subtasks(a.id).every((t) => t.isDone), isTrue);
      expect(s.task(a.id)?.isDone, isFalse);
    });

    test('undo reverts a subtask edit', () {
      final s = makeStore();
      final a = s.quickAdd('Trip')!;
      final id = s.addSubtask(to: a.id, title: 'Book hotel')!;
      final before = s.task(id)!.estimateMin;
      s.editTask(id, name: 'Set Length', (t) => t.copyWith(estimateMin: 90));
      s.undo();
      expect(s.task(id)?.estimateMin, before);
      s.setNotes(id, 'N');
      s.setNotes(id, 'Near');
      s.setNotes(id, 'Near the station'); // one burst of typing
      s.undo();
      expect(s.task(id)?.notes, '');
      expect(s.task(id)?.title, 'Book hotel');
    });
  });

  // The text rules behind the subtask list in the task panel.
  group('SubtaskRules', () {
    test('no subtasks gives plain header', () {
      expect(SubtaskRules.summary([]), '');
      expect(SubtaskRules.header([]), 'Subtasks');
    });

    test('header shows done of total and total time', () {
      final subs = [sub(15, done: true), sub(30, done: true), sub(10), sub(20)];
      expect(SubtaskRules.summary(subs), '2/4 · 1h 15m');
      expect(SubtaskRules.header(subs), 'Subtasks  2/4 · 1h 15m');
    });

    test('no time leaves the time out', () {
      expect(SubtaskRules.summary([sub(0), sub(0, done: true)]), '1/2');
    });

    test('chip shows the duration and hides zero', () {
      expect(SubtaskRules.chip(15), '15m');
      expect(SubtaskRules.chip(90), '1h 30m');
      expect(SubtaskRules.chip(0), isNull);
    });

    test('duration choices are fixed and keep an odd current value', () {
      expect(SubtaskRules.durationsIncluding(30), [
        5,
        10,
        15,
        30,
        45,
        60,
        90,
        120,
      ]);
      expect(SubtaskRules.durationsIncluding(20), [
        5,
        10,
        15,
        20,
        30,
        45,
        60,
        90,
        120,
      ]);
    });

    test('a rename needs a new non-empty name', () {
      expect(SubtaskRules.renamed('  ', from: 'Book hotel'), isNull);
      expect(SubtaskRules.renamed('Book hotel', from: 'Book hotel'), isNull);
      expect(
        SubtaskRules.renamed(' Book flight ', from: 'Book hotel'),
        'Book flight',
      );
    });
  });
}
