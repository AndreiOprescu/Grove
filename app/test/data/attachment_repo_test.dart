import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/parsing/reference_parser.dart';
import 'package:grove/data/data.dart';

import 'helpers.dart';

/// Image bytes. The repo stores what it gets; shrinking happens before it.
Uint8List bytes(int n) => Uint8List.fromList(List.generate(n, (i) => i % 256));

StoredImage add(Repos r, {int size = 16}) => r.attachments.add(
  mime: 'image/png',
  data: bytes(size),
  width: 8,
  height: 8,
);

void main() {
  test('add and get round trip', () {
    final r = makeRepos();
    final raw = bytes(300);
    final a = r.attachments.add(
      mime: 'image/png',
      data: raw,
      width: 64,
      height: 48,
    );
    final back = r.attachments.get(a.id)!;
    expect(back.data, raw);
    expect(back.mime, 'image/png');
    expect(back.width, 64);
    expect(back.height, 48);
    expect(
      RegExp(r'^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-').hasMatch(back.id),
      isTrue,
    );
  });

  test('get an unknown id gives null', () {
    expect(makeRepos().attachments.get('nope'), isNull);
  });

  test('delete removes the row', () {
    final r = makeRepos();
    final a = add(r);
    r.attachments.delete(a.id);
    expect(r.attachments.get(a.id), isNull);
    expect(r.attachments.count(), 0);
  });

  ({StoredImage task, StoredImage note, StoredImage event, StoredImage orphan})
  fourImages(Repos r) {
    final a = add(r), b = add(r), c = add(r), d = add(r);
    r.tasks.save(
      TaskItem(
        title: 'T',
        notes: ReferenceParser.imageMarkup(id: a.id, alt: 'a'),
      ),
    );
    r.notes.save(
      Note(
        title: 'N',
        body: 'text ${ReferenceParser.imageMarkup(id: b.id, alt: 'b')}',
      ),
    );
    r.events.save(
      EventItem(
        title: 'E',
        start: WallTime.parse('2026-10-05T09:00')!,
        end: WallTime.parse('2026-10-05T10:00')!,
        notes: ReferenceParser.imageMarkup(id: c.id, alt: 'c'),
      ),
    );
    return (task: a, note: b, event: c, orphan: d);
  }

  test('sweep removes old unreferenced images only', () {
    final r = makeRepos();
    final x = fourImages(r);
    final later = DateTime.now().add(const Duration(days: 2));
    expect(r.attachments.sweepOrphans(now: later), 1);
    expect(r.attachments.get(x.orphan.id), isNull);
    expect(r.attachments.get(x.task.id), isNotNull);
    expect(r.attachments.get(x.note.id), isNotNull);
    expect(r.attachments.get(x.event.id), isNotNull);
  });

  test('sweep keeps fresh images even when nothing uses them yet', () {
    final r = makeRepos();
    final x = fourImages(r);
    expect(r.attachments.sweepOrphans(now: DateTime.now()), 0);
    expect(r.attachments.get(x.orphan.id), isNotNull);
  });

  test('an image stays when another body still uses it', () {
    final r = makeRepos();
    final a = add(r);
    var t1 = TaskItem(
      title: 'One',
      notes: ReferenceParser.imageMarkup(id: a.id, alt: ''),
    );
    final t2 = TaskItem(
      title: 'Two',
      notes: ReferenceParser.imageMarkup(id: a.id, alt: ''),
    );
    r.tasks.save(t1);
    r.tasks.save(t2);
    t1 = t1.copyWith(notes: '');
    r.tasks.save(t1);
    expect(
      r.attachments.sweepOrphans(
        olderThanMinutes: 0,
        now: DateTime.now().add(const Duration(minutes: 1)),
      ),
      0,
    );
  });

  test('images survive the daily backup', () {
    final dir = tempDir('grove-bk-');
    final r = makeRepos();
    final raw = bytes(1000);
    final a = r.attachments.add(
      mime: 'image/png',
      data: raw,
      width: 32,
      height: 32,
    );
    final file = Backup.runDaily(
      r.db,
      directory: dir.path,
      today: const DayKey('2026-10-02'),
    )!;
    final copy = Repos(Database.open(file));
    expect(copy.attachments.get(a.id)?.data, raw);
    copy.db.close();
  });
}
