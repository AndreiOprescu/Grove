import 'dart:convert';
import 'dart:typed_data';

import 'package:grove/sync/sync.dart';

class _Stored {
  _Stored(this.stamp, this.deleted, this.seq, this.data);

  int stamp;
  bool deleted;
  int seq;
  Map<String, Object?> data;
}

/// A Supabase project in memory. It keeps the rules of the SQL in
/// `supabase/migrations/`: typed columns, one row for a key, the last write
/// wins, each person has own rows and own files. Every call goes through
/// JSON text, as on the network.
class FakeSupabase implements SupabaseApi {
  FakeSupabase(this.schema, {this.userId = 'user-1'})
    : serverSchema = schema.version;

  final RemoteSchema schema;

  @override
  String? userId;

  /// The schema number the SQL on the server was made for.
  int serverSchema;

  bool offline = false;

  /// The functions that were called, oldest first.
  final calls = <String>[];

  /// The JSON text of the last call of `sync_push`.
  String lastPush = '';

  final uploads = <String>[];
  final downloads = <String>[];

  /// The files, by "bucket/path". The value holds the content type too.
  final files = <String, ({Uint8List bytes, String contentType})>{};

  final _rows = <String, Map<String, _Stored>>{};
  final _lastSeq = <String, int>{};

  void _online() {
    if (offline) throw const RemoteUnavailable();
  }

  @override
  Future<Object?> rpc(String function, Map<String, Object?> args) async {
    _online();
    calls.add(function);
    final text = jsonEncode(args);
    final sent = jsonDecode(text) as Map<String, Object?>;
    final user = userId;
    if (user == null) {
      throw const SupabaseApiError(
        'Not signed in.',
        code: SupabaseNames.notSignedIn,
      );
    }
    if (sent['p_schema'] != serverSchema) {
      throw SupabaseApiError(
        'Grove schema: the server has $serverSchema, the app has '
        '${sent['p_schema']}.',
        code: SupabaseNames.schemaMismatch,
      );
    }
    final answer = switch (function) {
      SupabaseNames.push => _push(user, sent['p_changes'] as List, text),
      SupabaseNames.pull => _pull(
        user,
        sent['p_after'] as int,
        sent['p_limit'] as int,
      ),
      _ => throw SupabaseApiError('No function $function.', code: 'PGRST202'),
    };
    return jsonDecode(jsonEncode(answer));
  }

  int _push(String user, List<Object?> changes, String text) {
    lastPush = text;
    final rows = _rows.putIfAbsent(user, () => {});
    final base = _lastSeq[user] ?? 0;
    final seen = <String>{};
    // All or nothing, as one SQL call.
    final next = {for (final e in rows.entries) e.key: e.value};
    for (final (i, item) in changes.indexed) {
      final c = (item as Map).cast<String, Object?>();
      final table = schema.table(c['table'] as String);
      if (table == null) continue;
      final key = c['key'] as String;
      final id = '${table.name}\u0000$key';
      if (!seen.add(id)) {
        throw const SupabaseApiError(
          'ON CONFLICT DO UPDATE command cannot affect row a second time',
          code: '21000',
        );
      }
      final parts = key.split(String.fromCharCode(31));
      final sent = (c['data'] as Map?)?.cast<String, Object?>() ?? const {};
      final data = <String, Object?>{};
      for (final column in table.stored) {
        final at = table.keyColumns.indexOf(column.name);
        final v = at >= 0
            ? (at < parts.length ? parts[at] : '')
            : sent[column.name];
        data[column.name] = _typed(table.name, column, v);
      }
      final stamp = c['stamp'] as int;
      final old = next[id];
      if (old != null && old.stamp >= stamp) continue;
      next[id] = _Stored(stamp, c['deleted'] == true, base + i + 1, data);
    }
    _rows[user] = next;
    _lastSeq[user] = base + changes.length;
    return base + changes.length;
  }

  /// What Postgres does with a JSON value for a column of this type.
  Object? _typed(String table, RemoteColumn column, Object? v) {
    if (v == null) return null;
    switch (column.type) {
      case RemoteType.text:
        if (v is String && v.contains('\u0000')) {
          throw const SupabaseApiError(
            'unsupported Unicode escape sequence',
            code: '22P05',
          );
        }
        return v is String ? v : jsonEncode(v);
      case RemoteType.integer:
        if (v is int) return v;
      case RemoteType.real:
        if (v is num) return v.toDouble();
      case RemoteType.bytes:
        break;
    }
    throw SupabaseApiError(
      'invalid input syntax for $table.${column.name}: $v',
      code: '22P02',
    );
  }

  List<Object?> _pull(String user, int after, int limit) {
    final rows = [
      for (final e in (_rows[user] ?? const <String, _Stored>{}).entries)
        if (e.value.seq > after) e,
    ]..sort((a, b) => a.value.seq.compareTo(b.value.seq));
    return [
      for (final e in rows.take(limit))
        {
          'table': e.key.split('\u0000').first,
          'key': e.key.split('\u0000').last,
          'stamp': e.value.stamp,
          'deleted': e.value.deleted,
          'seq': e.value.seq,
          'data': e.value.deleted
              ? const <String, Object?>{}
              : {
                  for (final d in e.value.data.entries)
                    // Postgres writes 2.0 as 2 in JSON.
                    d.key: switch (d.value) {
                      final double x when x == x.roundToDouble() => x.toInt(),
                      final Object? x => x,
                    },
                },
        },
    ];
  }

  /// The rows the server holds for a person, as "table key state" lines.
  List<String> rowsOf(String user) => [
    for (final e in (_rows[user] ?? const <String, _Stored>{}).entries)
      '${e.key.replaceAll('\u0000', ' ')} '
          '${e.value.deleted ? 'gone' : 'saved'}',
  ];

  bool _mine(String path) => userId != null && path.startsWith('$userId/');

  @override
  Future<void> upload(
    String bucket,
    String path,
    Uint8List bytes, {
    required String contentType,
  }) async {
    _online();
    if (!_mine(path)) {
      throw const SupabaseApiError(
        'new row violates row-level security policy',
        code: '403',
      );
    }
    uploads.add(path);
    files['$bucket/$path'] = (
      bytes: Uint8List.fromList(bytes),
      contentType: contentType,
    );
  }

  @override
  Future<Uint8List?> download(String bucket, String path) async {
    _online();
    downloads.add(path);
    if (!_mine(path)) return null;
    final file = files['$bucket/$path'];
    return file == null ? null : Uint8List.fromList(file.bytes);
  }
}
