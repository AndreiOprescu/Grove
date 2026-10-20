import 'dart:typed_data';

import 'remote_schema.dart';
import 'row_change.dart';
import 'supabase_api.dart';
import 'supabase_sql.dart';
import 'sync_remote.dart';

/// The app and the server do not have the same schema number. A sync would
/// lose the columns that one side does not know, so there is no sync until
/// both are the same.
class SchemaMismatch implements Exception {
  const SchemaMismatch(this.message);

  final String message;

  @override
  String toString() => 'SchemaMismatch: $message';
}

/// The sync needs a person who is signed in, and nobody is.
class NotSignedIn implements Exception {
  const NotSignedIn();

  @override
  String toString() => 'NotSignedIn';
}

/// The remote that is a Supabase project (`supabase/migrations/`).
///
/// The rows go through the two database functions `sync_push` and
/// `sync_pull`. The bytes of an image do not go in a table: they go to the
/// file store, at `<user id>/<attachment id>`, before the row is pushed.
class SupabaseRemote implements SyncRemote {
  SupabaseRemote({required this.api, required this.schema, this.localImage});

  final SupabaseApi api;
  final RemoteSchema schema;

  /// The bytes of an image this device already has, by attachment id. With
  /// it, a pull does not download an image that is already here.
  final Uint8List? Function(String id)? localImage;

  /// The table and the column whose bytes go to the file store.
  static const imageTable = 'attachments';
  static const imageColumn = 'data';
  static const _mimeColumn = 'mime';

  String _path(String user, String id) => '$user/$id';

  @override
  Future<void> push(List<RowChange> changes) async {
    // One call can change a row one time only.
    var batch = <RowChange>[];
    final seen = <String>{};
    for (final c in changes) {
      if (!seen.add('${c.table}\u0000${c.key}')) {
        await _send(batch);
        batch = [];
        seen
          ..clear()
          ..add('${c.table}\u0000${c.key}');
      }
      batch.add(c);
    }
    await _send(batch);
  }

  Future<void> _send(List<RowChange> changes) async {
    if (changes.isEmpty) return;
    final items = <Map<String, Object?>>[];
    for (final c in changes) {
      final table = schema.table(c.table);
      if (table == null) {
        throw ArgumentError('"${c.table}" is not a synced table.');
      }
      if (c.table == imageTable && !c.deleted) await _upload(c);
      items.add({
        'table': c.table,
        'key': c.key,
        'stamp': c.stamp,
        'deleted': c.deleted,
        'data': c.deleted
            ? const <String, Object?>{}
            : {
                for (final column in table.stored)
                  if (c.data.containsKey(column.name))
                    column.name: _out(column.type, c.data[column.name]),
              },
      });
    }
    await _call(SupabaseNames.push, {
      'p_changes': items,
      'p_schema': schema.version,
    });
  }

  Future<void> _upload(RowChange c) async {
    final bytes = c.data[imageColumn];
    if (bytes is! List<int>) return;
    final user = api.userId;
    if (user == null) throw const NotSignedIn();
    final mime = c.data[_mimeColumn];
    await api.upload(
      SupabaseNames.bucket,
      _path(user, c.key),
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      contentType: mime is String && mime.isNotEmpty
          ? mime
          : 'application/octet-stream',
    );
  }

  @override
  Future<List<RowChange>> pull({required int after, required int limit}) async {
    final answer = await _call(SupabaseNames.pull, {
      'p_after': after,
      'p_limit': limit,
      'p_schema': schema.version,
    });
    if (answer is! List<Object?>) {
      throw const SupabaseApiError('sync_pull did not give a list.');
    }
    try {
      return await _read(answer);
    } on TypeError {
      throw const SupabaseApiError('sync_pull gave rows Grove cannot read.');
    }
  }

  Future<List<RowChange>> _read(List<Object?> answer) async {
    final out = <RowChange>[];
    for (final item in answer) {
      final map = (item as Map).cast<String, Object?>();
      final name = map['table'] as String;
      final key = map['key'] as String;
      final deleted = map['deleted'] == true;
      final table = schema.table(name);
      final raw = (map['data'] as Map?)?.cast<String, Object?>() ?? const {};
      final data = <String, Object?>{
        for (final e in raw.entries)
          e.key: _in(table?.column(e.key)?.type, e.value),
      };
      if (name == imageTable && !deleted) {
        final bytes = await _image(key);
        if (bytes != null) data[imageColumn] = bytes;
      }
      out.add(
        RowChange(
          table: name,
          key: key,
          stamp: (map['stamp'] as num).toInt(),
          deleted: deleted,
          data: data,
          seq: (map['seq'] as num).toInt(),
        ),
      );
    }
    return out;
  }

  /// The bytes of an image: the ones this device has, or the file of the
  /// remote. Null when the file is not there (the app then leaves the row
  /// out and says so in the report of the sync).
  Future<Uint8List?> _image(String id) async {
    final here = localImage?.call(id);
    if (here != null) return Uint8List.fromList(here);
    final user = api.userId;
    if (user == null) throw const NotSignedIn();
    return api.download(SupabaseNames.bucket, _path(user, id));
  }

  Future<Object?> _call(String function, Map<String, Object?> args) async {
    try {
      return await api.rpc(function, args);
    } on SupabaseApiError catch (e) {
      if (e.code == SupabaseNames.schemaMismatch) {
        throw SchemaMismatch(e.message);
      }
      if (e.code == SupabaseNames.notSignedIn) throw const NotSignedIn();
      rethrow;
    }
  }

  /// A value on its way out, in a form that JSON and Postgres can hold.
  static Object? _out(RemoteType type, Object? v) => switch ((type, v)) {
    (_, null) => null,
    // Postgres has no place for the character with code 0 in a text.
    (RemoteType.text, final String s) => s.replaceAll('\u0000', ''),
    (RemoteType.text, _) => '$v',
    (RemoteType.integer, final double d) when d == d.roundToDouble() =>
      d.toInt(),
    (RemoteType.real, final num n) => n.isFinite ? n.toDouble() : null,
    _ => v,
  };

  /// A value on its way in, with the type the column of the app has.
  static Object? _in(RemoteType? type, Object? v) => switch ((type, v)) {
    (_, null) => null,
    (RemoteType.integer, final num n) => n.toInt(),
    (RemoteType.real, final num n) => n.toDouble(),
    (RemoteType.text, final String s) => s,
    (RemoteType.text, _) => '$v',
    _ => v,
  };
}
