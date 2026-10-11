import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'remote_contract.dart';
import 'support.dart';

void main() {
  group('The rules of every remote', () {
    remoteContract(
      make: MemoryRemote.new,
      offline: (remote, off) => (remote as MemoryRemote).offline = off,
    );
  });

  late MemoryRemote remote;
  setUp(() => remote = MemoryRemote());

  Future<List<String>> pulled({int after = 0, int limit = 100}) async => [
    for (final c in await remote.pull(after: after, limit: limit))
      '${c.seq} ${c.key} ${c.stamp}',
  ];

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
