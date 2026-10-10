import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

RowChange change(
  String key,
  int stamp, {
  String table = 'tasks',
  bool deleted = false,
  Map<String, Object?> data = const {},
}) => RowChange(
  table: table,
  key: key,
  stamp: stamp,
  deleted: deleted,
  data: data,
);

/// The rules every remote must keep (`SyncRemote`). Each kind of remote runs
/// these same checks: the one in memory, the Supabase one over a fake
/// server, and the Supabase one over a real Postgres.
///
/// [make] gives a new, empty remote. [offline] takes the remote off the
/// network, or puts it back.
void remoteContract({
  required FutureOr<SyncRemote> Function() make,
  required void Function(SyncRemote remote, bool offline) offline,
}) {
  late SyncRemote remote;
  setUp(() async => remote = await make());

  Future<List<String>> pulled({int after = 0, int limit = 100}) async => [
    for (final c in await remote.pull(after: after, limit: limit))
      '${c.seq} ${c.key} ${c.stamp}',
  ];

  test('a new row is kept and gets the next number', () async {
    await remote.push([change('a', 10), change('b', 10)]);
    expect(await pulled(), ['1 a 10', '2 b 10']);
  });

  test(
    'a newer change takes the place of the row and gets a new number',
    () async {
      await remote.push([change('a', 10), change('b', 10)]);
      await remote.push([change('a', 11)]);
      expect(await pulled(), ['2 b 10', '3 a 11']);
    },
  );

  test('a row with stamp 0 is kept when the remote has no such row', () async {
    await remote.push([
      change('a', 0, data: {'title': 'old file'}),
    ]);
    expect(
      (await remote.pull(after: 0, limit: 10)).single.data['title'],
      'old file',
    );
    await remote.push([
      change('a', 0, data: {'title': 'again'}),
    ]);
    expect(
      (await remote.pull(after: 0, limit: 10)).single.data['title'],
      'old file',
    );
  });

  test('an older change and a change of the same age are refused', () async {
    await remote.push([
      change('a', 10, data: {'title': 'first'}),
    ]);
    await remote.push([
      change('a', 9, data: {'title': 'older'}),
      change('a', 10, data: {'title': 'same age'}),
    ]);
    final row = (await remote.pull(after: 0, limit: 10)).single;
    expect(row.data['title'], 'first');
    expect(row.seq, 1);
  });

  test('a delete is a row too', () async {
    await remote.push([
      change('a', 10, data: {'title': 'T'}),
    ]);
    await remote.push([change('a', 11, deleted: true)]);
    final row = (await remote.pull(after: 0, limit: 10)).single;
    expect(row.deleted, isTrue);
    expect(row.stamp, 11);
    expect(row.data['title'], isNull);
  });

  test('a newer change brings a deleted row back', () async {
    await remote.push([change('a', 10, deleted: true)]);
    await remote.push([
      change('a', 11, data: {'title': 'back'}),
    ]);
    final row = (await remote.pull(after: 0, limit: 10)).single;
    expect(row.deleted, isFalse);
    expect(row.data['title'], 'back');
  });

  test('the same key in two tables is two rows', () async {
    await remote.push([change('a', 10), change('a', 10, table: 'notes')]);
    expect((await pulled()).length, 2);
  });

  test('a key with more than one part comes back the same', () async {
    final key = SyncSchema.key(['task', 't1', 'note', 'n1']);
    await remote.push([change(key, 10, table: 'links')]);
    final row = (await remote.pull(after: 0, limit: 10)).single;
    expect(row.table, 'links');
    expect(row.key, key);
  });

  test(
    'a pull gives the rows after a number, lowest first, up to the limit',
    () async {
      await remote.push([for (var i = 0; i < 5; i++) change('k$i', 10)]);
      expect(await pulled(after: 1, limit: 2), ['2 k1 10', '3 k2 10']);
      expect(await pulled(after: 5), isEmpty);
    },
  );

  test('rows of many tables come in the order they were kept', () async {
    await remote.push([
      change('n', 10, table: 'notes'),
      change('t', 10),
      change('l', 10, table: 'lists'),
    ]);
    await remote.push([change('t2', 10)]);
    expect(await pulled(limit: 3), ['1 n 10', '2 t 10', '3 l 10']);
    expect(await pulled(after: 3), ['4 t2 10']);
  });

  test('when it is offline, push and pull throw', () async {
    offline(remote, true);
    await expectLater(
      remote.push([change('a', 1)]),
      throwsA(isA<RemoteUnavailable>()),
    );
    await expectLater(
      remote.pull(after: 0, limit: 1),
      throwsA(isA<RemoteUnavailable>()),
    );
    offline(remote, false);
    expect(await pulled(), isEmpty);
  });

  test('the remote keeps its own copy of the data', () async {
    final data = <String, Object?>{'title': 'T'};
    await remote.push([change('a', 1, data: data)]);
    data['title'] = 'changed';
    final first = (await remote.pull(after: 0, limit: 1)).single;
    expect(first.data['title'], 'T');
    first.data['title'] = 'changed again';
    final second = (await remote.pull(after: 0, limit: 1)).single;
    expect(second.data['title'], 'T');
  });
}
