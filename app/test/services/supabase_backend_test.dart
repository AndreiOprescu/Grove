import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/services/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/remote_contract.dart';
import '../sync/support.dart';
import '../sync/sync_engine_test.dart' show fill;
import 'local_supabase.dart';

// The real Supabase package talks to a web server on this computer
// (127.0.0.1). No call leaves the computer. This file does not start the
// Flutter test binding, because the binding stops all web calls.

RemoteSchema appSchema() {
  final db = Repos(Database.inMemory()).db;
  addTearDown(db.close);
  return RemoteSchema.read(db);
}

Future<LocalSupabase> startServer() async {
  final local = await LocalSupabase.start(appSchema());
  addTearDown(local.stop);
  return local;
}

SupabaseClient clientFor(LocalSupabase local) {
  final client = SupabaseClient(
    local.url,
    'test-key',
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.implicit,
    ),
  );
  addTearDown(client.dispose);
  return client;
}

Future<SupabaseClient> signedIn(LocalSupabase local, String email) async {
  final client = clientFor(local);
  final auth = SupabaseAuth(client.auth);
  await auth.sendLink(email);
  await auth.verifyCode(email: email, code: local.code);
  return client;
}

const me = 'me@example.com';

void main() {
  group('The login', () {
    test('the email is asked for, then the code signs in', () async {
      final local = await startServer();
      final auth = SupabaseAuth(clientFor(local).auth);
      final seen = <Account?>[];
      final listening = auth.changes.listen(seen.add);
      addTearDown(listening.cancel);
      expect(auth.account, isNull);

      await auth.sendLink(me);
      expect(local.sent, [me]);
      expect(local.requests, contains('POST /auth/v1/otp'));
      expect(auth.account, isNull);

      await auth.verifyCode(email: me, code: local.code);
      await pumpEventQueue();
      final account = Account(userId: LocalSupabase.userIdOf(me), email: me);
      expect(auth.account, account);
      expect(seen.last, account);

      await auth.signOut();
      await pumpEventQueue();
      expect(auth.account, isNull);
      expect(seen.last, isNull);
      expect(local.requests, contains('POST /auth/v1/logout'));
    });

    test('a wrong code is "the code is wrong or too old"', () async {
      final local = await startServer();
      final auth = SupabaseAuth(clientFor(local).auth);
      await auth.sendLink(me);
      await expectLater(
        auth.verifyCode(email: me, code: '000000'),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.problem,
            'problem',
            AuthProblem.badCode,
          ),
        ),
      );
      expect(auth.account, isNull);
    });

    test('too many emails is "wait"', () async {
      final local = await startServer();
      final auth = SupabaseAuth(clientFor(local).auth);
      local.tooMany = true;
      await expectLater(
        auth.sendLink(me),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.problem,
            'problem',
            AuthProblem.tooMany,
          ),
        ),
      );
    });

    test('a server that does not answer is "no connection"', () async {
      final local = await startServer();
      final auth = SupabaseAuth(clientFor(local).auth);
      local.down = true;
      await expectLater(
        auth.sendLink(me),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.problem,
            'problem',
            AuthProblem.offline,
          ),
        ),
      );
    });

    test('what the package says, as a problem the form knows', () {
      AuthProblem of(AuthException e, {bool codeStep = false}) =>
          SupabaseAuth.failureOf(e, codeStep: codeStep).problem;
      expect(of(AuthRetryableFetchException()), AuthProblem.offline);
      expect(
        of(const AuthApiException('x', statusCode: '429')),
        AuthProblem.tooMany,
      );
      expect(
        of(const AuthApiException('x', code: 'over_request_rate_limit')),
        AuthProblem.tooMany,
      );
      expect(
        of(const AuthApiException('x', code: 'email_address_invalid')),
        AuthProblem.badEmail,
      );
      expect(
        of(const AuthApiException('x', code: 'otp_expired'), codeStep: true),
        AuthProblem.badCode,
      );
      final other = SupabaseAuth.failureOf(
        const AuthApiException('Signups not allowed', code: 'signup_disabled'),
      );
      expect(other.problem, AuthProblem.other);
      expect(other.message, 'Signups not allowed');
    });
  });

  group('The rules of every remote, over the web calls', () {
    late LocalSupabase local;
    remoteContract(
      make: () async {
        local = await startServer();
        final client = await signedIn(local, me);
        return SupabaseRemote(
          api: SupabaseClientApi(client),
          schema: local.rows.schema,
        );
      },
      offline: (remote, off) => local.down = off,
    );
  });

  group('What the server refuses', () {
    test('nobody is signed in', () async {
      final local = await startServer();
      final remote = SupabaseRemote(
        api: SupabaseClientApi(clientFor(local)),
        schema: local.rows.schema,
      );
      await expectLater(
        remote.pull(after: 0, limit: 10),
        throwsA(isA<NotSignedIn>()),
      );
    });

    test('another schema number', () async {
      final local = await startServer();
      final client = await signedIn(local, me);
      local.rows.serverSchema += 1;
      final remote = SupabaseRemote(
        api: SupabaseClientApi(client),
        schema: local.rows.schema,
      );
      await expectLater(
        remote.push([change('a', 1)]),
        throwsA(isA<SchemaMismatch>()),
      );
    });

    test('a function that is not there', () async {
      final local = await startServer();
      final api = SupabaseClientApi(await signedIn(local, me));
      await expectLater(
        api.rpc('no_such_function', {'p_schema': local.rows.schema.version}),
        throwsA(
          isA<SupabaseApiError>().having((e) => e.code, 'code', 'PGRST202'),
        ),
      );
    });
  });

  group('Files', () {
    test('a file goes up and comes down the same', () async {
      final local = await startServer();
      final api = SupabaseClientApi(await signedIn(local, me));
      final user = api.userId!;
      expect(user, LocalSupabase.userIdOf(me));
      final bytes = Uint8List.fromList([0, 1, 2, 250, 255]);

      await api.upload(
        'grove-attachments',
        '$user/img-1',
        bytes,
        contentType: 'image/png',
      );
      expect(
        local.rows.files['grove-attachments/$user/img-1']!.contentType,
        'image/png',
      );
      expect(await api.download('grove-attachments', '$user/img-1'), bytes);

      // A second upload to the same path takes the place of the first.
      await api.upload(
        'grove-attachments',
        '$user/img-1',
        Uint8List.fromList([9]),
        contentType: 'image/png',
      );
      expect(await api.download('grove-attachments', '$user/img-1'), [9]);
    });

    test('a file that is not there gives nothing', () async {
      final local = await startServer();
      final api = SupabaseClientApi(await signedIn(local, me));
      expect(
        await api.download('grove-attachments', '${api.userId}/none'),
        isNull,
      );
    });

    test('the file of another person is out of reach', () async {
      final local = await startServer();
      final mine = SupabaseClientApi(await signedIn(local, me));
      final theirs = SupabaseClientApi(
        await signedIn(local, 'other@example.com'),
      );
      await mine.upload(
        'grove-attachments',
        '${mine.userId}/img',
        Uint8List.fromList([1]),
        contentType: 'image/png',
      );

      expect(
        await theirs.download('grove-attachments', '${mine.userId}/img'),
        isNull,
      );
      await expectLater(
        theirs.upload(
          'grove-attachments',
          '${mine.userId}/img',
          Uint8List.fromList([2]),
          contentType: 'image/png',
        ),
        throwsA(isA<SupabaseApiError>().having((e) => e.code, 'code', '403')),
      );
      expect(await mine.download('grove-attachments', '${mine.userId}/img'), [
        1,
      ]);
    });

    test('a server that does not answer is "no connection"', () async {
      final local = await startServer();
      final api = SupabaseClientApi(await signedIn(local, me));
      local.down = true;
      await expectLater(
        api.upload(
          'grove-attachments',
          '${api.userId}/img',
          Uint8List.fromList([1]),
          contentType: 'image/png',
        ),
        throwsA(isA<RemoteUnavailable>()),
      );
      await expectLater(
        api.download('grove-attachments', '${api.userId}/img'),
        throwsA(isA<RemoteUnavailable>()),
      );
    });
  });

  group('Two devices of one person', () {
    test('every kind of row and an image go from one to the other', () async {
      final local = await startServer();
      Future<Device> device() async {
        final client = await signedIn(local, me);
        late final Device d;
        d = Device(_Late(() => SupabaseBackend.remoteFor(client, d.repos)));
        return d;
      }

      final a = await device(), b = await device();
      fill(a);
      await settle([a, b]);
      expectSame([a, b]);
      expect(dump(b.db)['attachments'], hasLength(1));
      expect(local.rows.uploads, hasLength(1));
      // Device a has the image, so it does not download it.
      expect(local.rows.downloads, hasLength(1));

      b.later();
      final task = b.repos.tasks.all().first;
      b.repos.tasks.save(task.copyWith(title: 'Changed on b'));
      await settle([a, b]);
      expectSame([a, b]);
      expect(a.repos.tasks.get(task.id)!.title, 'Changed on b');
    });

    test('another person sees none of it', () async {
      final local = await startServer();
      final mine = SupabaseRemote(
        api: SupabaseClientApi(await signedIn(local, me)),
        schema: local.rows.schema,
      );
      final theirs = SupabaseRemote(
        api: SupabaseClientApi(await signedIn(local, 'other@example.com')),
        schema: local.rows.schema,
      );
      await mine.push([change('a', 1)]);
      expect(await theirs.pull(after: 0, limit: 10), isEmpty);
      expect(await mine.pull(after: 0, limit: 10), hasLength(1));
    });
  });

  group('The start', () {
    test('a build with no keys has no sync', () async {
      expect(
        await SupabaseBackend.start(const SyncConfig(url: '', anonKey: '')),
        isNull,
      );
      expect(
        await SupabaseBackend.start(
          const SyncConfig(url: 'https://x.supabase.co', anonKey: ' '),
        ),
        isNull,
      );
    });
  });
}

/// A remote that is made at its first call (the device must exist first).
class _Late implements SyncRemote {
  _Late(this._make);

  final SyncRemote Function() _make;
  late final SyncRemote _remote = _make();

  @override
  Future<void> push(List<RowChange> changes) => _remote.push(changes);

  @override
  Future<List<RowChange>> pull({required int after, required int limit}) =>
      _remote.pull(after: after, limit: limit);
}
