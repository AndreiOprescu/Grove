import '../data/database.dart';
import '../data/sync_schema.dart';

/// One waiting change: a row that the remote does not have yet in this state.
class OutboxEntry {
  const OutboxEntry({
    required this.seq,
    required this.table,
    required this.key,
    required this.stamp,
    required this.deleted,
  });

  /// Rises with each change on this device. A row that changes again gets a
  /// new number.
  final int seq;
  final String table;
  final String key;

  /// The time of the change on the clock of this device. See [Outbox.clock].
  final int stamp;

  /// True: the row was deleted.
  final bool deleted;
}

/// The list of local changes that wait for the next sync, the clock of this
/// device, and how far this device has pulled. The triggers of `SyncSchema`
/// write the list; this class reads it.
class Outbox {
  Outbox(this.db);

  final Database db;

  static const _columns = 'seq, tbl, pk, stamp, deleted';

  static OutboxEntry _entry(Row r) => OutboxEntry(
    seq: r.asInt(0),
    table: r.text(1),
    key: r.text(2),
    stamp: r.asInt(3),
    deleted: r.asBool(4),
  );

  int get count =>
      db.queryOne('SELECT count(*) FROM outbox', const [], (r) => r.asInt(0)) ??
      0;

  /// The waiting changes, oldest first.
  List<OutboxEntry> entries() =>
      db.query('SELECT $_columns FROM outbox ORDER BY seq', const [], _entry);

  OutboxEntry? entry(String table, String key) => db.queryOne(
    'SELECT $_columns FROM outbox WHERE tbl = ? AND pk = ?',
    [table, key],
    _entry,
  );

  /// Takes the change with this number off the list. A row that changed
  /// again after that has a new number and stays.
  void remove(int seq) => db.execute('DELETE FROM outbox WHERE seq = ?', [seq]);

  /// Takes the row off the list: the remote has it in this state.
  void forget(String table, String key) =>
      db.execute('DELETE FROM outbox WHERE tbl = ? AND pk = ?', [table, key]);

  /// Puts the row on the list as a new change, made now.
  void record(String table, String key, {required bool deleted}) {
    db.transaction(() {
      db.execute(SyncSchema.tick);
      forget(table, key);
      db.execute(
        'INSERT INTO outbox (tbl, pk, stamp, deleted) VALUES (?, ?, ?, ?)',
        [table, key, clock, deleted ? 1 : 0],
      );
    });
  }

  int _meta(String key) =>
      int.tryParse(
        db.queryOne('SELECT value FROM sync_meta WHERE key = ?', [
              key,
            ], (r) => r.text(0)) ??
            '',
      ) ??
      0;

  void _setMeta(String key, int value) => db.execute(
    'INSERT INTO sync_meta (key, value) VALUES (?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, '$value'],
  );

  /// The stamp of the last change this device made or saw, in milliseconds
  /// since 1970 (UTC). The next change gets a higher stamp, also when the
  /// clock of the computer is behind.
  int get clock => _meta('clock');

  /// This device saw a change with this stamp. The clock never goes back.
  void seeClock(int stamp) {
    if (stamp > clock) _setMeta('clock', stamp);
  }

  /// The number of the last remote change this device pulled.
  int get cursor => _meta('cursor');

  set cursor(int seq) => _setMeta('cursor', seq);
}
