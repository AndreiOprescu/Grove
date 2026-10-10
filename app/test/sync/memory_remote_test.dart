import 'dart:typed_data';

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

void main() {
  late MemoryRemote remote;
  setUp(() => remote = MemoryRemote());

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
    await remote.push([change('a', 10)]);
    await remote.push([change('a', 11, deleted: true)]);
    final row = (await remote.pull(after: 0, limit: 10)).single;
    expect(row.deleted, isTrue);
  });

  test('the same key in two tables is two rows', () async {
    await remote.push([change('a', 10), change('a', 10, table: 'notes')]);
    expect((await pulled()).length, 2);
  });

  test(
    'a pull gives the rows after a number, lowest first, up to the limit',
    () async {
      await remote.push([for (var i = 0; i < 5; i++) change('k$i', 10)]);
      expect(await pulled(after: 1, limit: 2), ['2 k1 10', '3 k2 10']);
      expect(await pulled(after: 5), isEmpty);
    },
  );

  test('when it is offline, push and pull throw', () async {
    remote.offline = true;
    expect(
      () => remote.push([change('a', 1)]),
      throwsA(isA<RemoteUnavailable>()),
    );
    expect(
      () => remote.pull(after: 0, limit: 1),
      throwsA(isA<RemoteUnavailable>()),
    );
    remote.offline = false;
    expect(await pulled(), isEmpty);
  });

  test('a push can stop half way: the first rows are kept', () async {
    remote.failPushAfter = 1;
    await expectLater(
      remote.push([change('a', 1), change('b', 1)]),
      throwsA(isA<RemoteUnavailable>()),
    );
    expect(await pulled(), ['1 a 1']);
    await remote.push([change('a', 1), change('b', 1)]);
    expect(await pulled(), ['1 a 1', '2 b 1']);
  });

  test('the remote keeps its own copy of the data', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final data = <String, Object?>{'title': 'T', 'data': bytes};
    await remote.push([change('a', 1, data: data)]);
    data['title'] = 'changed';
    bytes[0] = 9;
    final first = (await remote.pull(after: 0, limit: 1)).single;
    expect(first.data['title'], 'T');
    expect(first.data['data'], [1, 2, 3]);
    first.data['title'] = 'changed again';
    final second = (await remote.pull(after: 0, limit: 1)).single;
    expect(second.data['title'], 'T');
  });
}
