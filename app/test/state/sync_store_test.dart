import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'sync_support.dart';

/// The smallest step of the clock of the tests.
const oneTick = Duration(milliseconds: 1);

/// Much longer than any wait of the store.
const longTime = Duration(hours: 1);

void main() {
  group('A build with no keys', () {
    test('Grove works, with no login and no sync', () async {
      final timers = ManualTimers();
      final store = makeStore()..newTimer = timers.start;
      expect(store.syncAvailable, isFalse);
      expect(store.syncStatus, SyncStatus.off);
      expect(store.isSignedIn, isFalse);
      expect(await store.sendLoginLink(me), isFalse);
      await store.syncNow();
      await store.signOut();
      store.quickAdd('Buy milk');
      // No sync waits for its time.
      expect(timers.waiting, 0);
      expect(store.syncTask, isNull);
      expect(store.syncError, isNull);
      expect(store.lastSyncAt, isNull);
    });
  });

  group('The login', () {
    test('the email, then the code', () async {
      final world = World();
      final d = world.device();
      final store = d.store;
      expect(store.syncAvailable, isTrue);
      expect(store.syncStatus, SyncStatus.signedOut);
      expect(store.loginStep, LoginStep.email);

      expect(await store.sendLoginLink('  $me '), isTrue);
      expect(d.auth.sent, [me]);
      expect(store.loginStep, LoginStep.code);
      expect(store.loginEmail, me);
      expect(store.loginError, isNull);
      expect(store.isSignedIn, isFalse);

      expect(await store.verifyLoginCode(' 123 456 '), isTrue);
      expect(store.isSignedIn, isTrue);
      expect(store.syncAccount!.email, me);
      expect(store.loginStep, LoginStep.email);
      await idle(store);
    });

    test('a text that is not an email address sends nothing', () async {
      final d = World().device();
      for (final bad in ['', 'me', 'me@', '@example.com', 'a b@example.com']) {
        expect(await d.store.sendLoginLink(bad), isFalse, reason: bad);
      }
      expect(d.auth.sent, isEmpty);
      expect(d.store.loginError, 'This is not an email address.');
      expect(d.store.loginStep, LoginStep.email);
    });

    test('a wrong code does not sign in, and the next code can', () async {
      final d = World().device();
      await d.store.sendLoginLink(me);
      expect(await d.store.verifyLoginCode('000000'), isFalse);
      expect(d.store.isSignedIn, isFalse);
      expect(d.store.loginError, contains('wrong or too old'));
      expect(d.store.loginStep, LoginStep.code);
      expect(await d.store.verifyLoginCode(''), isFalse);
      expect(await d.store.verifyLoginCode('123456'), isTrue);
      expect(d.store.loginError, isNull);
      await idle(d.store);
    });

    test('no code is checked before an email is sent', () async {
      final d = World().device();
      expect(await d.store.verifyLoginCode('123456'), isFalse);
      expect(d.store.isSignedIn, isFalse);
    });

    test('with no connection the form says so', () async {
      final d = World().device();
      d.auth.offline = true;
      expect(await d.store.sendLoginLink(me), isFalse);
      expect(d.store.loginError, contains('No connection'));
      expect(d.store.loginBusy, isFalse);
      d.auth.offline = false;
      expect(await d.store.sendLoginLink(me), isTrue);
      expect(d.store.loginError, isNull);
    });

    test('too many emails: the form says wait', () async {
      final d = World().device();
      d.auth.nextFailure = const AuthFailure(AuthProblem.tooMany);
      expect(await d.store.sendLoginLink(me), isFalse);
      expect(d.store.loginError, contains('Wait a minute'));
    });

    test('the form is busy while the email is sent', () async {
      final d = World().device();
      final seen = <bool>[];
      d.store.addListener(() => seen.add(d.store.loginBusy));
      final sending = d.store.sendLoginLink(me);
      expect(d.store.loginBusy, isTrue);
      // A second tap does nothing.
      expect(await d.store.sendLoginLink(me), isFalse);
      await sending;
      expect(d.store.loginBusy, isFalse);
      expect(d.auth.sent, [me]);
      expect(seen, [true, false]);
    });

    test('"use another address" goes back to the email box', () async {
      final d = World().device();
      await d.store.sendLoginLink(me);
      await d.store.verifyLoginCode('000000');
      d.store.changeLoginEmail();
      expect(d.store.loginStep, LoginStep.email);
      expect(d.store.loginError, isNull);
    });

    test('the link of the email signs in too', () async {
      final d = World().device();
      await d.store.sendLoginLink(me);
      d.auth.openLink(me);
      expect(d.store.isSignedIn, isTrue);
      await idle(d.store);
      expect(d.store.syncStatus, SyncStatus.upToDate);
    });
  });

  group('The first login of a device', () {
    test('an account with no data gets the data of the device, '
        'with no question', () async {
      final world = World();
      final d = world.device(seed: true);
      d.store.quickAdd('Buy milk');
      await signIn(d, me);

      expect(d.store.firstSyncQuestion, isFalse);
      expect(d.store.syncStatus, SyncStatus.upToDate);
      expect(d.store.syncError, isNull);
      expect(d.store.syncWaiting, 0);
      expect(d.store.lastSyncAt, isNotNull);

      final second = world.device();
      await signIn(second, me);
      expect(second.store.firstSyncQuestion, isFalse);
      expect(titles(second.store), titles(d.store));
      expect(titles(second.store), contains('Buy milk'));
      expect(second.store.repos.lists.all().length, 3);
    });

    test('a device with no data gets the data of the account, '
        'with no question', () async {
      final world = World();
      final a = world.device(seed: true);
      await signIn(a, me);

      final b = world.device();
      var told = 0;
      b.store.addListener(() => told += 1);
      await signIn(b, me);

      expect(b.store.firstSyncQuestion, isFalse);
      expect(b.store.syncStatus, SyncStatus.upToDate);
      expect(titles(b.store), titles(a.store));
      expect(told, greaterThan(0));
      // The account was seeded on the first device. This device does not
      // seed again at its next start.
      expect(b.store.repos.settings.get(FirstRun.doneKey), isNotNull);
      expect(b.store.welcomeVisible, isTrue);
    });

    test('device and account both have data: Grove asks, '
        'and nothing moves before the answer', () async {
      final world = World();
      final a = world.device(seed: true);
      a.store.quickAdd('From the account');
      await signIn(a, me);
      final account = world.of(me);
      final rows = account.count;

      final b = world.device(seed: true);
      b.store.quickAdd('From the device');
      final before = titles(b.store);
      await signIn(b, me);

      expect(b.store.firstSyncQuestion, isTrue);
      expect(b.store.syncStatus, SyncStatus.question);
      expect(titles(b.store), before);
      expect(account.count, rows);
      expect(account.pushes, 1);

      // No sync runs before the answer: not by hand, not after a change.
      await b.store.syncNow();
      b.store.quickAdd('One more');
      await world.pass(longTime);
      expect(account.count, rows);
      expect(account.pushes, 1);
      expect(b.store.lastSyncAt, isNull);
    });

    test('answer "add the data of this device": both are there', () async {
      final world = World();
      final a = world.device(seed: true);
      a.store.quickAdd('From the account');
      await signIn(a, me);
      final b = world.device(seed: true);
      b.store.quickAdd('From the device');
      await signIn(b, me);

      await b.store.answerFirstSync(FirstSyncChoice.addDevice);
      await idle(b.store);
      await a.store.syncNow();

      expect(b.store.firstSyncQuestion, isFalse);
      expect(b.store.syncStatus, SyncStatus.upToDate);
      expect(
        titles(b.store),
        containsAll(['From the account', 'From the device']),
      );
      expect(titles(a.store), titles(b.store));
      // Both devices made the sample lists, so they are there two times.
      expect(a.store.repos.lists.all().length, 6);
    });

    test('answer "use the data of the account": the device is replaced, '
        'and a copy of its data is saved first', () async {
      final dir = Directory.systemTemp.createTempSync('grove-sync-store');
      addTearDown(() => dir.deleteSync(recursive: true));
      final world = World();
      final a = world.device(seed: true);
      a.store.quickAdd('From the account');
      await signIn(a, me);
      final rows = world.of(me).count;

      final b = world.device(seed: true, dataDir: dir.path);
      final mine = b.store.quickAdd('From the device')!;
      b.store.selectedTaskId = mine.id;
      await signIn(b, me);
      expect(b.store.firstSyncQuestion, isTrue);

      await b.store.answerFirstSync(FirstSyncChoice.useAccount);
      await idle(b.store);

      expect(b.store.firstSyncQuestion, isFalse);
      expect(b.store.syncStatus, SyncStatus.upToDate);
      expect(titles(b.store), titles(a.store));
      expect(titles(b.store), isNot(contains('From the device')));
      expect(b.store.repos.lists.all().length, 3);
      expect(b.store.selectedTaskId, isNull);
      expect(b.store.undoStack, isEmpty);
      expect(b.store.toast, isNotNull);
      // Nothing of the device went to the account.
      expect(world.of(me).count, rows);

      final copies = [
        for (final f in dir.listSync().whereType<File>())
          if (f.uri.pathSegments.last.startsWith('before-sync-')) f,
      ];
      expect(copies, hasLength(1));
      final copy = Database.open(copies.single.path);
      addTearDown(copy.close);
      expect(
        Repos(copy).tasks.all().map((t) => t.title),
        contains('From the device'),
      );
    });

    test('"use the data of the account" with no connection: '
        'the device keeps its data and the question stays', () async {
      final world = World();
      final a = world.device(seed: true);
      await signIn(a, me);
      final b = world.device(seed: true);
      b.store.quickAdd('From the device');
      await signIn(b, me);

      world.of(me).offline = true;
      await b.store.answerFirstSync(FirstSyncChoice.useAccount);
      expect(b.store.firstSyncQuestion, isTrue);
      expect(b.store.syncError, contains('No connection'));
      expect(titles(b.store), contains('From the device'));

      world.of(me).offline = false;
      await b.store.answerFirstSync(FirstSyncChoice.useAccount);
      expect(b.store.firstSyncQuestion, isFalse);
      expect(b.store.syncError, isNull);
      expect(titles(b.store), titles(a.store));
    });

    test('with no connection at the login, the next sync asks again', () async {
      final world = World();
      final a = world.device(seed: true);
      await signIn(a, me);
      final b = world.device(seed: true);
      world.of(me).offline = true;
      await signIn(b, me);
      expect(b.store.isSignedIn, isTrue);
      expect(b.store.firstSyncQuestion, isFalse);
      expect(b.store.syncStatus, SyncStatus.error);
      expect(b.store.syncError, contains('No connection'));

      world.of(me).offline = false;
      await b.store.syncNow();
      expect(b.store.firstSyncQuestion, isTrue);
      expect(b.store.syncError, isNull);
    });

    test('the question is asked one time: the next start just syncs', () async {
      final world = World();
      final a = world.device(seed: true);
      await signIn(a, me);
      final repos = Repos(Database.inMemory());
      final b = world.device(seed: true, repos: repos);
      await signIn(b, me);
      await b.store.answerFirstSync(FirstSyncChoice.addDevice);
      await idle(b.store);

      // The app starts again on the same database, with the session kept.
      a.store.quickAdd('Made while b was closed');
      await world.pass(a.store.syncDelay);
      final again = world.device(repos: repos, signedIn: me);
      await idle(again.store);
      expect(again.store.isSignedIn, isTrue);
      expect(again.store.firstSyncQuestion, isFalse);
      expect(again.store.syncStatus, SyncStatus.upToDate);
      expect(titles(again.store), contains('Made while b was closed'));
    });
  });

  group('When a sync runs', () {
    test('a change goes to the account some moments later', () async {
      final world = World();
      final a = world.device(), b = world.device();
      await signIn(a, me);
      await signIn(b, me);

      final pushes = world.of(me).pushes;
      a.store.quickAdd('Buy milk');
      expect(a.store.syncWaiting, greaterThan(0));
      // Nothing goes before the wait of the store is over.
      await world.pass(a.store.syncDelay - oneTick);
      expect(a.store.syncWaiting, greaterThan(0));
      expect(world.of(me).pushes, pushes);
      await world.pass(oneTick);
      expect(a.store.syncWaiting, 0);
      expect(world.of(me).pushes, pushes + 1);

      await b.store.syncNow();
      expect(titles(b.store), {'Buy milk'});
    });

    test('many changes in a row are one sync', () async {
      final world = World();
      final a = world.device();
      await signIn(a, me);
      final pushes = world.of(me).pushes;
      // Each change starts the wait again.
      for (var i = 0; i < 5; i++) {
        a.store.quickAdd('Task $i');
        await world.pass(a.store.syncDelay - oneTick);
      }
      expect(world.of(me).pushes, pushes);
      await world.pass(oneTick);
      expect(world.of(me).pushes, pushes + 1);
      await world.pass(longTime);
      expect(world.of(me).pushes, pushes + 1);
      expect(world.of(me).count, greaterThanOrEqualTo(5));
    });

    test('a change of the screen only sends nothing', () async {
      final world = World();
      final a = world.device();
      await signIn(a, me);
      final pulls = world.of(me).pulls;
      a.store.selectedTaskId = null;
      a.store.showToast('Hello');
      await world.pass(longTime);
      expect(world.of(me).pulls, pulls);
    });

    test('rows that come in do not start a sync again', () async {
      final world = World();
      final a = world.device(), b = world.device();
      await signIn(a, me);
      await signIn(b, me);
      a.store.quickAdd('Buy milk');
      await a.store.syncNow();
      await b.store.syncNow();
      final pulls = world.of(me).pulls;
      await world.pass(longTime);
      expect(world.of(me).pulls, pulls);
    });

    test('the screens hear about rows that come in', () async {
      final world = World();
      final a = world.device(), b = world.device();
      await signIn(a, me);
      await signIn(b, me);
      final task = a.store.quickAdd('Buy milk')!;
      await a.store.syncNow();
      await b.store.syncNow();
      b.store.selectedTaskId = task.id;
      b.store.selection = {task.id};
      final revision = b.store.revision;

      a.store.deleteTask(task.id);
      await a.store.syncNow();
      await b.store.syncNow();

      expect(b.store.revision, greaterThan(revision));
      expect(b.store.selectedTaskId, isNull);
      expect(b.store.selection, isEmpty);
      expect(titles(b.store), isEmpty);
    });

    test('a second call during a sync gives the same sync', () async {
      final world = World();
      final a = world.device();
      await signIn(a, me);
      a.store.quickAdd('Buy milk');
      final pushes = world.of(me).pushes;
      final one = a.store.syncNow();
      final two = a.store.syncNow();
      expect(a.store.isSyncing, isTrue);
      expect(a.store.syncStatus, SyncStatus.syncing);
      await Future.wait([one, two]);
      expect(world.of(me).pushes, pushes + 1);
      expect(a.store.isSyncing, isFalse);
    });

    test('the time of the last sync is kept for the next start', () async {
      final world = World();
      final prefs = MemoryPrefs();
      final repos = Repos(Database.inMemory());
      final a = world.device(prefs: prefs, repos: repos);
      expect(a.store.lastSyncAt, isNull);
      final before = DateTime.now();
      await signIn(a, me);
      final at = a.store.lastSyncAt!;
      expect(at.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);

      final again = world.device(prefs: prefs, repos: repos);
      expect(again.store.lastSyncAt, at);
    });

    test('a store that is closed during a sync stays quiet', () async {
      final world = World();
      final a = world.device();
      await signIn(a, me);
      a.store.quickAdd('Buy milk');
      final sync = a.store.syncNow();
      a.store.dispose();
      await sync;
      // A closed store leaves no timer behind.
      expect(world.timers.waiting, 0);
      await world.pass(longTime);
    });
  });

  group('When the sync fails', () {
    test('no connection: the changes wait, and go later', () async {
      final world = World();
      final a = world.device(), b = world.device();
      await signIn(a, me);
      await signIn(b, me);
      final last = a.store.lastSyncAt;

      world.of(me).offline = true;
      a.store.quickAdd('Made offline');
      await world.pass(a.store.syncDelay);
      expect(a.store.syncStatus, SyncStatus.error);
      expect(a.store.syncError, contains('No connection'));
      expect(a.store.syncWaiting, greaterThan(0));
      expect(a.store.lastSyncAt, last);
      expect(titles(a.store), {'Made offline'});

      world.of(me).offline = false;
      await a.store.syncNow();
      expect(a.store.syncError, isNull);
      expect(a.store.syncStatus, SyncStatus.upToDate);
      expect(a.store.syncWaiting, 0);
      await b.store.syncNow();
      expect(titles(b.store), {'Made offline'});
    });

    test('after an error there is no new try again and again', () async {
      final world = World();
      final a = world.device();
      await signIn(a, me);
      world.of(me).offline = true;
      a.store.quickAdd('Made offline');
      await world.pass(a.store.syncDelay);
      expect(a.store.syncStatus, SyncStatus.error);
      final pushes = world.of(me).pushes;
      final pulls = world.of(me).pulls;
      // No timer waits for a new try.
      expect(world.timers.waiting, 0);
      await world.pass(longTime);
      expect(world.of(me).pushes, pushes);
      expect(world.of(me).pulls, pulls);
    });

    test('an app with another schema number is told to update', () async {
      final world = World();
      final a = world.device();
      await signIn(a, me);
      world.of(me).failure = const SchemaMismatch('server 8, app 7');
      a.store.quickAdd('Buy milk');
      await a.store.syncNow();
      expect(a.store.syncError, contains('Update Grove'));
      expect(a.store.syncWaiting, greaterThan(0));
    });

    test('a login that ended is said so', () async {
      final world = World();
      final a = world.device();
      await signIn(a, me);
      world.of(me).failure = const NotSignedIn();
      await a.store.syncNow();
      expect(a.store.syncError, contains('Sign in again'));
    });

    test('what the server says is shown', () async {
      final world = World();
      final a = world.device();
      await signIn(a, me);
      world.of(me).failure = const SupabaseApiError(
        'permission denied',
        code: '42501',
      );
      a.store.quickAdd('Buy milk');
      await a.store.syncNow();
      expect(a.store.syncError, contains('permission denied'));
    });
  });

  group('Sign out', () {
    test('the data of the device and of the account stay', () async {
      final world = World();
      final a = world.device(seed: true);
      a.store.quickAdd('Buy milk');
      await signIn(a, me);
      final rows = world.of(me).count;
      final before = titles(a.store);

      await a.store.signOut();

      expect(a.store.isSignedIn, isFalse);
      expect(a.store.syncStatus, SyncStatus.signedOut);
      expect(a.store.loginStep, LoginStep.email);
      expect(titles(a.store), before);
      expect(world.of(me).count, rows);
    });

    test('no sync runs while signed out, and the changes go at the '
        'next login, with no question', () async {
      final world = World();
      final a = world.device(seed: true), b = world.device();
      await signIn(a, me);
      await signIn(b, me);
      await a.store.signOut();
      final pushes = world.of(me).pushes;

      a.store.quickAdd('Made while signed out');
      await a.store.syncNow();
      await world.pass(longTime);
      expect(world.of(me).pushes, pushes);

      await signIn(a, me);
      expect(a.store.firstSyncQuestion, isFalse);
      await b.store.syncNow();
      expect(titles(b.store), contains('Made while signed out'));
    });

    test('a session the server ended signs the device out', () async {
      final world = World();
      final a = world.device(seed: true);
      await signIn(a, me);
      a.auth.expire();
      expect(a.store.isSignedIn, isFalse);
      expect(a.store.syncStatus, SyncStatus.signedOut);
      expect(titles(a.store), isNotEmpty);
    });

    test('a login with another account asks before anything moves', () async {
      final world = World();
      final a = world.device(seed: true);
      a.store.quickAdd('Mine');
      await signIn(a, me);
      await a.store.signOut();

      await signIn(a, other);

      // The account is empty, but the data of this device is of another
      // account. Grove does not put it there without a word.
      expect(a.store.firstSyncQuestion, isTrue);
      expect(world.of(other).count, 0);
      expect(titles(a.store), contains('Mine'));

      await a.store.answerFirstSync(FirstSyncChoice.addDevice);
      await idle(a.store);
      expect(world.of(other).count, greaterThan(0));
      expect(titles(a.store), contains('Mine'));
    });
  });
}
