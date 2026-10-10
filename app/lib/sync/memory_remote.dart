import 'dart:typed_data';

import 'row_change.dart';
import 'sync_remote.dart';

/// A remote that lives in memory. The tests use it, and it shows the rules a
/// real remote must follow.
class MemoryRemote implements SyncRemote {
  final _rows = <String, RowChange>{};

  /// The number of the last change that was kept.
  int lastSeq = 0;

  int pushCalls = 0;
  int pullCalls = 0;

  /// True: [push] and [pull] throw [RemoteUnavailable].
  bool offline = false;

  /// Set to N: the remote keeps N more rows, then a push throws. One time.
  int? failPushAfter;

  /// Set to N: N more pulls work, then a pull throws. One time.
  int? failPullAfter;

  /// Every row the remote holds, in the order of their numbers.
  List<RowChange> get rows =>
      _rows.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));

  @override
  Future<void> push(List<RowChange> changes) async {
    pushCalls++;
    if (offline) throw const RemoteUnavailable();
    for (final c in changes) {
      final left = failPushAfter;
      if (left != null) {
        if (left <= 0) {
          failPushAfter = null;
          throw const RemoteUnavailable('The push stopped half way.');
        }
        failPushAfter = left - 1;
      }
      final id = '${c.table}\u0000${c.key}';
      final stored = _rows[id];
      if (stored != null && c.stamp <= stored.stamp) continue;
      _rows[id] = _copy(c, seq: ++lastSeq);
    }
  }

  @override
  Future<List<RowChange>> pull({required int after, required int limit}) async {
    pullCalls++;
    if (offline) throw const RemoteUnavailable();
    final left = failPullAfter;
    if (left != null) {
      if (left <= 0) {
        failPullAfter = null;
        throw const RemoteUnavailable('The pull stopped half way.');
      }
      failPullAfter = left - 1;
    }
    return [
      for (final c in rows.where((c) => c.seq > after).take(limit))
        _copy(c, seq: c.seq),
    ];
  }

  static RowChange _copy(RowChange c, {required int seq}) => RowChange(
    table: c.table,
    key: c.key,
    stamp: c.stamp,
    deleted: c.deleted,
    data: {
      for (final e in c.data.entries)
        e.key: switch (e.value) {
          final Uint8List bytes => Uint8List.fromList(bytes),
          final Object? other => other,
        },
    },
    seq: seq,
  );
}
