// Import and sync together (the owner's answer under Q-18, 2026-10-11):
// the store refuses an import while a person is signed in to sync. And what
// the first sync after an import does with the rows of the file.
import 'package:flutter_test/flutter_test.dart';

import 'sync_support.dart';

/// Longer than each wait of the store.
const longTime = Duration(hours: 1);

/// An export file with one task in it, made on a device of its own.
String fileWith(World world, String title) {
  final maker = world.device();
  maker.store.quickAdd(title);
  return maker.store.exportData();
}

void main() {
  group('Import while signed in to sync', () {
    test('the store refuses, says why, and changes no row', () async {
      final world = World();
      final file = fileWith(world, 'From the file');
      final a = world.device(seed: true);
      final mine = a.store.quickAdd('Mine')!;
      await signIn(a, me);
      a.store.selectedTaskId = mine.id;
      final before = titles(a.store);
      final rows = world.of(me).count;
      final revision = a.store.revision;
      final undo = a.store.undoName;

      expect(a.store.importBlocked, isNotNull);
      expect(
        () => a.store.importData(file),
        throwsA(
          isA<ImportRefused>().having(
            (e) => '$e',
            'the words for the screen',
            allOf(contains('signed in'), contains('Sign out')),
          ),
        ),
      );

      expect(titles(a.store), before);
      expect(a.store.syncWaiting, 0);
      expect(a.store.selectedTaskId, mine.id);
      expect(a.store.undoName, undo);
      expect(a.store.revision, revision);
      expect(a.store.toast, isNull);
      // Nothing goes to the account later.
      await a.store.syncNow();
      await world.pass(longTime);
      expect(world.of(me).count, rows);
      expect(titles(a.store), before);
    });

    test('the words of the store are the words of the error', () async {
      final world = World();
      final a = world.device(seed: true);
      await signIn(a, me);
      expect(a.store.importBlocked, '${const ImportRefused()}');
    });

    test('a bad file is refused for the login first', () async {
      final world = World();
      final a = world.device(seed: true);
      await signIn(a, me);
      expect(() => a.store.importData('nope'), throwsA(isA<ImportRefused>()));
    });

    test('Grove waits for the answer of the first login: '
        'the import is refused too', () async {
      final world = World();
      final file = fileWith(world, 'From the file');
      final a = world.device(seed: true);
      await signIn(a, me);
      final b = world.device(seed: true);
      b.store.quickAdd('From the device');
      await signIn(b, me);
      expect(b.store.firstSyncQuestion, isTrue);

      expect(() => b.store.importData(file), throwsA(isA<ImportRefused>()));
      expect(titles(b.store), contains('From the device'));
    });
  });

  group('Import while signed out', () {
    test('a build with no keys imports as before', () {
      final a = makeStore();
      a.quickAdd('Something old');
      final file = fileWith(World(), 'From the file');

      expect(a.importBlocked, isNull);
      a.importData(file);
      expect(titles(a), {'From the file'});
      expect(a.toast, isNotNull);
    });

    test('a device with keys and no login imports as before', () {
      final world = World();
      final file = fileWith(world, 'From the file');
      final a = world.device(seed: true);

      expect(a.store.importBlocked, isNull);
      a.store.importData(file);
      expect(titles(a.store), {'From the file'});
    });

    test('after the sign-out the import works again', () async {
      final world = World();
      final file = fileWith(world, 'From the file');
      final a = world.device(seed: true);
      await signIn(a, me);
      final rows = world.of(me).count;
      await a.store.signOut();

      expect(a.store.importBlocked, isNull);
      a.store.importData(file);
      expect(titles(a.store), {'From the file'});
      // Signed out: nothing goes to the account.
      await a.store.syncNow();
      await world.pass(longTime);
      expect(world.of(me).count, rows);
    });
  });

  // What the sync does today with the rows of an import. These tests say
  // what is, so a change of it is seen. Question card Q-22 asks the owner if
  // the last group is what Grove must do.
  group('The first sync after an import: a device that never synced', () {
    test('an account with no data gets the rows of the file, '
        'with no question', () async {
      final world = World();
      final file = fileWith(world, 'From the file');
      final a = world.device(seed: true);
      a.store.quickAdd('Old one');
      a.store.importData(file);

      await signIn(a, me);
      expect(a.store.firstSyncQuestion, isFalse);
      expect(a.store.syncStatus, SyncStatus.upToDate);
      expect(a.store.syncWaiting, 0);

      final b = world.device();
      await signIn(b, me);
      expect(titles(b.store), {'From the file'});
    });

    test('an account with data: Grove asks, and "add the data of this '
        'device" keeps the rows of the account', () async {
      final world = World();
      final file = fileWith(world, 'From the file');
      final a = world.device(seed: true);
      a.store.quickAdd('From the account');
      await signIn(a, me);
      final account = titles(a.store);

      final b = world.device(seed: true);
      b.store.quickAdd('Old one of the device');
      b.store.importData(file);
      await signIn(b, me);
      expect(b.store.firstSyncQuestion, isTrue);

      await b.store.answerFirstSync(FirstSyncChoice.addDevice);
      await idle(b.store);
      await a.store.syncNow();

      expect(titles(a.store), {...account, 'From the file'});
      expect(titles(b.store), titles(a.store));
    });

    test('an account with data: "use the data of the account" drops the rows '
        'of the file, and nothing of the file goes to the account', () async {
      final world = World();
      final file = fileWith(world, 'From the file');
      final a = world.device(seed: true);
      a.store.quickAdd('From the account');
      await signIn(a, me);
      final account = titles(a.store);
      final rows = world.of(me).count;

      final b = world.device(seed: true);
      b.store.importData(file);
      await signIn(b, me);
      await b.store.answerFirstSync(FirstSyncChoice.useAccount);
      await idle(b.store);

      expect(titles(b.store), account);
      expect(world.of(me).count, rows);
    });

    test('a setting the device had and the file has not: with "add the data '
        'of this device" it goes away on the account too', () async {
      final world = World();
      final file = fileWith(world, 'From the file');
      final a = world.device(seed: true);
      a.store.setTemplate(NoteKind.daily, '## Account\n');
      await signIn(a, me);

      final b = world.device(seed: true);
      b.store.setTemplate(NoteKind.daily, '## Device\n');
      b.store.importData(file);
      await signIn(b, me);
      await b.store.answerFirstSync(FirstSyncChoice.addDevice);
      await idle(b.store);
      await a.store.syncNow();

      // The import took the row away on the device, later than the account
      // wrote its own. The later change wins, as for each row (Q-22).
      expect(a.store.repos.settings.get('notes.dailyTemplate'), isNull);
      expect(b.store.repos.settings.get('notes.dailyTemplate'), isNull);
    });
  });

  group('The first sync after an import: a device that synced with the '
      'account before', () {
    test('sign out, import, sign in again: no question, and the rows of the '
        'file take the place of the rows of the account, '
        'on each device', () async {
      final world = World();
      final file = fileWith(world, 'From the file');
      final a = world.device(seed: true), b = world.device();
      a.store.quickAdd('From the account');
      await signIn(a, me);
      await signIn(b, me);
      expect(titles(b.store), contains('From the account'));

      await a.store.signOut();
      a.store.importData(file);
      await signIn(a, me);

      expect(a.store.firstSyncQuestion, isFalse);
      expect(a.store.syncStatus, SyncStatus.upToDate);
      expect(titles(a.store), {'From the file'});

      await b.store.syncNow();
      expect(titles(b.store), {'From the file'});
      // A third device, new, gets the file and nothing of before.
      final c = world.device();
      await signIn(c, me);
      expect(titles(c.store), {'From the file'});
    });

    test('a row another device made after the sign-out stays', () async {
      final world = World();
      final file = fileWith(world, 'From the file');
      final a = world.device(seed: true), b = world.device();
      await signIn(a, me);
      await signIn(b, me);

      await a.store.signOut();
      b.store.quickAdd('Made on the other device');
      await world.pass(longTime);
      a.store.importData(file);
      await signIn(a, me);
      await b.store.syncNow();

      expect(titles(a.store), {'From the file', 'Made on the other device'});
      expect(titles(b.store), titles(a.store));
    });

    test('sign in with another account: Grove asks before anything '
        'moves', () async {
      final world = World();
      final file = fileWith(world, 'From the file');
      final a = world.device(seed: true);
      await signIn(a, me);
      await a.store.signOut();
      a.store.importData(file);

      await signIn(a, other);
      expect(a.store.firstSyncQuestion, isTrue);
      expect(world.of(other).count, 0);
      expect(titles(a.store), {'From the file'});
    });
  });
}
