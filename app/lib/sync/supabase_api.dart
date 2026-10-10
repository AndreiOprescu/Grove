import 'dart:typed_data';

/// The server answered, and the answer is "no".
class SupabaseApiError implements Exception {
  const SupabaseApiError(this.message, {this.code});

  final String message;

  /// The code the server gave (an SQL state, or a status of the file store).
  final String? code;

  @override
  String toString() => 'SupabaseApiError(${code ?? '-'}): $message';
}

/// The few calls the sync makes to Supabase. The real one is in
/// `lib/services/supabase_backend.dart`; the tests use a fake.
///
/// A call that cannot reach the server throws `RemoteUnavailable`. A call
/// that the server refuses throws [SupabaseApiError].
abstract interface class SupabaseApi {
  /// The id of the person who is signed in, or null.
  String? get userId;

  /// Calls a database function. Gives the decoded JSON it returns.
  Future<Object?> rpc(String function, Map<String, Object?> args);

  /// Saves a file. A file that is already at [path] is replaced.
  Future<void> upload(
    String bucket,
    String path,
    Uint8List bytes, {
    required String contentType,
  });

  /// The bytes of a file, or null when there is no file at [path].
  Future<Uint8List?> download(String bucket, String path);
}
