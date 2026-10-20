-- Run by run.sh after the migration ran one more time on a database with
-- rows: the rows are still there, and the rules are as they were.
\o /dev/null
select grove_test.ok((select count(*) from public.tasks) = 2, 'the rows are still there');
select grove_test.ok((select count(*) from public.lists where deleted) = 1, 'the deleted row is still there');
select grove_test.ok((select last_seq from public.sync_state
  where user_id = '11111111-1111-4111-8111-111111111111') = 8, 'the counter is as it was');
select grove_test.ok((select count(*) from storage.objects) = 1, 'the file is still there');
select grove_test.ok((select count(*) from storage.buckets) = 1, 'there is one bucket');
select grove_test.ok(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r') = 19,
  'there are 18 data tables and the counter');
select grove_test.ok(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity) = 0,
  'each table has row level security');
select grove_test.ok(
  (select count(*) from pg_policies where schemaname = 'public') = 57,
  'each table has its 3 rules, one time');
select grove_test.ok(
  (select count(*) from pg_policies where schemaname = 'public' and cmd = 'DELETE') = 0,
  'no rule allows a delete');
select grove_test.ok(
  (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects') = 3,
  'the file store has its 3 rules, one time');
select grove_test.ok(
  (select count(*) from information_schema.role_table_grants
    where table_schema = 'public' and grantee in ('anon', 'PUBLIC')) = 0,
  'anon has no right on a table');
select grove_test.ok(
  (select count(*) from information_schema.role_table_grants
    where table_schema = 'public' and grantee = 'authenticated'
      and privilege_type not in ('SELECT', 'INSERT', 'UPDATE')) = 0,
  'a person can read, add and change, and nothing more');
select grove_test.ok(
  not has_function_privilege('anon', 'public.sync_push(jsonb, integer)', 'execute')
  and not has_function_privilege('anon', 'public.sync_pull(bigint, integer, integer)', 'execute'),
  'anon cannot call the sync functions');
