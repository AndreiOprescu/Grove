import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'sync_engine_test.dart' show fill;

void main() {
  group('The account of a database', () {
    test('a new database has no account', () {
      final d = Device(MemoryRemote());
      expect(d.engine.account, isNull);
      expect(d.outbox.account, isNull);
    });

    test('the account is kept in the database', () {
      final d = Device(MemoryRemote());
      d.outbox.account = 'user-1';
      expect(Outbox(d.db).account, 'user-1');
      d.outbox.account = null;
      expect(Outbox(d.db).account, isNull);
    });

    test('a device has data when it has a list, note, goal, task or event', () {
      final d = Device(MemoryRemote());
      expect(d.engine.hasLocalData, isFalse);
      d.repos.settings.set('theme', 'dark');
      expect(d.engine.hasLocalData, isFalse);
      d.repos.goals.upsert(GoalItem(title: 'Read'));
      expect(d.engine.hasLocalData, isTrue);
    });

    test('the remote has data when it has a row, also a deleted one', () async {
      final remote = MemoryRemote();
      final a = Device(remote), b = Device(remote);
      expect(await b.engine.remoteHasData(), isFalse);
      final task = TaskItem(title: 'Sweep');
      a.repos.tasks.save(task);
      await a.sync();
      expect(await b.engine.remoteHasData(), isTrue);
      a.later();
      a.repos.tasks.delete(task.id);
      await a.sync();
      expect(await b.engine.remoteHasData(), isTrue);
    });
  });

  group('Add the data of this device to the account', () {
    test('every row is queued again, also the rows sent before', () async {
      final old = MemoryRemote();
      final d = Device(old);
      fill(d);
      await d.sync();
      expect(d.outbox.count, 0);
      final before = dump(d.db);

      // The same database, now with another account.
      final account = MemoryRemote();
      final engine = SyncEngine(repos: d.repos, remote: account);
      engine.addDeviceTo('user-2');
      expect(engine.account, 'user-2');
      expect(engine.outbox.cursor, 0);
      expect(engine.outbox.count, greaterThan(0));
      await engine.sync();

      final other = Device(account);
      await other.sync();
      expect(dump(other.db), before);
      expect(dump(d.db), before);
    });

    test('a change that waits keeps its age', () async {
      final d = Device(MemoryRemote());
      final task = TaskItem(title: 'Sweep');
      d.repos.tasks.save(task);
      final stamp = d.outbox.entries().single.stamp;
      expect(stamp, greaterThan(0));
      d.engine.addDeviceTo('user-1');
      expect(d.outbox.entries().single.stamp, stamp);
    });

    test('the rows of the account and of the device are both there', () async {
      final remote = MemoryRemote();
      final a = Device(remote), b = Device(remote);
      a.repos.tasks.save(TaskItem(title: 'From the account'));
      a.engine.addDeviceTo('user-1');
      await a.sync();

      b.repos.tasks.save(TaskItem(title: 'From the device'));
      b.engine.addDeviceTo('user-1');
      await settle([a, b]);

      expectSame([a, b]);
      expect(
        {for (final t in a.repos.tasks.all()) t.title},
        {'From the account', 'From the device'},
      );
    });
  });

  group('Use the data of the account', () {
    test('the data of the device is replaced', () async {
      final remote = MemoryRemote();
      final a = Device(remote), b = Device(remote);
      fill(a);
      await a.sync();

      b.repos.lists.save(ListItem(name: 'Sample', emoji: '🌿'));
      b.repos.tasks.save(TaskItem(title: 'A sample task'));
      b.repos.settings.set('firstrun.done', '1');
      final report = await b.engine.replaceWithAccount('user-1');

      expect(report.pulled, greaterThan(0));
      expect(report.skipped, isEmpty);
      expect(b.engine.account, 'user-1');
      expectSame([a, b]);
      expect(b.repos.tasks.all().any((t) => t.title == 'A sample task'), false);
      // What went away is not a change for the account.
      expect(b.outbox.count, 0);
      await settle([a, b]);
      expectSame([a, b]);
      expect(a.repos.tasks.all().map((t) => t.title), contains('Sweep'));
    });

    test(
      'the search finds the rows of the account, not the old rows',
      () async {
        final remote = MemoryRemote();
        final a = Device(remote), b = Device(remote);
        a.repos.notes.save(Note(title: 'Plum tree', body: 'Prune in winter'));
        await a.sync();
        b.repos.notes.save(Note(title: 'Walnut', body: 'Old note'));

        await b.engine.replaceWithAccount('user-1');

        expect(b.repos.search.search('plum'), hasLength(1));
        expect(b.repos.search.search('walnut'), isEmpty);
      },
    );

    test('an account with no data leaves an empty device', () async {
      final d = Device(MemoryRemote());
      fill(d);
      final report = await d.engine.replaceWithAccount('user-1');
      expect(report.pulled, 0);
      expect(d.engine.hasLocalData, isFalse);
      expect(d.outbox.count, 0);
      expect(d.engine.account, 'user-1');
    });

    test('with no connection the device keeps its data', () async {
      final remote = MemoryRemote();
      final a = Device(remote), b = Device(remote);
      fill(a);
      await a.sync();
      b.repos.tasks.save(TaskItem(title: 'Mine'));
      final before = dump(b.db);
      final waiting = b.outbox.count;

      remote.offline = true;
      await expectLater(
        b.engine.replaceWithAccount('user-1'),
        throwsA(isA<RemoteUnavailable>()),
      );

      expect(dump(b.db), before);
      expect(b.outbox.count, waiting);
      expect(b.engine.account, isNull);
    });

    test('it waits for a sync that runs', () async {
      final remote = MemoryRemote();
      final a = Device(remote), b = Device(remote);
      a.repos.tasks.save(TaskItem(title: 'From the account'));
      await a.sync();
      b.repos.tasks.save(TaskItem(title: 'Mine'));

      final sync = b.sync();
      final replace = b.engine.replaceWithAccount('user-1');
      await sync;
      await replace;
      await settle([a, b]);

      // The sync ran first, so "Mine" went to the account before the
      // replace, and it came back with the data of the account.
      expectSame([a, b]);
      expect(
        {for (final t in b.repos.tasks.all()) t.title},
        {'From the account', 'Mine'},
      );
    });

    test('changes after the replace go to the account', () async {
      final remote = MemoryRemote();
      final a = Device(remote), b = Device(remote);
      fill(a);
      await a.sync();
      await b.engine.replaceWithAccount('user-1');
      b.later();
      b.repos.tasks.save(TaskItem(title: 'New on b'));
      await settle([a, b]);
      expectSame([a, b]);
      expect(a.repos.tasks.all().map((t) => t.title), contains('New on b'));
    });
  });

  group('The copy before the replace', () {
    test('each copy has its own name', () {
      final one = Backup.beforeSyncName(DateTime(2026, 10, 11, 9, 5, 7));
      final two = Backup.beforeSyncName(DateTime(2026, 10, 11, 9, 5, 8));
      expect(one, 'before-sync-20261011-090507.sqlite');
      expect(two, isNot(one));
    });

    test('the copy holds the data and is not a daily copy', () {
      final dir = Directory.systemTemp.createTempSync('grove-sync-copy');
      addTearDown(() => dir.deleteSync(recursive: true));
      final d = Device(MemoryRemote());
      d.repos.tasks.save(TaskItem(title: 'Mine'));
      final name = Backup.beforeSyncName(DateTime(2026, 10, 11));
      final path = Backup.safetyCopy(d.db, directory: dir.path, name: name);
      expect(File(path).existsSync(), isTrue);
      expect(path, endsWith(name));
      expect(Backup.list(dir.path), isEmpty);
      final copy = Database.open(path);
      addTearDown(copy.close);
      expect(Repos(copy).tasks.all().single.title, 'Mine');
    });
  });
}
