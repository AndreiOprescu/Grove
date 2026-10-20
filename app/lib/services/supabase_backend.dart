import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repos.dart';
import '../sync/sync.dart';

/// The sync with a real Supabase project (cross-platform plan F11). This is
/// the only file that uses the Supabase package. The rules of the sync are
/// in `lib/sync/` and are tested there with fakes.
abstract final class SupabaseBackend {
  /// Starts the Supabase package with the keys of the build. Gives null when
  /// the build has no keys, or when the start did not work: Grove then runs
  /// with no sync.
  ///
  /// The package keeps the session on this device, so the person stays
  /// signed in when the app starts again.
  static Future<SyncBackend?> start(SyncConfig config) async {
    if (!config.isSet) return null;
    try {
      final supabase = await Supabase.initialize(
        url: _trimUrl(config.url),
        publishableKey: config.anonKey.trim(),
        debug: false,
      );
      return of(supabase.client);
    } on Exception {
      return null;
    }
  }

  /// The login and the remote on top of [client].
  static SyncBackend of(SupabaseClient client) => SyncBackend(
    auth: SupabaseAuth(client.auth),
    remote: (repos) => remoteFor(client, repos),
  );

  static SupabaseRemote remoteFor(SupabaseClient client, Repos repos) =>
      SupabaseRemote(
        api: SupabaseClientApi(client),
        schema: RemoteSchema.read(repos.db),
        // An image is never changed after it is saved, so the bytes this
        // device has are the bytes of the file.
        localImage: (id) => repos.attachments.get(id)?.data,
      );

  static String _trimUrl(String url) {
    var text = url.trim();
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }
}

/// The calls of the sync, sent with the Supabase package.
class SupabaseClientApi implements SupabaseApi {
  SupabaseClientApi(this.client);

  final SupabaseClient client;

  /// The codes PostgREST gives when the token of the session is not good.
  static const _tokenCodes = {'PGRST301', 'PGRST302', 'PGRST303'};

  @override
  String? get userId => client.auth.currentUser?.id;

  @override
  Future<Object?> rpc(String function, Map<String, Object?> args) async {
    try {
      return await client.rpc<Object?>(function, params: args);
    } on PostgrestException catch (e) {
      throw SupabaseApiError(
        e.message,
        code: _tokenCodes.contains(e.code) ? SupabaseNames.notSignedIn : e.code,
      );
    } on Exception {
      // No answer from the server at all.
      throw const RemoteUnavailable();
    }
  }

  @override
  Future<void> upload(
    String bucket,
    String path,
    Uint8List bytes, {
    required String contentType,
  }) async {
    try {
      await client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
    } on StorageException catch (e) {
      throw _storageError(e);
    } on Exception {
      throw const RemoteUnavailable();
    }
  }

  @override
  Future<Uint8List?> download(String bucket, String path) async {
    try {
      return await client.storage.from(bucket).download(path);
    } on StorageException catch (e) {
      if (_isMissing(e)) return null;
      throw _storageError(e);
    } on Exception {
      throw const RemoteUnavailable();
    }
  }

  /// The file store answers with a number. With no number, there was no
  /// answer.
  static Exception _storageError(StorageException e) =>
      int.tryParse(e.statusCode ?? '') == null
      ? const RemoteUnavailable()
      : SupabaseApiError(e.message, code: e.statusCode);

  static bool _isMissing(StorageException e) {
    if (e.statusCode == '404') return true;
    final text = '${e.error} ${e.message}'.toLowerCase();
    return e.statusCode == '400' &&
        (text.contains('not_found') || text.contains('not found'));
  }
}

/// The login with an email, with the Supabase package. One email holds a
/// link and a code (when the email template of the project shows the code,
/// see `docs/acceptance/F11-login.md`).
class SupabaseAuth implements AuthGateway {
  SupabaseAuth(this.auth);

  final GoTrueClient auth;

  static Account? _account(User? user) =>
      user == null ? null : Account(userId: user.id, email: user.email ?? '');

  @override
  Account? get account => _account(auth.currentUser);

  /// The package tells more than a change of the person (a new token, for
  /// example). Only a change of the person goes on.
  @override
  Stream<Account?> get changes => auth.onAuthStateChange
      .map((state) => _account(state.session?.user))
      .distinct();

  @override
  Future<void> sendLink(String email) =>
      _guard(() => auth.signInWithOtp(email: email));

  @override
  Future<void> verifyCode({required String email, required String code}) =>
      _guard(
        () => auth.verifyOTP(email: email, token: code, type: OtpType.email),
        codeStep: true,
      );

  /// Signs out on this device only. Other devices stay signed in.
  @override
  Future<void> signOut() =>
      _guard(() => auth.signOut(scope: SignOutScope.local));

  static Future<void> _guard(
    Future<Object?> Function() call, {
    bool codeStep = false,
  }) async {
    try {
      await call();
    } on AuthException catch (e) {
      throw failureOf(e, codeStep: codeStep);
    } on Exception catch (e) {
      throw AuthFailure(AuthProblem.offline, '$e');
    }
  }

  /// What the package said, as a problem the login form knows.
  static AuthFailure failureOf(AuthException e, {bool codeStep = false}) {
    final code = e.code ?? '';
    if (e is AuthRetryableFetchException) {
      return AuthFailure(AuthProblem.offline, e.message);
    }
    if (e.statusCode == '429' || code.contains('rate_limit')) {
      return AuthFailure(AuthProblem.tooMany, e.message);
    }
    if (code == 'email_address_invalid' ||
        (code == 'validation_failed' && !codeStep)) {
      return AuthFailure(AuthProblem.badEmail, e.message);
    }
    if (codeStep &&
        (code == 'otp_expired' ||
            code == 'invalid_credentials' ||
            code == 'validation_failed' ||
            e.statusCode == '401' ||
            e.statusCode == '403')) {
      return AuthFailure(AuthProblem.badCode, e.message);
    }
    return AuthFailure(AuthProblem.other, e.message);
  }
}
