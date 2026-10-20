import 'package:flutter_test/flutter_test.dart';
import 'package:grove/sync/sync.dart';

import 'support.dart';

void main() {
  ({AppStore store, MemoryRemote remote}) signedIn() {
    final remote = MemoryRemote();
    final auth = MemoryAuth(
      account: const Account(userId: 'user-1', email: 'me@example.com'),
    );
    final store = AppStore(
      repos: Repos(Database.inMemory()),
      syncBackend: SyncBackend(auth: auth, remote: (_) => remote),
    );
    addTearDown(() {
      if (!store.isDisposed) store.dispose();
      auth.dispose();
    });
    return (store: store, remote: remote);
  }

  test('a check brings in what another device made', () async {
    final d = signedIn();
    await d.store.syncTask;
    final schedule = SyncSchedule(d.store);
    await d.remote.push([
      const RowChange(
        table: 'settings',
        key: 'theme',
        stamp: 5,
        deleted: false,
        data: {'key': 'theme', 'value': 'dark'},
      ),
    ]);

    schedule.check();
    await d.store.syncTask;

    expect(d.store.repos.settings.get('theme'), 'dark');
  });

  test('the timer checks again and again, and stops', () async {
    final d = signedIn();
    await d.store.syncTask;
    final pulls = d.remote.pullCalls;
    final schedule = SyncSchedule(
      d.store,
      every: const Duration(milliseconds: 20),
    )..start();
    await wait(90);
    schedule.dispose();
    await d.store.syncTask;
    final after = d.remote.pullCalls;
    expect(after, greaterThan(pulls + 1));
    await wait(60);
    expect(d.remote.pullCalls, after);
  });

  test('with nobody signed in a check does nothing', () async {
    final store = makeStore();
    SyncSchedule(store).check();
    expect(store.syncTask, isNull);
  });

  test('a check after the store is closed does nothing', () async {
    final d = signedIn();
    await d.store.syncTask;
    final schedule = SyncSchedule(d.store);
    d.store.dispose();
    schedule.check();
  });
}
