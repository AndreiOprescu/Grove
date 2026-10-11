import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The folder `supabase/migrations/` of the repo.
Directory migrationsFolder() {
  var dir = Directory.current;
  while (!Directory('${dir.path}/supabase/migrations').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) fail('No supabase/migrations folder.');
    dir = parent;
  }
  return Directory('${dir.path}/supabase/migrations');
}

/// The newest SQL file. The name starts with the time, so the last name is
/// the newest.
File newestMigration() {
  final files = [
    for (final f in migrationsFolder().listSync().whereType<File>())
      if (f.path.endsWith('.sql')) f,
  ]..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) fail('No SQL file in supabase/migrations.');
  return files.last;
}

void main() {
  late RemoteSchema schema;
  late String sql;

  setUp(() {
    final db = Repos(Database.inMemory()).db;
    addTearDown(db.close);
    schema = RemoteSchema.read(db);
    sql = supabaseSql(schema);
  });

  test('the newest file in supabase/migrations is the SQL of this schema', () {
    // To make the file: GROVE_WRITE_SQL=<file name> flutter test <this file>
    final write = Platform.environment['GROVE_WRITE_SQL'];
    if (write != null && write.isNotEmpty) {
      File('${migrationsFolder().path}/$write').writeAsStringSync(sql);
    }
    final file = newestMigration();
    expect(
      file.readAsStringSync().replaceAll('\r\n', '\n'),
      sql,
      reason:
          'The schema of the app changed. Make a new file in '
          'supabase/migrations (see the first lines of ${file.path}).',
    );
  });

  test('the schema number is the count of the shared migrations', () {
    expect(schema.version, Migrations.all.length);
    expect(sql, contains('p_schema is distinct from ${schema.version} then'));
  });

  test('every synced table has a table, in the same order', () {
    expect([
      for (final t in schema.tables) t.name,
    ], SyncMigrations.syncedTables);
    for (final name in SyncMigrations.syncedTables) {
      expect(sql, contains('create table if not exists public."$name" ('));
    }
  });

  test('every data column of the app is a column of the remote', () {
    final db = Repos(Database.inMemory()).db;
    addTearDown(db.close);
    for (final name in SyncMigrations.syncedTables) {
      final local = SyncTable.read(db, name);
      final table = schema.table(name)!;
      expect([for (final c in table.columns) c.name], local.columns);
      for (final c in table.columns) {
        final isKey = local.keyColumns.contains(c.name);
        final line = isKey
            ? '  "${c.name}" text not null,'
            : 'alter table public."$name" add column if not exists "${c.name}" ';
        if (c.type == RemoteType.bytes) {
          expect(sql, isNot(contains(line)), reason: '$name.${c.name}');
        } else {
          expect(sql, contains(line), reason: '$name.${c.name}');
        }
      }
    }
  });

  test('the remote has no column the app does not have', () {
    final added = RegExp(r'add column if not exists "(\w+)"');
    final known = {
      for (final t in schema.tables)
        for (final c in t.columns) c.name,
    };
    for (final m in added.allMatches(sql)) {
      expect(known, contains(m.group(1)));
    }
  });

  test('the only bytes are the bytes of an image', () {
    final bytes = [
      for (final t in schema.tables)
        for (final c in t.columns)
          if (c.type == RemoteType.bytes) '${t.name}.${c.name}',
    ];
    expect(bytes, [
      '${SupabaseRemote.imageTable}.${SupabaseRemote.imageColumn}',
    ]);
  });

  test('every table has Row Level Security and the three rules', () {
    for (final name in ['sync_state', ...SyncMigrations.syncedTables]) {
      final t = 'public."$name"';
      expect(sql, contains('alter table $t enable row level security;'));
      expect(
        sql,
        contains('revoke all on $t from public, anon, authenticated;'),
      );
      expect(
        sql,
        contains('grant select, insert, update on $t to authenticated;'),
      );
      for (final rule in ['read', 'add', 'change']) {
        expect(sql, contains('create policy "own rows: $rule" on $t for '));
      }
    }
    final rules = RegExp('create policy ').allMatches(sql).length;
    final own = RegExp(
      r'user_id = \(select auth\.uid\(\)\)|'
      r'\(storage\.foldername\(name\)\)\[1\] = \(select auth\.uid\(\)\)::text',
    );
    final lines = sql.split('\n');
    var checked = 0;
    for (final (i, line) in lines.indexed) {
      if (!line.startsWith('create policy ')) continue;
      expect(line, contains(' to authenticated'));
      expect(own.hasMatch(lines[i + 1]), isTrue, reason: line);
      checked += 1;
    }
    expect(checked, rules);
    expect(rules, (SyncMigrations.syncedTables.length + 1) * 3 + 3);
  });

  test('nothing is ever deleted, and nothing is open to all', () {
    final lower = sql.toLowerCase();
    final code = [
      for (final line in lower.split('\n'))
        if (!line.trimLeft().startsWith('--')) line,
    ].join('\n');
    for (final word in [
      'drop table',
      'drop column',
      'truncate',
      'delete from',
      'for delete',
      'for all',
      'security definer',
      ' to anon',
      'on delete cascade',
      'using (true)',
    ]) {
      expect(code, isNot(contains(word)), reason: word);
    }
    expect(RegExp(r'grant[^;]* to public').hasMatch(code), isFalse);
    expect(
      code,
      contains("values ('grove-attachments', 'grove-attachments', false)"),
    );
  });

  test('the SQL can run again: every step is "if not exists" or "replace"', () {
    for (final line in sql.split('\n')) {
      if (line.startsWith('create table')) {
        expect(line, startsWith('create table if not exists'));
      }
      if (line.startsWith('create index')) {
        expect(line, startsWith('create index if not exists'));
      }
      if (line.startsWith('create function')) fail(line);
    }
    final made = RegExp(r'^create policy (".*?" on \S+)', multiLine: true);
    for (final m in made.allMatches(sql)) {
      expect(sql, contains('drop policy if exists ${m.group(1)};'));
    }
  });
}
