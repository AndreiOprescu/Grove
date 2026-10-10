import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/ids.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/model/task.dart';

import 'helpers.dart';

ItemRef task(String id) => ItemRef(ItemType.task, id);
ItemRef note(String id) => ItemRef(ItemType.note, id);
ItemRef event(String id) => ItemRef(ItemType.event, id);

EventItem anEvent(String title) => EventItem(
  title: title,
  start: WallTime.parse('2026-10-05T09:00')!,
  end: WallTime.parse('2026-10-05T10:00')!,
);

void main() {
  group('resolving and canonical text', () {
    test('a title mention becomes an id mention', () {
      final r = makeRepos();
      final milk = TaskItem(title: 'Buy milk');
      r.tasks.save(milk);
      final out = r.refs.canonicalize('see [[buy MILK]]');
      expect(out.text, 'see [[Buy milk|${milk.id}]]');
      expect(out.targets, [task(milk.id)]);
    });

    test('the id wins over the title', () {
      final r = makeRepos();
      final a = TaskItem(title: 'Same'), b = TaskItem(title: 'Same');
      r.tasks.save(a);
      r.tasks.save(b);
      final out = r.refs.canonicalize('[[Same|${b.id}]]');
      expect(out.targets, [task(b.id)]);
      expect(out.text, '[[Same|${b.id}]]');
    });

    test('an open task beats a done task with the same title', () {
      final r = makeRepos();
      final done = TaskItem(title: 'Same', status: TaskStatus.done);
      final open = TaskItem(title: 'Same');
      r.tasks.save(open);
      r.tasks.save(done);
      expect(r.refs.canonicalize('[[Same]]').targets, [task(open.id)]);
    });

    test('a note beats a task on a title tie', () {
      final r = makeRepos();
      final t = TaskItem(title: 'Plan'), n = Note(title: 'Plan');
      r.tasks.save(t);
      r.notes.save(n);
      expect(r.refs.canonicalize('[[Plan]]').targets, [note(n.id)]);
    });

    test('events can be mentioned', () {
      final r = makeRepos();
      final e = anEvent('Dentist');
      r.events.save(e);
      expect(r.refs.canonicalize('[[Dentist]]').targets, [event(e.id)]);
    });

    test('an unknown mention stays as typed', () {
      final r = makeRepos();
      final out = r.refs.canonicalize('[[Nope]] and text');
      expect(out.text, '[[Nope]] and text');
      expect(out.targets, isEmpty);
    });

    test('a deleted target stays dangling and does not rebind', () {
      final r = makeRepos();
      final gone = TaskItem(title: 'Old'), other = TaskItem(title: 'Old');
      r.tasks.save(gone);
      r.tasks.save(other);
      r.tasks.delete(gone.id);
      final text = '[[Old|${gone.id}]]';
      final out = r.refs.canonicalize(text);
      expect(out.text, text);
      expect(out.targets, isEmpty);
    });

    test('a stale title is healed', () {
      final r = makeRepos();
      final t = TaskItem(title: 'New name');
      r.tasks.save(t);
      expect(
        r.refs.canonicalize('[[Old name|${t.id}]]').text,
        '[[New name|${t.id}]]',
      );
    });

    test('subtasks can be mentioned', () {
      final r = makeRepos();
      final parent = TaskItem(title: 'Trip');
      final child = TaskItem(title: 'Book hotel', parentId: parent.id);
      r.tasks.save(parent);
      r.tasks.save(child);
      expect(r.refs.canonicalize('[[Book hotel]]').targets, [task(child.id)]);
    });

    test('resolves by title and id without a mention value', () {
      final r = makeRepos();
      final milk = TaskItem(title: 'Buy milk');
      r.tasks.save(milk);
      expect(r.refs.resolveTitle('buy milk')?.ref, task(milk.id));
      expect(
        r.refs.resolveTitle('stale title', id: milk.id)?.title,
        'Buy milk',
      );
      expect(r.refs.resolveTitle('Buy milk', id: newId()), isNull);
      expect(r.refs.resolveTitle('Nope'), isNull);
    });

    test('titleOf checks the type too', () {
      final r = makeRepos();
      final t = TaskItem(title: 'Buy milk');
      r.tasks.save(t);
      expect(r.refs.titleOf(task(t.id)), 'Buy milk');
      expect(r.refs.titleOf(note(t.id)), isNull);
    });
  });

  group('links table', () {
    test('reindex writes and clears backlinks', () {
      final r = makeRepos();
      final a = TaskItem(title: 'A'), b = TaskItem(title: 'B');
      r.tasks.save(a);
      r.tasks.save(b);
      final canon = r.refs.reindex(task(a.id), 'needs [[B]]');
      expect(canon, 'needs [[B|${b.id}]]');
      expect(r.links.backlinks(task(b.id)), [task(a.id)]);
      r.refs.reindex(task(a.id), 'no mention now');
      expect(r.links.backlinks(task(b.id)), isEmpty);
    });

    test('reindex keeps manual links', () {
      final r = makeRepos();
      final a = TaskItem(title: 'A'), c = TaskItem(title: 'C');
      r.tasks.save(a);
      r.tasks.save(c);
      r.links.addManual(task(a.id), task(c.id));
      r.refs.reindex(task(a.id), '');
      expect(r.links.outgoing(task(a.id)), [task(c.id)]);
    });

    test('mentioning yourself makes no link', () {
      final r = makeRepos();
      final a = TaskItem(title: 'A');
      r.tasks.save(a);
      r.refs.reindex(task(a.id), '[[A]]');
      expect(r.links.outgoing(task(a.id)), isEmpty);
    });

    test('notes and events link to tasks too', () {
      final r = makeRepos();
      final t = TaskItem(title: 'Report');
      final n = Note(title: 'Journal');
      r.tasks.save(t);
      r.notes.save(n);
      r.refs.reindex(note(n.id), 'finish [[Report]]');
      expect(r.links.backlinks(task(t.id)), [note(n.id)]);
    });
  });

  test('a rename rewrites every body that links', () {
    final r = makeRepos();
    var target = TaskItem(title: 'Old title');
    final other = TaskItem(title: 'Other');
    r.tasks.save(target);
    r.tasks.save(other);

    final host = TaskItem(
      title: 'Host',
      notes: r.refs.canonicalize('depends on [[Old title]]').text,
    );
    r.tasks.save(host);
    final n = Note(
      title: 'Journal',
      body: r.refs.canonicalize('x [[Old title]] y [[Other]] z').text,
    );
    r.notes.save(n);
    final e = anEvent('Sync')
        .copyWith(notes: r.refs.canonicalize('talk about [[Old title]]').text);
    r.events.save(e);
    r.refs.reindex(task(host.id), host.notes);
    r.refs.reindex(note(n.id), n.body);
    r.refs.reindex(event(e.id), e.notes);
    final noteStamp = r.notes.get(n.id)!.updatedAt;

    target = target.copyWith(title: 'Fresh title');
    r.tasks.save(target);
    r.refs.renamed(task(target.id), 'Fresh title');

    expect(
      r.tasks.get(host.id)?.notes,
      'depends on [[Fresh title|${target.id}]]',
    );
    expect(
      r.notes.get(n.id)?.body,
      'x [[Fresh title|${target.id}]] y [[Other|${other.id}]] z',
    );
    expect(
      r.events.get(e.id)?.notes,
      'talk about [[Fresh title|${target.id}]]',
    );
    // A rename must not make every linking note look freshly edited.
    expect(r.notes.get(n.id)?.updatedAt, noteStamp);
    // Search sees the new title text.
    expect(r.search.search('Fresh').map((h) => h.ref), contains(task(host.id)));
    // Links are still in place.
    expect(r.links.backlinks(task(target.id)).length, 3);
  });

  group('deleting', () {
    test('deleting an item removes its links both ways', () {
      final r = makeRepos();
      final a = TaskItem(title: 'A'), b = TaskItem(title: 'B');
      final n = Note(title: 'N');
      final e = anEvent('E');
      r.tasks.save(a);
      r.tasks.save(b);
      r.notes.save(n);
      r.events.save(e);
      r.links.addManual(task(a.id), task(b.id));
      r.links.addManual(note(n.id), task(a.id));
      r.links.addManual(event(e.id), task(a.id));

      r.notes.delete(n.id);
      expect(r.links.backlinks(task(a.id)), [event(e.id)]);
      r.events.delete(e.id);
      expect(r.links.backlinks(task(a.id)), isEmpty);
      r.tasks.delete(b.id);
      expect(r.links.outgoing(task(a.id)), isEmpty);
    });

    test('deleting a parent task also clears the links of its subtasks', () {
      final r = makeRepos();
      final parent = TaskItem(title: 'Parent');
      final child = TaskItem(title: 'Child', parentId: parent.id);
      final n = Note(title: 'N');
      r.tasks.save(parent);
      r.tasks.save(child);
      r.notes.save(n);
      r.links.addManual(task(child.id), note(n.id));
      r.tasks.delete(parent.id);
      expect(r.links.backlinks(note(n.id)), isEmpty);
    });

    test('rebuildIncoming restores links to a brought back target', () {
      final r = makeRepos();
      final target = TaskItem(title: 'Target');
      r.tasks.save(target);
      final host = TaskItem(
        title: 'Host',
        notes: r.refs.canonicalize('see [[Target]]').text,
      );
      r.tasks.save(host);
      r.refs.reindex(task(host.id), host.notes);
      r.tasks.delete(target.id);
      expect(r.links.backlinks(task(target.id)), isEmpty);
      r.tasks.save(target); // Same id, as undo does.
      r.refs.rebuildIncoming(task(target.id));
      expect(r.links.backlinks(task(target.id)), [task(host.id)]);
    });
  });

  test('search sees words, not ids or markup', () {
    final r = makeRepos();
    final dentist = TaskItem(title: 'Dentist');
    r.tasks.save(dentist);
    final imageId = newId();
    final host = TaskItem(
      title: 'Errands',
      notes:
          'call [[Dentist|${dentist.id}]] '
          '![front door](grove-image:$imageId)',
    );
    r.tasks.save(host);
    expect(r.search.search('front').map((h) => h.ref), contains(task(host.id)));
    expect(r.search.search(imageId.substring(0, 8)), isEmpty);
    expect(r.search.search('grove'), isEmpty);
  });

  test('a task summary is saved and searched', () {
    final r = makeRepos();
    final t = TaskItem(
      title: 'Plan trip',
      summary: 'Flights and hotel',
      notes: 'Long text',
    );
    r.tasks.save(t);
    final back = r.tasks.get(t.id)!;
    expect(back.summary, 'Flights and hotel');
    expect(back.notes, 'Long text');
    expect(r.search.search('hotel').map((h) => h.ref.id), contains(t.id));
  });

  test('a task colour is saved', () {
    final r = makeRepos();
    r.tasks.save(TaskItem(id: 'T1', title: 'Paint', color: 'teal'));
    expect(r.tasks.get('T1')?.color, 'teal');
    expect(r.tasks.all().first.color, 'teal');
  });

  test('a time block is not in the search', () {
    final r = makeRepos();
    final t = TaskItem(title: 'Essay');
    r.tasks.save(t);
    r.events.save(
      EventItem(
        title: 'Essay block',
        start: const WallTime(day: DayKey('2026-10-05'), minute: 600),
        end: const WallTime(day: DayKey('2026-10-05'), minute: 660),
        kind: EventKind.block,
        taskId: t.id,
      ),
    );
    expect(r.search.search('Essay').map((h) => h.ref), [task(t.id)]);
  });
}
