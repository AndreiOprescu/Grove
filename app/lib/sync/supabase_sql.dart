import 'remote_schema.dart';

/// The names the app and the SQL share.
abstract final class SupabaseNames {
  /// The private bucket for the bytes of images. A file is at
  /// `<user id>/<attachment id>`.
  static const bucket = 'grove-attachments';

  static const push = 'sync_push';
  static const pull = 'sync_pull';

  /// The SQL state of "the app and the server have another schema number".
  static const schemaMismatch = 'GRV01';

  /// The SQL state of "nobody is signed in".
  static const notSignedIn = '28000';

  /// The columns the remote adds to every table.
  static const added = ['user_id', 'stamp', 'deleted', 'seq'];

  /// Goes between the parts of a key with more than one column
  /// (`SyncSchema.separator`).
  static const separatorCode = 31;
}

String _q(String name) => '"${name.replaceAll('"', '""')}"';

String _sqlType(RemoteType type) => switch (type) {
  RemoteType.text => 'text',
  RemoteType.integer => 'bigint',
  RemoteType.real => 'double precision',
  RemoteType.bytes => throw StateError('Bytes are not in a remote table.'),
};

const _own = 'user_id = (select auth.uid())';

String _policies(String table) {
  final t = 'public.${_q(table)}';
  return '''
alter table $t enable row level security;
revoke all on $t from public, anon, authenticated;
grant select, insert, update on $t to authenticated;
drop policy if exists "own rows: read" on $t;
create policy "own rows: read" on $t for select to authenticated
  using ($_own);
drop policy if exists "own rows: add" on $t;
create policy "own rows: add" on $t for insert to authenticated
  with check ($_own);
drop policy if exists "own rows: change" on $t;
create policy "own rows: change" on $t for update to authenticated
  using ($_own) with check ($_own);
''';
}

String _table(RemoteTable table) {
  final t = 'public.${_q(table.name)}';
  final keys = table.keyColumns;
  final rest = [
    for (final c in table.stored)
      if (!keys.contains(c.name)) c,
  ];
  return '''
create table if not exists $t (
  user_id uuid not null default auth.uid() references auth.users (id),
${keys.map((k) => '  ${_q(k)} text not null,').join('\n')}
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, ${keys.map(_q).join(', ')})
);
${rest.map((c) => 'alter table $t add column if not exists ${_q(c.name)} ${_sqlType(c.type)};').join('\n')}
create index if not exists ${_q('${table.name}_user_seq')} on $t (user_id, seq);
${_policies(table.name)}''';
}

/// The key of a row as one text, from the columns of the row [row].
String _keyOf(RemoteTable table, String row) => table.keyColumns
    .map((k) => '$row.${_q(k)}')
    .join(' || chr(${SupabaseNames.separatorCode}) || ');

String _pushTable(RemoteTable table) {
  final t = 'public.${_q(table.name)}';
  final keys = table.keyColumns;
  final rest = [
    for (final c in table.stored)
      if (!keys.contains(c.name)) c.name,
  ];
  final columns = ['user_id', ...keys, ...rest, 'stamp', 'deleted', 'seq'];
  final values = [
    'v_user',
    for (final (i, _) in keys.indexed)
      "split_part(c.item->>'key', chr(${SupabaseNames.separatorCode}), ${i + 1})",
    for (final c in rest) 'r.${_q(c)}',
    "(c.item->>'stamp')::bigint",
    "coalesce((c.item->>'deleted')::boolean, false)",
    'v_seq + c.ord',
  ];
  final updates = [
    for (final c in [...rest, 'stamp', 'deleted', 'seq'])
      '${_q(c)} = excluded.${_q(c)}',
  ];
  return '''
  insert into $t as t (${columns.map(_q).join(', ')})
  select ${values.join(',\n    ')}
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::$t, coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = '${table.name}'
  on conflict (user_id, ${keys.map(_q).join(', ')}) do update set
    ${updates.join(',\n    ')}
  where t.stamp < excluded.stamp;
''';
}

String _checks(int version) =>
    '''
  if v_user is null then
    raise exception 'Not signed in.' using errcode = '${SupabaseNames.notSignedIn}';
  end if;
  if p_schema is distinct from $version then
    raise exception 'Grove schema: the server has $version, the app has %.', p_schema
      using errcode = '${SupabaseNames.schemaMismatch}';
  end if;''';

String _functions(RemoteSchema schema) {
  final tables = schema.tables;
  final seqs = [
    for (final t in tables)
      '      select t.seq from public.${_q(t.name)} t '
          'where t.user_id = v_user and t.seq > p_after',
  ].join('\n      union all\n');
  final rows = [
    for (final t in tables)
      '''
    select t.seq, jsonb_build_object(
      'table', '${t.name}', 'key', ${_keyOf(t, 't')},
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{${SupabaseNames.added.join(',')}}'::text[] end) as item
    from public.${_q(t.name)} t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to''',
  ].join('\n    union all\n');
  return '''
-- Takes changes. A change is kept when the row is new, or when its stamp is
-- higher than the stamp of the row (the last write wins, for the whole row).
-- A deleted row stays as a row with "deleted" set. Each change gets the next
-- number of the person. Gives the last number.
create or replace function public.${SupabaseNames.push}(p_changes jsonb, p_schema integer)
returns bigint
language plpgsql
security invoker
set search_path = ''
as \$grove\$
declare
  v_user uuid := auth.uid();
  v_seq bigint;
begin
${_checks(schema.version)}
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    raise exception 'p_changes must be a JSON array.' using errcode = '22023';
  end if;
  insert into public.sync_state (user_id, last_seq) values (v_user, 0)
    on conflict (user_id) do nothing;
  -- One push at a time for a person, so the numbers rise in the order the
  -- pushes end.
  select s.last_seq into v_seq from public.sync_state s
    where s.user_id = v_user for update;

${tables.map(_pushTable).join('\n')}
  update public.sync_state s set last_seq = v_seq + jsonb_array_length(p_changes)
    where s.user_id = v_user;
  return v_seq + jsonb_array_length(p_changes);
end;
\$grove\$;

-- Gives the changes of the person with a number above p_after, lowest
-- first, p_limit at most.
create or replace function public.${SupabaseNames.pull}(p_after bigint, p_limit integer, p_schema integer)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as \$grove\$
declare
  v_user uuid := auth.uid();
  v_to bigint;
  v_out jsonb;
begin
${_checks(schema.version)}
  select max(z.seq) into v_to from (
    select u.seq from (
$seqs
    ) u order by u.seq limit greatest(p_limit, 0)
  ) z;
  if v_to is null then
    return '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(u.item order by u.seq), '[]'::jsonb) into v_out from (
$rows
  ) u;
  return v_out;
end;
\$grove\$;

revoke all on function public.${SupabaseNames.push}(jsonb, integer) from public, anon;
revoke all on function public.${SupabaseNames.pull}(bigint, integer, integer) from public, anon;
grant execute on function public.${SupabaseNames.push}(jsonb, integer) to authenticated;
grant execute on function public.${SupabaseNames.pull}(bigint, integer, integer) to authenticated;
''';
}

String _storage() {
  const b = SupabaseNames.bucket;
  const mine =
      "bucket_id = '$b' and (storage.foldername(name))[1] = (select auth.uid())::text";
  return '''
-- The bytes of images. A private bucket. A person reads and writes only the
-- files in the folder with the person's own id.
insert into storage.buckets (id, name, public) values ('$b', '$b', false)
  on conflict (id) do nothing;
drop policy if exists "grove images: own files, read" on storage.objects;
create policy "grove images: own files, read" on storage.objects for select to authenticated
  using ($mine);
drop policy if exists "grove images: own files, add" on storage.objects;
create policy "grove images: own files, add" on storage.objects for insert to authenticated
  with check ($mine);
drop policy if exists "grove images: own files, change" on storage.objects;
create policy "grove images: own files, change" on storage.objects for update to authenticated
  using ($mine) with check ($mine);
''';
}

/// The SQL that makes a Supabase project ready for the sync of this app:
/// one table for each synced table, Row Level Security, the bucket for
/// images, and the functions `sync_push` and `sync_pull`.
///
/// The file in `supabase/migrations/` is this text. A test compares them.
String supabaseSql(RemoteSchema schema) {
  for (final t in schema.tables) {
    for (final c in t.columns) {
      if (SupabaseNames.added.contains(c.name)) {
        throw StateError('${t.name}.${c.name} has a name the remote uses.');
      }
    }
    for (final k in t.keyColumns) {
      if (t.column(k)?.type != RemoteType.text) {
        throw StateError('The key column ${t.name}.$k is not text.');
      }
    }
  }
  return '''
-- Grove: the tables of the sync, who can read them, the file store for
-- images, and the two sync functions.
--
-- Made from the schema of the app (number ${schema.version}) by
-- app/lib/sync/supabase_sql.dart. Do not change this file by hand. When the
-- schema of the app changes, make a new file:
--   cd app && GROVE_WRITE_SQL=<new file name> flutter test test/sync/supabase_sql_test.dart
--
-- Safe to run again. It never drops a table or a column and never deletes
-- a row. No delete is allowed: a deleted row stays with "deleted" set.

-- The last number given to a change, for each person.
create table if not exists public.sync_state (
  user_id uuid primary key default auth.uid() references auth.users (id),
  last_seq bigint not null default 0
);
${_policies('sync_state')}
${schema.tables.map(_table).join('\n')}
${_functions(schema)}
${_storage()}''';
}
