// Shared helpers for the tests of the login and the sync in the store.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/sync/sync.dart';

import 'support.dart';

export 'package:grove/sync/sync.dart';

export 'support.dart';

/// A remote that can fail in a chosen way.
class CountingRemote extends MemoryRemote {
  Exception? failure;

  /// How many changes the remote kept, in all.
  int get count => lastSeq;
  int get pushes => pushCalls;
  int get pulls => pullCalls;

  @override
  Future<void> push(List<RowChange> changes) async {
    if (failure case final f?) throw f;
    await super.push(changes);
  }

  @override
  Future<List<RowChange>> pull({required int after, required int limit}) async {
    if (failure case final f?) throw f;
    return super.pull(after: after, limit: limit);
  }
}

/// One Supabase project in memory: one login, and one set of rows for each
/// person.
class World {
  final auths = <MemoryAuth>[];
  final remotes = <String, CountingRemote>{};

  /// The timers of the devices. They run when [pass] says that time passed.
  final timers = ManualTimers();
  final _stores = <AppStore>[];

  CountingRemote of(String email) =>
      remotes.putIfAbsent(MemoryAuth.userIdOf(email), CountingRemote.new);

  /// Lets [time] pass on each device, and waits for the syncs this starts.
  /// No real time passes, so a slow machine gives the same result.
  Future<void> pass(Duration time) async {
    timers.pass(time);
    // One turn of the event loop: a wait that ended starts its sync.
    await Future<void>.delayed(Duration.zero);
    for (final store in _stores) {
      if (!store.isDisposed) await idle(store);
    }
  }

  /// A device with Grove on it. [signedIn]: the device has a session from
  /// the last time the app ran. [realTime]: the waits of the store use real
  /// timers, with a short wait before a sync. For a widget test, where
  /// `tester.pump` moves the clock.
  ({AppStore store, MemoryAuth auth}) device({
    String? signedIn,
    String? dataDir,
    Repos? repos,
    Prefs? prefs,
    bool seed = false,
    bool realTime = false,
  }) {
    final auth = MemoryAuth(
      account: signedIn == null
          ? null
          : Account(userId: MemoryAuth.userIdOf(signedIn), email: signedIn),
    );
    auths.add(auth);
    final r = repos ?? Repos(Database.inMemory());
    if (seed) FirstRun.seedIfNew(r, today: DayKey('2026-10-11'));
    final store = AppStore(
      repos: r,
      prefs: prefs,
      dataDir: dataDir,
      syncBackend: SyncBackend(
        auth: auth,
        remote: (_) => PersonRemote(this, auth),
      ),
    );
    if (realTime) {
      store.syncDelay = const Duration(milliseconds: 20);
    } else {
      store.newTimer = timers.start;
      _stores.add(store);
    }
    addTearDown(() {
      if (!store.isDisposed) store.dispose();
      auth.dispose();
    });
    return (store: store, auth: auth);
  }
}

/// The remote of the person who is signed in, as row level security gives
/// it: each person has rows of their own.
class PersonRemote implements SyncRemote {
  PersonRemote(this.world, this.auth);

  final World world;
  final MemoryAuth auth;

  CountingRemote get _mine {
    final account = auth.account;
    if (account == null) throw const NotSignedIn();
    return world.of(account.email);
  }

  @override
  Future<void> push(List<RowChange> changes) async => _mine.push(changes);

  @override
  Future<List<RowChange>> pull({required int after, required int limit}) =>
      Future.sync(() => _mine.pull(after: after, limit: limit));
}

/// Waits until the sync has nothing more to do.
Future<void> idle(AppStore store) async {
  for (var i = 0; i < 50; i++) {
    final task = store.syncTask;
    if (task == null) return;
    await task;
  }
  fail('The sync never came to an end.');
}

Future<void> signIn(({AppStore store, MemoryAuth auth}) d, String email) async {
  expect(await d.store.sendLoginLink(email), isTrue);
  expect(await d.store.verifyLoginCode(d.auth.code), isTrue);
  await idle(d.store);
}

Set<String> titles(AppStore s) => {
  for (final t in s.repos.tasks.all()) t.title,
};

const me = 'me@example.com';
const other = 'other@example.com';
