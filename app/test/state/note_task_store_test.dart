// Port of Tests/GroveTests/NoteTaskStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const friday = DayKey('2026-10-02');

String body(AppStore s, String id) => s.note(id)?.body ?? '';

List<NoteCheckbox> boxes(AppStore s, String id) =>
    NoteParser.checkboxes(body(s, id));

List<String> linkTitles(AppStore s, String noteId) => [
  for (final l in s.linkedItems(ItemRef(ItemType.note, noteId))) l.title,
];

/// A note "Trip" with one box that has its task. Returns the note and the
/// task id.
({Note note, String taskId}) tripWithTask(AppStore s) {
  final n = s.newNote(title: 'Trip', body: '- [ ] Buy sunscreen');
  s.syncNoteTasks(n.id);
  return (note: n, taskId: s.repos.tasks.inbox().first.id);
}

void main() {
  group('a box makes a task', () {
    test('open boxes make tasks in order and get marks', () {
      final s = makeStore();
      final n = s.newNote(
        title: 'Trip',
        body: '## Pack\n- [ ] Buy sunscreen\n- [ ] Book taxi',
      );
      expect(s.syncNoteTasks(n.id), 2);

      final tasks = s.repos.tasks.inbox();
      expect(titles(tasks), ['Buy sunscreen', 'Book taxi']);
      expect([for (final b in boxes(s, n.id)) b.taskId], ids(tasks));
      // The reader sees the same words as before.
      expect(
        NoteParser.withoutMarkers(body(s, n.id)),
        '## Pack\n- [ ] Buy sunscreen\n- [ ] Book taxi',
      );
    });

    test('a second sync makes nothing new', () {
      final s = makeStore();
      final n = s.newNote(title: 'Trip', body: '- [ ] Buy sunscreen');
      expect(s.syncNoteTasks(n.id), 1);
      expect(s.syncNoteTasks(n.id), 0);
      expect(s.repos.tasks.inbox().length, 1);
    });

    test('ticked, empty and plain lines make no task', () {
      final s = makeStore();
      const text = '- [x] Old thing\n- [ ] \n- not a box\nText';
      final n = s.newNote(title: 'Trip', body: text);
      expect(s.syncNoteTasks(n.id), 0);
      expect(s.repos.tasks.inbox(), isEmpty);
      expect(body(s, n.id), text);
    });

    test('a daily note makes tasks for that day', () {
      final s = makeStore();
      final d = s.dailyNote(friday);
      s.setNoteBody(d.id, '## Plan\n- [ ] Write report\n');
      expect(s.syncNoteTasks(d.id), 1);
      final t = s.repos.tasks.forDay(friday).first;
      expect(t.title, 'Write report');
      expect(t.bucket, TaskBucket.day);
    });

    test('a weekly note makes tasks for that week', () {
      final s = makeStore();
      final w = s.weeklyNote(friday);
      s.setNoteBody(w.id, '## Goals\n- [ ] Ship the notes screen\n');
      expect(s.syncNoteTasks(w.id), 1);
      final t = s.repos.tasks.forWeek(const DayKey('2026-09-28')).first;
      expect(t.title, 'Ship the notes screen');
      expect(t.bucket, TaskBucket.week);
    });

    test('the line is read like quick add', () {
      final s = makeStore();
      final n = s.newNote(title: 'Trip', body: '- [ ] Call Sam tomorrow #home');
      s.syncNoteTasks(n.id);
      final tomorrow = DayKey.today().adding(days: 1);
      final t = s.repos.tasks.forDay(tomorrow).first;
      expect(t.title, 'Call Sam');
      expect(s.tagNames(t.id), ['home']);
    });

    test('the task links back to the note', () {
      final s = makeStore();
      final n = s.newNote(title: 'Trip', body: '- [ ] Buy sunscreen');
      s.syncNoteTasks(n.id);
      final t = s.repos.tasks.inbox().first;
      expect(t.notes, 'From [[Trip|${n.id}]]');
      expect(linkTitles(s, n.id), ['Buy sunscreen']);
    });

    test('one undo removes the tasks and the marks', () {
      final s = makeStore();
      final n = s.newNote(title: 'Trip', body: '- [ ] One\n- [ ] Two');
      s.syncNoteTasks(n.id);
      expect(s.undoName, 'New Tasks from Note');
      s.undo();
      expect(s.repos.tasks.inbox(), isEmpty);
      expect(body(s, n.id), '- [ ] One\n- [ ] Two');
      s.redo();
      expect(s.repos.tasks.inbox().length, 2);
      expect(boxes(s, n.id).every((b) => b.taskId != null), isTrue);
    });

    test('a sync without creating only follows the boxes', () {
      final s = makeStore();
      final (note: n, taskId: id) = tripWithTask(s);
      s.setNoteBody(
        n.id,
        '${NoteParser.settingChecked(body(s, n.id), line: 0, checked: true)}'
        '\n- [ ] Half-typed',
      );
      expect(s.syncNoteTasks(n.id, creating: false), 0);
      // The ticked box still finishes its task.
      expect(s.task(id)?.isDone, isTrue);
      expect(s.repos.tasks.all().length, 1); // the new line waits
      expect(s.syncNoteTasks(n.id), 1);
    });
  });

  group('the two stay in step', () {
    test('ticking the box finishes the task and clearing it reopens it', () {
      final s = makeStore();
      final (note: n, taskId: id) = tripWithTask(s);

      s.setNoteBody(
        n.id,
        NoteParser.settingChecked(body(s, n.id), line: 0, checked: true),
      );
      s.syncNoteTasks(n.id);
      expect(s.task(id)?.isDone, isTrue);

      s.setNoteBody(
        n.id,
        NoteParser.settingChecked(body(s, n.id), line: 0, checked: false),
      );
      s.syncNoteTasks(n.id);
      expect(s.task(id)?.isDone, isFalse);
    });

    test('finishing the task ticks the box and undo clears it', () {
      final s = makeStore();
      final (note: n, taskId: id) = tripWithTask(s);
      final edited = s.note(n.id)!.updatedAt;

      s.toggleDone(taskId: id);
      expect(boxes(s, n.id).first.checked, isTrue);
      // The user did not edit the note.
      expect(s.note(n.id)?.updatedAt, edited);

      s.undo();
      expect(boxes(s, n.id).first.checked, isFalse);
      s.redo();
      expect(boxes(s, n.id).first.checked, isTrue);
    });

    test('the same task in two notes ticks both', () {
      final s = makeStore();
      final a = s.newNote(title: 'A', body: '- [ ] Shared');
      s.syncNoteTasks(a.id);
      final id = boxes(s, a.id).first.taskId!;
      final b = s.newNote(
        title: 'B',
        body: '- [ ] Shared copy ${NoteParser.marker(id)}',
      );
      s.toggleDone(taskId: id);
      expect(boxes(s, a.id).first.checked, isTrue);
      expect(boxes(s, b.id).first.checked, isTrue);
    });

    test('a task that is brought back by undo matches its box', () {
      final s = makeStore();
      final (note: n, taskId: id) = tripWithTask(s);
      s.toggleDone(taskId: id);
      s.deleteTask(id);
      s.undo(); // the task is back, finished
      expect(s.task(id)?.isDone, isTrue);
      expect(boxes(s, n.id).first.checked, isTrue);
    });
  });

  group('lines and tasks that go away', () {
    test('deleting the line keeps the task', () {
      final s = makeStore();
      final n = tripWithTask(s).note;
      s.setNoteBody(n.id, '');
      expect(s.syncNoteTasks(n.id), 0);
      expect(s.repos.tasks.inbox().length, 1);
    });

    test('deleting the task keeps the line and makes no new task', () {
      final s = makeStore();
      final (note: n, taskId: id) = tripWithTask(s);
      s.deleteTask(id);
      expect(s.syncNoteTasks(n.id), 0);
      expect(s.repos.tasks.inbox(), isEmpty);
      expect(boxes(s, n.id).length, 1);
    });

    test('a title change on one side does not change the other', () {
      final s = makeStore();
      final (note: n, taskId: id) = tripWithTask(s);
      s.setNoteBody(
        n.id,
        body(s, n.id).replaceAll('Buy sunscreen', 'Buy lotion'),
      );
      s.syncNoteTasks(n.id);
      expect(s.task(id)?.title, 'Buy sunscreen');
    });
  });

  group('make task', () {
    test('make task gives an id and links to the note', () {
      final s = makeStore();
      final n = s.newNote(title: 'Trip', body: 'Call Sam about the trip');
      final id = s.makeTask(from: 'Call Sam', inNote: n.id)!;
      final t = s.task(id)!;
      expect(t.title, 'Call Sam');
      expect(t.bucket, TaskBucket.inbox);
      expect(t.notes, 'From [[Trip|${n.id}]]');
      expect(linkTitles(s, n.id), ['Call Sam']);
      expect(s.undoName, 'New Task from Note');
      s.undo();
      expect(s.task(id), isNull);
    });

    test('make task in a daily note lands on that day', () {
      final s = makeStore();
      final d = s.dailyNote(friday);
      final id = s.makeTask(from: 'Send the invoice', inNote: d.id)!;
      expect(s.task(id)?.planDate, friday);
    });

    test('make task without words or note makes nothing', () {
      final s = makeStore();
      final n = s.newNote(title: 'Trip');
      expect(s.makeTask(from: '   ', inNote: n.id), isNull);
      expect(s.makeTask(from: 'Call Sam', inNote: 'missing'), isNull);
      expect(s.repos.tasks.inbox(), isEmpty);
    });

    test('a line made with make task is not made again by sync', () {
      final s = makeStore();
      final n = s.newNote(title: 'Trip', body: 'Call Sam about the trip');
      final id = s.makeTask(from: 'Call Sam about the trip', inNote: n.id)!;
      final text = body(s, n.id);
      final target = MarkdownEdit.taskTarget(text, const Utf16Range(0, 0))!;
      final edit = MarkdownEdit.taskLine(target, text, taskId: id);
      s.setNoteBody(
        n.id,
        text.replaceRange(
          edit.range.location,
          edit.range.end,
          edit.replacement,
        ),
      );
      expect(s.syncNoteTasks(n.id), 0);
      expect(s.repos.tasks.inbox().length, 1);
    });

    test('a box with an @date waits for "Add to planner"', () {
      final s = makeStore();
      final n = s.newNote(
        title: 'Trip',
        body: '- [ ] Call Sam @tomorrow 3pm\n- [ ] Buy sunscreen',
      );
      expect(s.syncNoteTasks(n.id), 1); // only the plain box
      expect(titles(s.repos.tasks.inbox()), ['Buy sunscreen']);
      // The line stays as typed.
      expect(body(s, n.id), contains('Call Sam @tomorrow 3pm\n'));

      final line = s.addToPlanner(
        line: '- [ ] Call Sam @tomorrow 3pm',
        inNote: n.id,
      )!;
      s.setNoteBody(
        n.id,
        body(s, n.id).replaceAll('- [ ] Call Sam @tomorrow 3pm', line),
      );
      expect(s.syncNoteTasks(n.id), 0); // it has its task now
      expect(s.repos.tasks.all().length, 2);
    });

    test('an address is not an @date', () {
      final s = makeStore();
      final n = s.newNote(title: 'Trip', body: '- [ ] Mail me@home.com');
      expect(s.syncNoteTasks(n.id), 1);
    });
  });
}
