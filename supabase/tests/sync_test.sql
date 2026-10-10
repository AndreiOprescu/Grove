-- Checks of the Grove SQL: the two sync functions, who can read what, and
-- the file store. Run by run.sh, after stub_supabase.sql and the migration.
\set a '11111111-1111-4111-8111-111111111111'
\set b '22222222-2222-4222-8222-222222222222'
\o /dev/null

insert into auth.users (id, email) values (:'a', 'a@example.com'), (:'b', 'b@example.com');

-- Nobody is signed in.
set role anon;
select grove_test.fails($$select public.sync_push('[]'::jsonb, 7)$$, '42501', 'anon cannot call sync_push');
select grove_test.fails($$select public.sync_pull(0, 10, 7)$$, '42501', 'anon cannot call sync_pull');
select grove_test.fails($$select count(*) from public.tasks$$, '42501', 'anon cannot read a table');
select grove_test.fails($$insert into public.lists (id) values ('x')$$, '42501', 'anon cannot write a table');
reset role;

set role authenticated;
select grove_test.sign_in('');
select grove_test.fails($$select public.sync_push('[]'::jsonb, 7)$$, '28000', 'no person: sync_push says "not signed in"');
select grove_test.fails($$select public.sync_pull(0, 10, 7)$$, '28000', 'no person: sync_pull says "not signed in"');

-- Person A.
select grove_test.sign_in(:'a');
select grove_test.fails($$select public.sync_push('[]'::jsonb, 6)$$, 'GRV01', 'an app with an older schema cannot push');
select grove_test.fails($$select public.sync_pull(0, 10, 8)$$, 'GRV01', 'an app with a newer schema cannot pull');
select grove_test.fails($$select public.sync_push('{}'::jsonb, 7)$$, '22023', 'the changes must be a list');
select grove_test.ok(public.sync_pull(0, 10, 7) = '[]'::jsonb, 'a new account has nothing');
select grove_test.ok(public.sync_push('[]'::jsonb, 7) = 0, 'a push of nothing gives the number 0');

select grove_test.ok(public.sync_push($j$[
  {"table": "lists", "key": "l1", "stamp": 10, "deleted": false,
   "data": {"id": "l1", "name": "Home", "emoji": "", "color": "green", "sort": 1, "archived": 0}},
  {"table": "tasks", "key": "t1", "stamp": 11, "deleted": false,
   "data": {"id": "t1", "title": "Buy milk", "list_id": "l1", "priority": 2, "sort": 1.5}},
  {"table": "task_tags", "key": "t1\u001ftag1", "stamp": 12, "deleted": false,
   "data": {"task_id": "t1", "tag_id": "tag1"}}
]$j$::jsonb, 7) = 3, 'a push of 3 changes gives the number 3');

select grove_test.ok(jsonb_array_length(public.sync_pull(0, 100, 7)) = 3, 'a pull gives the 3 changes');
select grove_test.ok(
  (select array_agg((e.x->>'seq')::int order by e.o)
     from jsonb_array_elements(public.sync_pull(0, 100, 7)) with ordinality as e(x, o)) = array[1, 2, 3],
  'the lowest number comes first');
select grove_test.ok(
  (select array_agg(e.x->>'table' order by e.o)
     from jsonb_array_elements(public.sync_pull(0, 100, 7)) with ordinality as e(x, o))
    = array['lists', 'tasks', 'task_tags'],
  'each change says its table');
select grove_test.ok(public.sync_pull(0, 100, 7)->1->>'key' = 't1', 'a change says its key');
select grove_test.ok((public.sync_pull(0, 100, 7)->1->>'stamp')::bigint = 11, 'a change says its stamp');
select grove_test.ok(public.sync_pull(0, 100, 7)->1->'data'->>'title' = 'Buy milk', 'a text comes back');
select grove_test.ok(public.sync_pull(0, 100, 7)->1->'data'->'priority' = '2'::jsonb, 'a whole number comes back as a number');
select grove_test.ok(public.sync_pull(0, 100, 7)->1->'data'->'sort' = '1.5'::jsonb, 'a number with a point comes back');
select grove_test.ok(public.sync_pull(0, 100, 7)->1->'data'->'due' = 'null'::jsonb, 'a column that was not sent is empty');
select grove_test.ok(not (public.sync_pull(0, 100, 7)->1->'data' ?| array['user_id', 'stamp', 'deleted', 'seq']),
  'the data has only the columns of the app');
select grove_test.ok(public.sync_pull(0, 100, 7)->2->>'key' = 't1' || chr(31) || 'tag1', 'a key of two columns comes back whole');
select grove_test.ok(public.sync_pull(0, 100, 7)->2->'data' = '{"task_id": "t1", "tag_id": "tag1"}'::jsonb,
  'a row with only key columns comes back');

-- Pages.
select grove_test.ok(jsonb_array_length(public.sync_pull(1, 1, 7)) = 1, 'the limit of a pull is kept');
select grove_test.ok((public.sync_pull(1, 1, 7)->0->>'seq')::int = 2, 'a pull starts after the given number');
select grove_test.ok(public.sync_pull(3, 100, 7) = '[]'::jsonb, 'nothing new: an empty list');

-- The last write wins.
select grove_test.ok(public.sync_push($j$[
  {"table": "tasks", "key": "t1", "stamp": 5, "deleted": false, "data": {"id": "t1", "title": "Older"}}
]$j$::jsonb, 7) = 4, 'each change takes a number, also one that loses');
select grove_test.ok((select title from public.tasks where id = 't1') = 'Buy milk', 'an older change does not win');
select grove_test.ok(public.sync_push($j$[
  {"table": "tasks", "key": "t1", "stamp": 11, "deleted": false, "data": {"id": "t1", "title": "Same time"}}
]$j$::jsonb, 7) = 5, 'a change with the same stamp takes a number');
select grove_test.ok((select title from public.tasks where id = 't1') = 'Buy milk', 'a change with the same stamp does not win');
select grove_test.ok(public.sync_pull(3, 100, 7) = '[]'::jsonb, 'a change that lost is not sent to the devices');
select grove_test.ok(public.sync_push($j$[
  {"table": "tasks", "key": "t1", "stamp": 20, "deleted": false, "data": {"id": "t1", "title": "Buy oat milk"}}
]$j$::jsonb, 7) = 6, 'a newer change takes the next number');
select grove_test.ok((select title from public.tasks where id = 't1') = 'Buy oat milk', 'a newer change wins');
select grove_test.ok((select list_id from public.tasks where id = 't1') is null, 'the newer row wins as a whole');
select grove_test.ok(jsonb_array_length(public.sync_pull(3, 100, 7)) = 1, 'the change that won is sent one time');
select grove_test.ok((public.sync_pull(3, 100, 7)->0->>'seq')::int = 6, 'the change that won has the new number');

-- A deleted row stays, with a mark.
select grove_test.ok(public.sync_push($j$[
  {"table": "lists", "key": "l1", "stamp": 30, "deleted": true, "data": {}}
]$j$::jsonb, 7) = 7, 'a delete takes a number');
select grove_test.ok((select count(*) from public.lists where id = 'l1' and deleted) = 1, 'a deleted row stays, with the mark');
select grove_test.ok((public.sync_pull(6, 100, 7)->0->>'deleted')::boolean, 'a pull says that the row is deleted');
select grove_test.ok(public.sync_pull(6, 100, 7)->0->'data' = '{}'::jsonb, 'a deleted row has no data');
select grove_test.ok(public.sync_push($j$[
  {"table": "lists", "key": "l1", "stamp": 25, "deleted": false, "data": {"id": "l1", "name": "Back"}}
]$j$::jsonb, 7) = 8, 'an older change after a delete takes a number');
select grove_test.ok((select deleted from public.lists where id = 'l1'), 'an older change does not bring a deleted row back');

-- No delete, and no row for another person.
select grove_test.fails($$delete from public.tasks$$, '42501', 'a person cannot delete rows');
select grove_test.fails(
  format('insert into public.lists (user_id, id, name) values (%L, %L, %L)', :'b', 'x', 'x'),
  '42501', 'a person cannot add a row for another person');
select grove_test.fails(
  format('update public.tasks set user_id = %L', :'b'),
  '42501', 'a person cannot give a row to another person');

-- Person B sees and changes nothing of A.
select grove_test.sign_in(:'b');
select grove_test.ok(public.sync_pull(0, 100, 7) = '[]'::jsonb, 'another person pulls nothing');
select grove_test.ok((select count(*) from public.tasks) = 0, 'another person reads no rows');
select grove_test.ok((select count(*) from public.sync_state) = 0, 'another person does not see the counter');
with u as (update public.tasks set title = 'changed by B' returning 1)
select grove_test.ok((select count(*) from u) = 0, 'another person changes no rows');
select grove_test.ok(public.sync_push($j$[
  {"table": "tasks", "key": "t1", "stamp": 99, "deleted": false, "data": {"id": "t1", "title": "The task of B"}}
]$j$::jsonb, 7) = 1, 'each person has numbers of their own');
select grove_test.ok(public.sync_pull(0, 100, 7)->0->'data'->>'title' = 'The task of B', 'B pulls the row of B');

select grove_test.sign_in(:'a');
select grove_test.ok((select title from public.tasks where id = 't1') = 'Buy oat milk', 'the row of A with the same id is as it was');
select grove_test.ok((select count(*) from public.tasks) = 1, 'A reads only the rows of A');
select grove_test.ok(public.sync_pull(8, 100, 7) = '[]'::jsonb, 'A pulls nothing of B');

-- The file store.
select grove_test.ok(
  (select count(*) from storage.buckets where id = 'grove-attachments' and public = false) = 1,
  'the bucket is there, and it is private');
insert into storage.objects (bucket_id, name) values ('grove-attachments', :'a' || '/img1');
select grove_test.ok((select count(*) from storage.objects) = 1, 'a person adds a file in the folder with the own id');
select grove_test.fails(
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'grove-attachments', :'b' || '/img2'),
  '42501', 'a person cannot add a file in the folder of another person');
select grove_test.fails(
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'grove-attachments', 'img3'),
  '42501', 'a person cannot add a file outside a folder');
select grove_test.fails(
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'other', :'a' || '/img4'),
  '42501', 'the rules do not open another bucket');
with u as (update storage.objects set owner = null where name = :'a' || '/img1' returning 1)
select grove_test.ok((select count(*) from u) = 1, 'a person can write the own file again');
with u as (delete from storage.objects returning 1)
select grove_test.ok((select count(*) from u) = 0, 'no file is deleted');

select grove_test.sign_in(:'b');
select grove_test.ok((select count(*) from storage.objects) = 0, 'another person sees no file');
with u as (update storage.objects set name = :'b' || '/stolen' returning 1)
select grove_test.ok((select count(*) from u) = 0, 'another person changes no file');
reset role;

set role anon;
select grove_test.sign_in('');
select grove_test.ok((select count(*) from storage.objects) = 0, 'anon sees no file');
select grove_test.fails(
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'grove-attachments', :'a' || '/img5'),
  '42501', 'anon cannot add a file');
reset role;

-- The owner of the database sees the rows of both.
select grove_test.ok((select count(*) from public.tasks) = 2, 'the database has the rows of both persons');
