import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/state/state.dart';

import '../state/support.dart' show makeStore;
import 'fake_supabase.dart';
import 'remote_contract.dart';
import 'support.dart';
import 'sync_engine_test.dart' show fill, randomOp;

void main() {
  late RemoteSchema schema;
  late FakeSupabase server;
  late SupabaseRemote remote;

  setUp(() {
    final db = Repos(Database.inMemory()).db;
    addTearDown(db.close);
    schema = RemoteSchema.read(db);
    server = FakeSupabase(schema);
    remote = SupabaseRemote(api: server, schema: schema);
  });

  group('The rules of every remote', () {
    remoteContract(
      make: () {
        final db = Repos(Database.inMemory()).db;
        addTearDown(db.close);
        final schema = RemoteSchema.read(db);
        return SupabaseRemote(api: FakeSupabase(schema), schema: schema);
      },
      offline: (remote, off) =>
          ((remote as SupabaseRemote).api as FakeSupabase).offline = off,
    );
  });

  group('Values', () {
    test('each value comes back with the type of its column', () async {
      final data = <String, Object?>{
        'id': 't1',
        'title': 'Buy milk',
        'notes': '',
        'list_id': null,
        'priority': 2,
        'estimate_min': null,
        'sort': 3.0,
        'created_at': '2026-10-11T09:00:00Z',
      };
      await remote.push([change('t1', 5, data: data)]);
      final row = (await remote.pull(after: 0, limit: 10)).single;
      for (final e in data.entries) {
        expect(row.data[e.key], e.value, reason: e.key);
        expect(row.data[e.key].runtimeType, e.value.runtimeType, reason: e.key);
      }
      expect(row.data['sort'], isA<double>());
      expect(row.table, 'tasks');
      expect(row.stamp, 5);
      expect(row.seq, 1);
    });

    test('a number with a part after the point stays as it is', () async {
      await remote.push([
        change('t1', 5, data: {'id': 't1', 'sort': 1.5}),
      ]);
      expect((await remote.pull(after: 0, limit: 1)).single.data['sort'], 1.5);
    });

    test('long text, quotes, new lines and emoji stay as they are', () async {
      final body = 'Line 1\nLine "2" \\ \u{1F33F} ${'x' * 5000} ; drop table';
      await remote.push([
        change('n1', 5, table: 'notes', data: {'id': 'n1', 'body': body}),
      ]);
      expect((await remote.pull(after: 0, limit: 1)).single.data['body'], body);
    });

    test('the character with code 0 is cut from a text', () async {
      await remote.push([
        change('t1', 5, data: {'id': 't1', 'title': 'a\u0000b'}),
      ]);
      expect(
        (await remote.pull(after: 0, limit: 1)).single.data['title'],
        'ab',
      );
    });

    test('a column the remote does not know is not sent', () async {
      await remote.push([
        change('t1', 5, data: {'id': 't1', 'title': 'T', 'not_there': 1}),
      ]);
      expect(server.lastPush, isNot(contains('not_there')));
      expect((await remote.pull(after: 0, limit: 1)).single.data['title'], 'T');
    });

    test('a table the remote does not know is an error', () async {
      await expectLater(
        remote.push([change('x', 1, table: 'not_a_table')]),
        throwsArgumentError,
      );
      expect(server.calls, isEmpty);
    });

    test('two changes of one row go in two calls, in order', () async {
      await remote.push([
        change('a', 10, data: {'title': 'first'}),
        change('b', 10),
        change('a', 11, data: {'title': 'second'}),
      ]);
      expect(server.calls, [SupabaseNames.push, SupabaseNames.push]);
      final rows = await remote.pull(after: 0, limit: 10);
      expect([for (final r in rows) r.key], ['b', 'a']);
      expect(rows.last.data['title'], 'second');
    });

    test('an empty push makes no call', () async {
      await remote.push(const []);
      expect(server.calls, isEmpty);
    });
  });

  group('What the server refuses', () {
    test('another schema number: no sync, and the error says so', () async {
      server.serverSchema = schema.version + 1;
      await expectLater(
        remote.push([change('a', 1)]),
        throwsA(isA<SchemaMismatch>()),
      );
      await expectLater(
        remote.pull(after: 0, limit: 1),
        throwsA(isA<SchemaMismatch>()),
      );
      expect(server.rowsOf('user-1'), isEmpty);
    });

    test('nobody is signed in', () async {
      server.userId = null;
      await expectLater(
        remote.push([change('a', 1)]),
        throwsA(isA<NotSignedIn>()),
      );
      await expectLater(
        remote.pull(after: 0, limit: 1),
        throwsA(isA<NotSignedIn>()),
      );
    });

    test('another error of the server comes out as it is', () async {
      await expectLater(
        remote.push([
          change('t1', 1, data: {'id': 't1', 'priority': 'high'}),
        ]),
        throwsA(isA<SupabaseApiError>().having((e) => e.code, 'code', '22P02')),
      );
      expect(server.rowsOf('user-1'), isEmpty);
    });

    test('a person gets only the rows of the person', () async {
      await remote.push([change('a', 1)]);
      server.userId = 'user-2';
      expect(await remote.pull(after: 0, limit: 10), isEmpty);
      await remote.push([change('a', 1), change('b', 1)]);
      expect((await remote.pull(after: 0, limit: 10)).length, 2);
      server.userId = 'user-1';
      expect((await remote.pull(after: 0, limit: 10)).single.key, 'a');
    });
  });

  group('Images', () {
    final bytes = Uint8List.fromList([137, 80, 78, 71, 0, 1, 2, 255]);
    Map<String, Object?> image(String id) => {
      'id': id,
      'mime': 'image/png',
      'data': bytes,
      'width': 4,
      'height': 2,
      'created_at': '2026-10-11T09:00:00Z',
    };
    const path = 'user-1/img1';
    const file = '${SupabaseNames.bucket}/$path';

    test('the bytes go to the file store, not in the row', () async {
      await remote.push([
        change('img1', 5, table: 'attachments', data: image('img1')),
      ]);
      expect(server.uploads, [path]);
      expect(server.files[file]!.bytes, bytes);
      expect(server.files[file]!.contentType, 'image/png');
      final sent = jsonDecode(server.lastPush) as Map<String, Object?>;
      final row = ((sent['p_changes'] as List).single as Map)['data'] as Map;
      expect(row.keys, isNot(contains('data')));
      expect(row['mime'], 'image/png');
      expect(row['width'], 4);
    });

    test('the file is saved before the row', () async {
      server.offline = true;
      await expectLater(
        remote.push([
          change('img1', 5, table: 'attachments', data: image('img1')),
        ]),
        throwsA(isA<RemoteUnavailable>()),
      );
      expect(server.files, isEmpty);
      expect(server.rowsOf('user-1'), isEmpty);
    });

    test('a pull brings the bytes back', () async {
      await remote.push([
        change('img1', 5, table: 'attachments', data: image('img1')),
      ]);
      final row = (await remote.pull(after: 0, limit: 10)).single;
      expect(row.data['data'], bytes);
      expect(row.data['data'], isA<Uint8List>());
      expect(row.data['mime'], 'image/png');
      expect(row.data['width'], 4);
      expect(server.downloads, [path]);
    });

    test('an image this device has is not downloaded', () async {
      final mine = SupabaseRemote(
        api: server,
        schema: schema,
        localImage: (id) => id == 'img1' ? bytes : null,
      );
      await mine.push([
        change('img1', 5, table: 'attachments', data: image('img1')),
      ]);
      final row = (await mine.pull(after: 0, limit: 10)).single;
      expect(row.data['data'], bytes);
      expect(server.downloads, isEmpty);
    });

    test('a deleted image has no bytes; its file is not touched', () async {
      await remote.push([
        change('img1', 5, table: 'attachments', data: image('img1')),
      ]);
      await remote.push([
        change('img1', 6, table: 'attachments', deleted: true),
      ]);
      expect(server.uploads, [path]);
      expect(server.files.keys, [file]);
      final row = (await remote.pull(after: 0, limit: 10)).single;
      expect(row.deleted, isTrue);
      expect(row.data, isEmpty);
      expect(server.downloads, isEmpty);
    });

    test('a row with no file comes with no bytes', () async {
      await remote.push([
        change('img1', 5, table: 'attachments', data: image('img1')),
      ]);
      server.files.clear();
      final row = (await remote.pull(after: 0, limit: 10)).single;
      expect(row.data.containsKey('data'), isFalse);
    });

    test('another person cannot read the file', () async {
      await remote.push([
        change('img1', 5, table: 'attachments', data: image('img1')),
      ]);
      server.userId = 'user-2';
      expect(await server.download(SupabaseNames.bucket, path), isNull);
      await expectLater(
        server.upload(
          SupabaseNames.bucket,
          path,
          bytes,
          contentType: 'image/png',
        ),
        throwsA(isA<SupabaseApiError>()),
      );
    });
  });

  group('The sync engine with the Supabase remote', () {
    Device device(FakeSupabase server, {int pageSize = 500}) {
      late final Device d;
      d = Device(
        SupabaseRemote(
          api: server,
          schema: schema,
          localImage: (id) => d.repos.attachments.get(id)?.data,
        ),
        pageSize: pageSize,
      );
      return d;
    }

    test('a second device gets every kind of row, and the image', () async {
      final a = device(server), b = device(server);
      fill(a);
      final image = a.repos.attachments.add(
        mime: 'image/png',
        data: Uint8List.fromList([1, 2, 3, 0, 255]),
        width: 2,
        height: 1,
      );
      await a.sync();
      final report = await b.sync();
      expect(report.skipped, isEmpty);
      for (final table in SyncMigrations.syncedTables) {
        expect(dump(b.db)[table], isNotEmpty, reason: table);
      }
      expectSame([a, b]);
      expect(b.repos.attachments.get(image.id)!.data, [1, 2, 3, 0, 255]);
      expect(server.uploads.where((p) => p == 'user-1/${image.id}').length, 1);
      expect(b.outbox.count, 0);
      final calls = server.calls.length;
      await b.sync();
      // Nothing to send: one pull, no push.
      expect(server.calls.skip(calls), [SupabaseNames.pull]);
    });

    test(
      'work in the app on two devices, offline, syncs to the same data',
      () async {
        final a = device(server), b = device(server);
        final storeA = makeStore(repos: a.repos);
        final storeB = makeStore(repos: b.repos);

        final milk = storeA.quickAdd('Buy milk #home')!;
        final note = storeA.newNote(title: 'Trip', body: 'Pack the tent');
        await settle([a, b]);
        expect(storeB.repos.tasks.get(milk.id)!.title, 'Buy milk');

        a.later();
        storeA.addSubtask(to: milk.id, title: 'Oat, not cow');
        storeA.quickAdd('Call mum tomorrow 6pm for 20m');
        b.later();
        storeB.toggleDone(taskId: milk.id);
        storeB.renameNote(note.id, to: 'Camping trip');
        storeB.quickAdd('Water the plants #home');
        // Offline: a sync fails and loses nothing.
        server.offline = true;
        await expectLater(a.sync(), throwsA(isA<RemoteUnavailable>()));
        await expectLater(b.sync(), throwsA(isA<RemoteUnavailable>()));
        server.offline = false;

        await settle([a, b]);
        expectSame([a, b]);
        expect(a.repos.tasks.get(milk.id)!.status, TaskStatus.done);
        expect(a.repos.tasks.subtasks(milk.id).single.title, 'Oat, not cow');
        expect(a.repos.notes.get(note.id)!.title, 'Camping trip');
        expect(a.repos.tags.all().length, 1);
        expect(b.repos.events.all().single.title, 'Call mum');
      },
    );

    for (var seed = 1; seed <= 10; seed++) {
      test(
        'random offline work on three devices ends the same (seed $seed)',
        () async {
          final rnd = Random(seed);
          final devices = [
            device(server, pageSize: 4),
            device(server, pageSize: 7),
            device(server, pageSize: 3),
          ];
          for (var step = 0; step < 90; step++) {
            final d = devices[rnd.nextInt(3)];
            if (rnd.nextInt(4) > 0) d.later();
            randomOp(d, rnd);
            if (rnd.nextInt(7) == 0) await devices[rnd.nextInt(3)].sync();
          }
          await settle(devices);
          expectSame(devices);
          final fresh = device(server);
          final report = await fresh.sync();
          expect(report.skipped, isEmpty);
          expect(fresh.outbox.count, 0);
          expect(dump(fresh.db), dump(devices.first.db));
        },
      );
    }
  });
}
