import '../data/database.dart';
import '../data/migrations.dart';
import '../data/repos.dart';
import '../data/sync_schema.dart';
import 'outbox.dart';
import 'row_change.dart';
import 'sync_remote.dart';

/// What one sync did.
class SyncReport {
  const SyncReport({
    required this.pushed,
    required this.pulled,
    required this.skipped,
  });

  /// How many local changes went to the remote.
  final int pushed;

  /// How many remote changes came in. The changes this device sent before
  /// come back one time and count too.
  final int pulled;

  /// The rows this app could not use, as "table key: reason" lines.
  final List<String> skipped;
}

/// A column that holds the id of a row of [parent]. When two rows of
/// [parent] become one row, these columns must follow.
typedef _Pointer = ({
  String table,
  String column,
  String parent,

  /// For `links`: the column that says which kind of row the id is of.
  String? typeColumn,
});

/// Sends the local changes to the remote and brings the remote changes in.
///
/// The local database stays the source of truth: the app reads and writes it
/// and never waits for the remote. The rule for two changes of the same row
/// is: the last write wins, for the whole row.
class SyncEngine {
  SyncEngine({required this.repos, required this.remote, this.pageSize = 500})
    : outbox = Outbox(repos.db) {
    for (final name in SyncMigrations.syncedTables) {
      _tables[name] = SyncTable.read(db, name);
    }
    for (final parent in _uniqueTables) {
      _pointers.addAll([
        for (final t in _tables.values)
          for (final fk in t.foreignKeys.values)
            if (fk.parent == parent)
              (
                table: t.name,
                column: fk.column,
                parent: parent,
                typeColumn: null,
              ),
      ]);
    }
    // A link holds a kind and an id, not a foreign key.
    _pointers.addAll(const [
      (
        table: 'links',
        column: 'src_id',
        parent: 'notes',
        typeColumn: 'src_type',
      ),
      (
        table: 'links',
        column: 'dst_id',
        parent: 'notes',
        typeColumn: 'dst_type',
      ),
    ]);
  }

  final Repos repos;
  final SyncRemote remote;

  /// How many rows go in one call to the remote.
  final int pageSize;

  final Outbox outbox;

  Database get db => repos.db;

  final _tables = <String, SyncTable>{};
  final _pointers = <_Pointer>[];

  /// The tables with a rule "only one row with this value": one tag for a
  /// name, one daily or weekly note for a date. See [_Pull._twin].
  static const _uniqueTables = ['notes', 'tags'];

  Future<SyncReport>? _running;

  bool get isSyncing => _running != null;

  /// Pushes, then pulls. A call during a sync gives the sync that runs.
  /// When the remote fails, the error comes out, nothing is lost, and the
  /// next sync goes on from there.
  Future<SyncReport> sync() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<SyncReport> _run() async {
    final pushed = await _push();
    final changes = await _fetch();
    final pull = _Pull(this, changes);
    if (changes.isNotEmpty) pull.run();
    return SyncReport(
      pushed: pushed,
      pulled: changes.length,
      skipped: List.unmodifiable(pull.skipped),
    );
  }

  // ---- Push ---------------------------------------------------------------

  Future<int> _push() async {
    var pushed = 0;
    while (true) {
      final queue = _pushOrder(outbox.entries());
      if (queue.isEmpty) return pushed;
      for (var start = 0; start < queue.length; start += pageSize) {
        final sent = <OutboxEntry>[];
        final changes = <RowChange>[];
        for (final e in queue.skip(start).take(pageSize)) {
          // A row that changed while an earlier page was on its way has a
          // new entry. The next round sends it, in the correct order.
          if (outbox.entry(e.table, e.key)?.seq != e.seq) continue;
          sent.add(e);
          changes.add(_changeFor(e));
        }
        if (changes.isEmpty) continue;
        await remote.push(changes);
        for (final e in sent) {
          outbox.remove(e.seq);
        }
        pushed += sent.length;
      }
    }
  }

  /// The order in which the remote gets the changes. Saved rows go first,
  /// each after the rows it points at. Deleted rows go last, each before the
  /// rows it pointed at. So a device that pulls between two pages never has
  /// a row without its parent, and never loses a row because its parent is
  /// deleted too early.
  List<OutboxEntry> _pushOrder(List<OutboxEntry> entries) {
    final order = SyncMigrations.syncedTables;
    final saved = <(int, int, OutboxEntry)>[];
    final gone = <(int, OutboxEntry)>[];
    final depths = <String, int>{};
    for (final e in entries) {
      final table = _tables[e.table];
      if (table == null) {
        outbox.remove(e.seq);
      } else if (e.deleted) {
        gone.add((order.indexOf(e.table), e));
      } else {
        saved.add((order.indexOf(e.table), _depth(table, e.key, depths), e));
      }
    }
    saved.sort((a, b) {
      if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
      if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
      return a.$3.seq.compareTo(b.$3.seq);
    });
    gone.sort((a, b) {
      if (a.$1 != b.$1) return b.$1.compareTo(a.$1);
      return a.$2.seq.compareTo(b.$2.seq);
    });
    return [for (final s in saved) s.$3, for (final g in gone) g.$2];
  }

  /// How many rows of the same table are above this row (a subtask is below
  /// its task, an event of a series is below the first event).
  int _depth(SyncTable table, String key, Map<String, int> memo) {
    final self = [
      for (final fk in table.foreignKeys.values)
        if (fk.parent == table.name) fk.column,
    ];
    if (self.isEmpty || table.keyColumns.length != 1) return 0;
    final id = table.keyColumns.single;
    final path = <String>[];
    String? at = key;
    var base = 0;
    while (at != null && path.length < 64) {
      final known = memo['${table.name}\u0000$at'];
      if (known != null) {
        base = known + 1;
        break;
      }
      path.add(at);
      at = db.queryOne(
        'SELECT ${self.first} FROM ${table.name} WHERE $id = ?',
        [at],
        (r) => r.optText(0),
      );
    }
    for (final (i, k) in path.reversed.indexed) {
      memo['${table.name}\u0000$k'] = base + i;
    }
    return base + path.length - 1;
  }

  RowChange _changeFor(OutboxEntry e) {
    final data = e.deleted ? null : _read(_tables[e.table]!, e.key);
    return RowChange(
      table: e.table,
      key: e.key,
      stamp: e.stamp,
      deleted: data == null,
      data: data ?? <String, Object?>{},
    );
  }

  // ---- Rows ---------------------------------------------------------------

  static Map<String, Object?> _map(Row r) => {
    for (var i = 0; i < r.length; i++) r.name(i): r.value(i),
  };

  /// The `WHERE` text and values for the row with this key.
  (String, List<Object?>) _where(SyncTable table, String key) {
    final parts = SyncSchema.keyParts(key);
    if (parts.length != table.keyColumns.length) {
      throw FormatException('"$key" is not a key of ${table.name}');
    }
    final tests = <String>[];
    final args = <Object?>[];
    for (final (i, column) in table.keyColumns.indexed) {
      if (parts[i].isEmpty) {
        tests.add("ifnull($column, '') = ''");
      } else {
        tests.add('$column = ?');
        args.add(parts[i]);
      }
    }
    return (tests.join(' AND '), args);
  }

  /// The data columns of a row, or null when the row is not there.
  Map<String, Object?>? _read(SyncTable table, String key) {
    final (where, args) = _where(table, key);
    return db.queryOne(
      'SELECT ${table.columns.join(', ')} FROM ${table.name} WHERE $where',
      args,
      _map,
    );
  }

  bool _exists(SyncTable table, String key) {
    final (where, args) = _where(table, key);
    return db.queryOne(
          'SELECT 1 FROM ${table.name} WHERE $where',
          args,
          (r) => r.asInt(0),
        ) !=
        null;
  }

  void _deleteRow(SyncTable table, String key) {
    final (where, args) = _where(table, key);
    db.execute('DELETE FROM ${table.name} WHERE $where', args);
  }

  /// Saves a row: a new row, or new values for the row with the same key.
  void _write(SyncTable table, Map<String, Object?> data, {bool keep = false}) {
    final columns = data.keys.toList();
    final rest = [
      for (final c in columns)
        if (!table.keyColumns.contains(c)) c,
    ];
    final onConflict = keep || rest.isEmpty
        ? 'DO NOTHING'
        : 'DO UPDATE SET ${rest.map((c) => '$c = excluded.$c').join(', ')}';
    db.execute(
      'INSERT INTO ${table.name} (${columns.join(', ')}) '
      'VALUES (${columns.map((_) => '?').join(', ')}) '
      'ON CONFLICT(${table.keyColumns.join(', ')}) $onConflict',
      data.values.toList(),
    );
  }

  // ---- Pull ---------------------------------------------------------------

  /// Gets every change after the cursor. The device uses them only when all
  /// pages came in, so it never has half of what another device sent.
  Future<List<RowChange>> _fetch() async {
    final all = <RowChange>[];
    var after = outbox.cursor;
    while (true) {
      final page = await remote.pull(after: after, limit: pageSize);
      all.addAll(page);
      if (page.length < pageSize || page.last.seq <= after) return all;
      after = page.last.seq;
    }
  }
}

/// One pull: puts the remote changes in the local database.
class _Pull {
  _Pull(this.engine, this.changes);

  final SyncEngine engine;
  final List<RowChange> changes;
  final skipped = <String>[];

  Database get db => engine.db;
  Outbox get outbox => engine.outbox;

  /// The remote changes that win over the local state of their row.
  final _winners = <RowChange>{};

  /// The rows that a winning remote change deletes in this pull.
  final _doomed = <String>{};

  /// Rows that became one with another row in this pull: lost id to kept id,
  /// by table.
  final _alias = <String, Map<String, String>>{
    for (final t in SyncEngine._uniqueTables) t: {},
  };

  static String _id(String table, String key) => '$table\u0000$key';

  void run() {
    db.transaction(() {
      // A row can come before the row it points at. The check is at the end.
      db.execute('PRAGMA defer_foreign_keys = ON');

      // A change made here after this pull is newer than all of them.
      var newest = 0;
      for (final c in changes) {
        if (c.stamp > newest) newest = c.stamp;
      }

      // Decide first, for every change. The work below writes outbox lines
      // of its own, and they must not change who wins.
      final known = [
        for (final c in changes)
          if (engine._tables.containsKey(c.table)) c,
      ];
      for (final c in known) {
        if (_remoteWins(c)) {
          _winners.add(c);
          if (c.deleted) _doomed.add(_id(c.table, c.key));
        }
      }
      outbox.seeClock(newest);

      // Saved rows first, a table after the tables it points at.
      for (final table in engine._tables.values) {
        var saved = [
          for (final c in known)
            if (c.table == table.name && !c.deleted && _winners.contains(c)) c,
        ];
        if (SyncEngine._uniqueTables.contains(table.name)) {
          // Rows this device has go first. A row that must become one with
          // a local row then meets the newest state of that local row.
          final here = <RowChange>[];
          final fresh = <RowChange>[];
          for (final c in saved) {
            (_existsSafe(table, c.key) ? here : fresh).add(c);
          }
          saved = [...here, ...fresh];
        }
        for (final c in saved) {
          _guard(c, () => _save(table, c));
        }
      }

      // Then the deleted rows, a table before the tables it points at. So a
      // delete takes with it only what the remote does not have any more.
      for (final table in engine._tables.values.toList().reversed) {
        for (final c in known) {
          if (c.table == table.name && c.deleted && _winners.contains(c)) {
            _guard(c, () {
              engine._deleteRow(table, c.key);
              outbox.forget(table.name, c.key);
            });
          }
        }
      }

      _repairForeignKeys();

      var last = outbox.cursor;
      for (final c in changes) {
        if (c.seq > last) last = c.seq;
      }
      outbox.cursor = last;
    });
    repos.rebuildSearch();
  }

  Repos get repos => engine.repos;

  bool _existsSafe(SyncTable table, String key) {
    try {
      return engine._exists(table, key);
    } on FormatException {
      return false;
    }
  }

  /// One row at a time. A row this app cannot save must not stop the others.
  void _guard(RowChange c, void Function() body) {
    try {
      db.transaction(body);
    } on Exception catch (e) {
      skipped.add('${c.table} ${c.key}: $e');
    }
  }

  /// Last write wins. A row with no waiting local change takes the remote
  /// state. When both stamps are the same, the remote state wins: the remote
  /// refused the local change of that age, so all devices end the same.
  bool _remoteWins(RowChange c) {
    final local = outbox.entry(c.table, c.key);
    if (local == null) return true;
    if (local.deleted && c.deleted) return true;
    return local.stamp <= c.stamp;
  }

  void _save(SyncTable table, RowChange c) {
    // Only the columns this app knows.
    final data = <String, Object?>{
      for (final column in table.columns)
        if (c.data.containsKey(column)) column: c.data[column],
    };
    if (table.keyOf(data) != c.key) {
      throw const FormatException('the key is not the key of the row');
    }

    // The row points at a row that became one with another row.
    var moved = false;
    for (final p in engine._pointers) {
      if (p.table != table.name) continue;
      if (p.typeColumn != null && data[p.typeColumn] != 'note') continue;
      final kept = _alias[p.parent]![data[p.column]];
      if (kept != null) {
        data[p.column] = kept;
        moved = true;
      }
    }
    if (moved) return _saveMoved(table, c, data);

    final twin = _twin(table, data);
    if (twin != null) return _merge(table, c, data, twin);

    engine._write(table, data);
    // The remote has the row in this state. Do not send it back.
    outbox.forget(table.name, c.key);
  }

  /// Saves a row that now points at the kept row. The remote does not have
  /// the row in this state, so it is a local change and goes out.
  void _saveMoved(SyncTable table, RowChange c, Map<String, Object?> data) {
    final key = table.keyOf(data)!;
    if (key != c.key) {
      // The id is a part of the key: the remote row with the old key goes.
      engine._deleteRow(table, c.key);
      outbox.record(table.name, c.key, deleted: true);
      final local = outbox.entry(table.name, key);
      if (local != null && local.deleted && local.stamp > c.stamp) return;
    }
    engine._write(table, data);
    outbox.record(table.name, key, deleted: false);
  }

  /// The id of the local row that cannot be there together with this row:
  /// a tag with the same name, or the daily or weekly note of the same date.
  String? _twin(SyncTable table, Map<String, Object?> data) {
    final id = data['id'];
    switch (table.name) {
      case 'tags':
        final name = data['name'];
        if (name is! String) return null;
        return db.queryOne('SELECT id FROM tags WHERE name = ? AND id <> ?', [
          name,
          id,
        ], (r) => r.text(0));
      case 'notes':
        final kind = data['kind'], date = data['date'];
        if (date is! String || (kind != 'daily' && kind != 'weekly')) {
          return null;
        }
        return db.queryOne(
          'SELECT id FROM notes WHERE kind = ? AND date = ? AND id <> ?',
          [kind, date, id],
          (r) => r.text(0),
        );
    }
    return null;
  }

  /// Makes one row from the remote row and its local twin. Every device
  /// keeps the same one: the row with the smaller id. When the remote
  /// deleted the twin in this same pull, the remote row is kept.
  void _merge(
    SyncTable table,
    RowChange c,
    Map<String, Object?> data,
    String twin,
  ) {
    final id = c.key;
    final keepRemote =
        id.compareTo(twin) < 0 || _doomed.contains(_id(table.name, twin));
    final isNote = table.name == 'notes';
    if (keepRemote) {
      final lostBody = isNote ? _body(twin) : null;
      _absorb(table, lost: twin, kept: id);
      engine._write(table, data);
      outbox.forget(table.name, id);
      if (lostBody != null) _joinBody(id, lostBody);
      _alias[table.name]![twin] = id;
    } else {
      _absorb(table, lost: id, kept: twin);
      final lostBody = data['body'];
      if (isNote && lostBody is String) _joinBody(twin, lostBody);
      _alias[table.name]![id] = twin;
    }
  }

  /// Moves what points at the lost row to the kept row, then deletes the
  /// lost row here and on the remote. These are local changes and go out.
  void _absorb(SyncTable table, {required String lost, required String kept}) {
    for (final p in engine._pointers) {
      if (p.parent != table.name) continue;
      final from = engine._tables[p.table]!;
      final typed = p.typeColumn == null ? '' : " AND ${p.typeColumn} = 'note'";
      final where = '${p.column} = ?$typed';
      if (!from.keyColumns.contains(p.column)) {
        db.execute('UPDATE ${from.name} SET ${p.column} = ? WHERE $where', [
          kept,
          lost,
        ]);
        continue;
      }
      // The id is a part of the key: make the row again with the kept id.
      final rows = db.query(
        'SELECT ${from.columns.join(', ')} FROM ${from.name} WHERE $where',
        [lost],
        SyncEngine._map,
      );
      for (final row in rows) {
        final oldKey = from.keyOf(row);
        // The remote deleted this row in this pull. It stays deleted.
        if (oldKey != null && _doomed.contains(_id(from.name, oldKey))) {
          continue;
        }
        row[p.column] = kept;
        engine._write(from, row, keep: true);
      }
      db.execute('DELETE FROM ${from.name} WHERE $where', [lost]);
    }
    if (engine._exists(table, lost)) {
      engine._deleteRow(table, lost);
    } else {
      outbox.record(table.name, lost, deleted: true);
    }
  }

  String? _body(String noteId) => db.queryOne(
    'SELECT body FROM notes WHERE id = ?',
    [noteId],
    (r) => r.optText(0) ?? '',
  );

  /// Puts the text of the lost note below the text of the kept note.
  void _joinBody(String keptId, String lostBody) {
    final kept = _body(keptId);
    if (kept == null) return;
    final joined = joinBodies(kept, lostBody);
    if (joined != kept) {
      db.execute('UPDATE notes SET body = ? WHERE id = ?', [joined, keptId]);
    }
  }

  /// The kept text, then the lost text. No text is there two times.
  static String joinBodies(String kept, String lost) {
    final extra = lost.trim();
    if (extra.isEmpty || kept.contains(extra)) return kept;
    if (kept.trim().isEmpty) return lost;
    return '${kept.trimRight()}\n\n${lost.trimLeft()}';
  }

  /// After a pull a row can point at a row that is not there: one device
  /// deleted the parent while another device changed the child. The schema
  /// says what happens then: the pointer becomes empty, or the child goes
  /// too. The triggers put these repairs in the outbox, so the remote and
  /// the other devices get them.
  void _repairForeignKeys() {
    for (var round = 0; round < 100; round++) {
      final bad = db.query(
        'PRAGMA foreign_key_check',
        const [],
        (r) => (table: r.text(0), rowid: r.optInt(1), fk: r.asInt(3)),
      );
      if (bad.isEmpty) return;
      for (final b in bad) {
        final fk = engine._tables[b.table]?.foreignKeys[b.fk];
        if (fk == null || b.rowid == null) {
          throw StateError('Cannot repair a row of ${b.table}.');
        }
        db.execute(
          fk.setsNull
              ? 'UPDATE ${b.table} SET ${fk.column} = NULL WHERE rowid = ?'
              : 'DELETE FROM ${b.table} WHERE rowid = ?',
          [b.rowid],
        );
      }
    }
    throw StateError('The rows still point at missing rows.');
  }
}
