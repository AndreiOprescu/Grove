-- Grove: the tables of the sync, who can read them, the file store for
-- images, and the two sync functions.
--
-- Made from the schema of the app (number 12) by
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
alter table public."sync_state" enable row level security;
revoke all on public."sync_state" from public, anon, authenticated;
grant select, insert, update on public."sync_state" to authenticated;
drop policy if exists "own rows: read" on public."sync_state";
create policy "own rows: read" on public."sync_state" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."sync_state";
create policy "own rows: add" on public."sync_state" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."sync_state";
create policy "own rows: change" on public."sync_state" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."lists" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."lists" add column if not exists "name" text;
alter table public."lists" add column if not exists "emoji" text;
alter table public."lists" add column if not exists "color" text;
alter table public."lists" add column if not exists "sort" bigint;
alter table public."lists" add column if not exists "archived" bigint;
create index if not exists "lists_user_seq" on public."lists" (user_id, seq);
alter table public."lists" enable row level security;
revoke all on public."lists" from public, anon, authenticated;
grant select, insert, update on public."lists" to authenticated;
drop policy if exists "own rows: read" on public."lists";
create policy "own rows: read" on public."lists" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."lists";
create policy "own rows: add" on public."lists" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."lists";
create policy "own rows: change" on public."lists" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."notes" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."notes" add column if not exists "title" text;
alter table public."notes" add column if not exists "body" text;
alter table public."notes" add column if not exists "kind" text;
alter table public."notes" add column if not exists "date" text;
alter table public."notes" add column if not exists "pinned" bigint;
alter table public."notes" add column if not exists "mood" bigint;
alter table public."notes" add column if not exists "created_at" text;
alter table public."notes" add column if not exists "updated_at" text;
create index if not exists "notes_user_seq" on public."notes" (user_id, seq);
alter table public."notes" enable row level security;
revoke all on public."notes" from public, anon, authenticated;
grant select, insert, update on public."notes" to authenticated;
drop policy if exists "own rows: read" on public."notes";
create policy "own rows: read" on public."notes" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."notes";
create policy "own rows: add" on public."notes" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."notes";
create policy "own rows: change" on public."notes" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."goals" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."goals" add column if not exists "title" text;
alter table public."goals" add column if not exists "notes" text;
alter table public."goals" add column if not exists "color" text;
alter table public."goals" add column if not exists "target_min" bigint;
alter table public."goals" add column if not exists "sort" double precision;
alter table public."goals" add column if not exists "archived" bigint;
alter table public."goals" add column if not exists "created_at" text;
alter table public."goals" add column if not exists "updated_at" text;
alter table public."goals" add column if not exists "kind" text;
alter table public."goals" add column if not exists "target_count" bigint;
create index if not exists "goals_user_seq" on public."goals" (user_id, seq);
alter table public."goals" enable row level security;
revoke all on public."goals" from public, anon, authenticated;
grant select, insert, update on public."goals" to authenticated;
drop policy if exists "own rows: read" on public."goals";
create policy "own rows: read" on public."goals" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."goals";
create policy "own rows: add" on public."goals" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."goals";
create policy "own rows: change" on public."goals" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."tasks" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."tasks" add column if not exists "title" text;
alter table public."tasks" add column if not exists "notes" text;
alter table public."tasks" add column if not exists "list_id" text;
alter table public."tasks" add column if not exists "parent_id" text;
alter table public."tasks" add column if not exists "priority" bigint;
alter table public."tasks" add column if not exists "status" text;
alter table public."tasks" add column if not exists "bucket" text;
alter table public."tasks" add column if not exists "plan_date" text;
alter table public."tasks" add column if not exists "plan_week" text;
alter table public."tasks" add column if not exists "due" text;
alter table public."tasks" add column if not exists "estimate_min" bigint;
alter table public."tasks" add column if not exists "recurrence" text;
alter table public."tasks" add column if not exists "source_note_id" text;
alter table public."tasks" add column if not exists "sort" double precision;
alter table public."tasks" add column if not exists "created_at" text;
alter table public."tasks" add column if not exists "updated_at" text;
alter table public."tasks" add column if not exists "completed_at" text;
alter table public."tasks" add column if not exists "summary" text;
alter table public."tasks" add column if not exists "color" text;
create index if not exists "tasks_user_seq" on public."tasks" (user_id, seq);
alter table public."tasks" enable row level security;
revoke all on public."tasks" from public, anon, authenticated;
grant select, insert, update on public."tasks" to authenticated;
drop policy if exists "own rows: read" on public."tasks";
create policy "own rows: read" on public."tasks" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."tasks";
create policy "own rows: add" on public."tasks" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."tasks";
create policy "own rows: change" on public."tasks" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."events" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."events" add column if not exists "title" text;
alter table public."events" add column if not exists "start" text;
alter table public."events" add column if not exists "end" text;
alter table public."events" add column if not exists "all_day" bigint;
alter table public."events" add column if not exists "kind" text;
alter table public."events" add column if not exists "task_id" text;
alter table public."events" add column if not exists "color" text;
alter table public."events" add column if not exists "location" text;
alter table public."events" add column if not exists "notes" text;
alter table public."events" add column if not exists "recurrence" text;
alter table public."events" add column if not exists "series_id" text;
alter table public."events" add column if not exists "original_date" text;
alter table public."events" add column if not exists "created_at" text;
alter table public."events" add column if not exists "updated_at" text;
alter table public."events" add column if not exists "goal_id" text;
alter table public."events" add column if not exists "done_at" text;
alter table public."events" add column if not exists "is_deadline" bigint;
create index if not exists "events_user_seq" on public."events" (user_id, seq);
alter table public."events" enable row level security;
revoke all on public."events" from public, anon, authenticated;
grant select, insert, update on public."events" to authenticated;
drop policy if exists "own rows: read" on public."events";
create policy "own rows: read" on public."events" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."events";
create policy "own rows: add" on public."events" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."events";
create policy "own rows: change" on public."events" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."block_subtasks" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."block_subtasks" add column if not exists "event_id" text;
alter table public."block_subtasks" add column if not exists "title" text;
alter table public."block_subtasks" add column if not exists "done_at" text;
alter table public."block_subtasks" add column if not exists "sort" double precision;
alter table public."block_subtasks" add column if not exists "created_at" text;
alter table public."block_subtasks" add column if not exists "updated_at" text;
create index if not exists "block_subtasks_user_seq" on public."block_subtasks" (user_id, seq);
alter table public."block_subtasks" enable row level security;
revoke all on public."block_subtasks" from public, anon, authenticated;
grant select, insert, update on public."block_subtasks" to authenticated;
drop policy if exists "own rows: read" on public."block_subtasks";
create policy "own rows: read" on public."block_subtasks" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."block_subtasks";
create policy "own rows: add" on public."block_subtasks" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."block_subtasks";
create policy "own rows: change" on public."block_subtasks" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."goal_subtasks" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."goal_subtasks" add column if not exists "goal_id" text;
alter table public."goal_subtasks" add column if not exists "title" text;
alter table public."goal_subtasks" add column if not exists "done_at" text;
alter table public."goal_subtasks" add column if not exists "sort" double precision;
alter table public."goal_subtasks" add column if not exists "created_at" text;
alter table public."goal_subtasks" add column if not exists "updated_at" text;
alter table public."goal_subtasks" add column if not exists "event_id" text;
create index if not exists "goal_subtasks_user_seq" on public."goal_subtasks" (user_id, seq);
alter table public."goal_subtasks" enable row level security;
revoke all on public."goal_subtasks" from public, anon, authenticated;
grant select, insert, update on public."goal_subtasks" to authenticated;
drop policy if exists "own rows: read" on public."goal_subtasks";
create policy "own rows: read" on public."goal_subtasks" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."goal_subtasks";
create policy "own rows: add" on public."goal_subtasks" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."goal_subtasks";
create policy "own rows: change" on public."goal_subtasks" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."skills" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."skills" add column if not exists "name" text;
alter table public."skills" add column if not exists "sort" double precision;
alter table public."skills" add column if not exists "hidden" bigint;
alter table public."skills" add column if not exists "builtin" bigint;
alter table public."skills" add column if not exists "created_at" text;
alter table public."skills" add column if not exists "updated_at" text;
create index if not exists "skills_user_seq" on public."skills" (user_id, seq);
alter table public."skills" enable row level security;
revoke all on public."skills" from public, anon, authenticated;
grant select, insert, update on public."skills" to authenticated;
drop policy if exists "own rows: read" on public."skills";
create policy "own rows: read" on public."skills" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."skills";
create policy "own rows: add" on public."skills" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."skills";
create policy "own rows: change" on public."skills" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."rewards" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."rewards" add column if not exists "task_id" text;
alter table public."rewards" add column if not exists "goal_id" text;
alter table public."rewards" add column if not exists "skill_id" text;
alter table public."rewards" add column if not exists "points" bigint;
create index if not exists "rewards_user_seq" on public."rewards" (user_id, seq);
alter table public."rewards" enable row level security;
revoke all on public."rewards" from public, anon, authenticated;
grant select, insert, update on public."rewards" to authenticated;
drop policy if exists "own rows: read" on public."rewards";
create policy "own rows: read" on public."rewards" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."rewards";
create policy "own rows: add" on public."rewards" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."rewards";
create policy "own rows: change" on public."rewards" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."earnings" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."earnings" add column if not exists "skill_id" text;
alter table public."earnings" add column if not exists "points" bigint;
alter table public."earnings" add column if not exists "source_kind" text;
alter table public."earnings" add column if not exists "source_id" text;
alter table public."earnings" add column if not exists "title" text;
alter table public."earnings" add column if not exists "earned_at" text;
create index if not exists "earnings_user_seq" on public."earnings" (user_id, seq);
alter table public."earnings" enable row level security;
revoke all on public."earnings" from public, anon, authenticated;
grant select, insert, update on public."earnings" to authenticated;
drop policy if exists "own rows: read" on public."earnings";
create policy "own rows: read" on public."earnings" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."earnings";
create policy "own rows: add" on public."earnings" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."earnings";
create policy "own rows: change" on public."earnings" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."agent_jobs" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."agent_jobs" add column if not exists "task_id" text;
alter table public."agent_jobs" add column if not exists "instructions" text;
alter table public."agent_jobs" add column if not exists "email_access" bigint;
alter table public."agent_jobs" add column if not exists "status" text;
alter table public."agent_jobs" add column if not exists "runner_device" text;
alter table public."agent_jobs" add column if not exists "result_json" text;
alter table public."agent_jobs" add column if not exists "error" text;
alter table public."agent_jobs" add column if not exists "result_note_id" text;
alter table public."agent_jobs" add column if not exists "created_at" text;
alter table public."agent_jobs" add column if not exists "updated_at" text;
alter table public."agent_jobs" add column if not exists "finished_at" text;
create index if not exists "agent_jobs_user_seq" on public."agent_jobs" (user_id, seq);
alter table public."agent_jobs" enable row level security;
revoke all on public."agent_jobs" from public, anon, authenticated;
grant select, insert, update on public."agent_jobs" to authenticated;
drop policy if exists "own rows: read" on public."agent_jobs";
create policy "own rows: read" on public."agent_jobs" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."agent_jobs";
create policy "own rows: add" on public."agent_jobs" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."agent_jobs";
create policy "own rows: change" on public."agent_jobs" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."event_exdates" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "event_id" text not null,
  "date" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "event_id", "date")
);

create index if not exists "event_exdates_user_seq" on public."event_exdates" (user_id, seq);
alter table public."event_exdates" enable row level security;
revoke all on public."event_exdates" from public, anon, authenticated;
grant select, insert, update on public."event_exdates" to authenticated;
drop policy if exists "own rows: read" on public."event_exdates";
create policy "own rows: read" on public."event_exdates" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."event_exdates";
create policy "own rows: add" on public."event_exdates" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."event_exdates";
create policy "own rows: change" on public."event_exdates" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."links" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "src_type" text not null,
  "src_id" text not null,
  "dst_type" text not null,
  "dst_id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "src_type", "src_id", "dst_type", "dst_id")
);
alter table public."links" add column if not exists "origin" text;
create index if not exists "links_user_seq" on public."links" (user_id, seq);
alter table public."links" enable row level security;
revoke all on public."links" from public, anon, authenticated;
grant select, insert, update on public."links" to authenticated;
drop policy if exists "own rows: read" on public."links";
create policy "own rows: read" on public."links" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."links";
create policy "own rows: add" on public."links" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."links";
create policy "own rows: change" on public."links" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."tags" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."tags" add column if not exists "name" text;
create index if not exists "tags_user_seq" on public."tags" (user_id, seq);
alter table public."tags" enable row level security;
revoke all on public."tags" from public, anon, authenticated;
grant select, insert, update on public."tags" to authenticated;
drop policy if exists "own rows: read" on public."tags";
create policy "own rows: read" on public."tags" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."tags";
create policy "own rows: add" on public."tags" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."tags";
create policy "own rows: change" on public."tags" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."task_tags" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "task_id" text not null,
  "tag_id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "task_id", "tag_id")
);

create index if not exists "task_tags_user_seq" on public."task_tags" (user_id, seq);
alter table public."task_tags" enable row level security;
revoke all on public."task_tags" from public, anon, authenticated;
grant select, insert, update on public."task_tags" to authenticated;
drop policy if exists "own rows: read" on public."task_tags";
create policy "own rows: read" on public."task_tags" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."task_tags";
create policy "own rows: add" on public."task_tags" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."task_tags";
create policy "own rows: change" on public."task_tags" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."note_tags" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "note_id" text not null,
  "tag_id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "note_id", "tag_id")
);

create index if not exists "note_tags_user_seq" on public."note_tags" (user_id, seq);
alter table public."note_tags" enable row level security;
revoke all on public."note_tags" from public, anon, authenticated;
grant select, insert, update on public."note_tags" to authenticated;
drop policy if exists "own rows: read" on public."note_tags";
create policy "own rows: read" on public."note_tags" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."note_tags";
create policy "own rows: add" on public."note_tags" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."note_tags";
create policy "own rows: change" on public."note_tags" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."settings" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "key" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "key")
);
alter table public."settings" add column if not exists "value" text;
create index if not exists "settings_user_seq" on public."settings" (user_id, seq);
alter table public."settings" enable row level security;
revoke all on public."settings" from public, anon, authenticated;
grant select, insert, update on public."settings" to authenticated;
drop policy if exists "own rows: read" on public."settings";
create policy "own rows: read" on public."settings" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."settings";
create policy "own rows: add" on public."settings" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."settings";
create policy "own rows: change" on public."settings" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public."attachments" (
  user_id uuid not null default auth.uid() references auth.users (id),
  "id" text not null,
  stamp bigint not null default 0,
  deleted boolean not null default false,
  seq bigint not null default 0,
  primary key (user_id, "id")
);
alter table public."attachments" add column if not exists "mime" text;
alter table public."attachments" add column if not exists "width" bigint;
alter table public."attachments" add column if not exists "height" bigint;
alter table public."attachments" add column if not exists "created_at" text;
create index if not exists "attachments_user_seq" on public."attachments" (user_id, seq);
alter table public."attachments" enable row level security;
revoke all on public."attachments" from public, anon, authenticated;
grant select, insert, update on public."attachments" to authenticated;
drop policy if exists "own rows: read" on public."attachments";
create policy "own rows: read" on public."attachments" for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "own rows: add" on public."attachments";
create policy "own rows: add" on public."attachments" for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "own rows: change" on public."attachments";
create policy "own rows: change" on public."attachments" for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Takes changes. A change is kept when the row is new, or when its stamp is
-- higher than the stamp of the row (the last write wins, for the whole row).
-- A deleted row stays as a row with "deleted" set. Each change gets the next
-- number of the person. Gives the last number.
create or replace function public.sync_push(p_changes jsonb, p_schema integer)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $grove$
declare
  v_user uuid := auth.uid();
  v_seq bigint;
begin
  if v_user is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;
  if p_schema is distinct from 12 then
    raise exception 'Grove schema: the server has 12, the app has %.', p_schema
      using errcode = 'GRV01';
  end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    raise exception 'p_changes must be a JSON array.' using errcode = '22023';
  end if;
  insert into public.sync_state (user_id, last_seq) values (v_user, 0)
    on conflict (user_id) do nothing;
  -- One push at a time for a person, so the numbers rise in the order the
  -- pushes end.
  select s.last_seq into v_seq from public.sync_state s
    where s.user_id = v_user for update;

  insert into public."lists" as t ("user_id", "id", "name", "emoji", "color", "sort", "archived", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."name",
    r."emoji",
    r."color",
    r."sort",
    r."archived",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."lists", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'lists'
  on conflict (user_id, "id") do update set
    "name" = excluded."name",
    "emoji" = excluded."emoji",
    "color" = excluded."color",
    "sort" = excluded."sort",
    "archived" = excluded."archived",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."notes" as t ("user_id", "id", "title", "body", "kind", "date", "pinned", "mood", "created_at", "updated_at", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."title",
    r."body",
    r."kind",
    r."date",
    r."pinned",
    r."mood",
    r."created_at",
    r."updated_at",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."notes", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'notes'
  on conflict (user_id, "id") do update set
    "title" = excluded."title",
    "body" = excluded."body",
    "kind" = excluded."kind",
    "date" = excluded."date",
    "pinned" = excluded."pinned",
    "mood" = excluded."mood",
    "created_at" = excluded."created_at",
    "updated_at" = excluded."updated_at",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."goals" as t ("user_id", "id", "title", "notes", "color", "target_min", "sort", "archived", "created_at", "updated_at", "kind", "target_count", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."title",
    r."notes",
    r."color",
    r."target_min",
    r."sort",
    r."archived",
    r."created_at",
    r."updated_at",
    r."kind",
    r."target_count",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."goals", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'goals'
  on conflict (user_id, "id") do update set
    "title" = excluded."title",
    "notes" = excluded."notes",
    "color" = excluded."color",
    "target_min" = excluded."target_min",
    "sort" = excluded."sort",
    "archived" = excluded."archived",
    "created_at" = excluded."created_at",
    "updated_at" = excluded."updated_at",
    "kind" = excluded."kind",
    "target_count" = excluded."target_count",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."tasks" as t ("user_id", "id", "title", "notes", "list_id", "parent_id", "priority", "status", "bucket", "plan_date", "plan_week", "due", "estimate_min", "recurrence", "source_note_id", "sort", "created_at", "updated_at", "completed_at", "summary", "color", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."title",
    r."notes",
    r."list_id",
    r."parent_id",
    r."priority",
    r."status",
    r."bucket",
    r."plan_date",
    r."plan_week",
    r."due",
    r."estimate_min",
    r."recurrence",
    r."source_note_id",
    r."sort",
    r."created_at",
    r."updated_at",
    r."completed_at",
    r."summary",
    r."color",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."tasks", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'tasks'
  on conflict (user_id, "id") do update set
    "title" = excluded."title",
    "notes" = excluded."notes",
    "list_id" = excluded."list_id",
    "parent_id" = excluded."parent_id",
    "priority" = excluded."priority",
    "status" = excluded."status",
    "bucket" = excluded."bucket",
    "plan_date" = excluded."plan_date",
    "plan_week" = excluded."plan_week",
    "due" = excluded."due",
    "estimate_min" = excluded."estimate_min",
    "recurrence" = excluded."recurrence",
    "source_note_id" = excluded."source_note_id",
    "sort" = excluded."sort",
    "created_at" = excluded."created_at",
    "updated_at" = excluded."updated_at",
    "completed_at" = excluded."completed_at",
    "summary" = excluded."summary",
    "color" = excluded."color",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."events" as t ("user_id", "id", "title", "start", "end", "all_day", "kind", "task_id", "color", "location", "notes", "recurrence", "series_id", "original_date", "created_at", "updated_at", "goal_id", "done_at", "is_deadline", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."title",
    r."start",
    r."end",
    r."all_day",
    r."kind",
    r."task_id",
    r."color",
    r."location",
    r."notes",
    r."recurrence",
    r."series_id",
    r."original_date",
    r."created_at",
    r."updated_at",
    r."goal_id",
    r."done_at",
    r."is_deadline",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."events", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'events'
  on conflict (user_id, "id") do update set
    "title" = excluded."title",
    "start" = excluded."start",
    "end" = excluded."end",
    "all_day" = excluded."all_day",
    "kind" = excluded."kind",
    "task_id" = excluded."task_id",
    "color" = excluded."color",
    "location" = excluded."location",
    "notes" = excluded."notes",
    "recurrence" = excluded."recurrence",
    "series_id" = excluded."series_id",
    "original_date" = excluded."original_date",
    "created_at" = excluded."created_at",
    "updated_at" = excluded."updated_at",
    "goal_id" = excluded."goal_id",
    "done_at" = excluded."done_at",
    "is_deadline" = excluded."is_deadline",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."block_subtasks" as t ("user_id", "id", "event_id", "title", "done_at", "sort", "created_at", "updated_at", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."event_id",
    r."title",
    r."done_at",
    r."sort",
    r."created_at",
    r."updated_at",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."block_subtasks", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'block_subtasks'
  on conflict (user_id, "id") do update set
    "event_id" = excluded."event_id",
    "title" = excluded."title",
    "done_at" = excluded."done_at",
    "sort" = excluded."sort",
    "created_at" = excluded."created_at",
    "updated_at" = excluded."updated_at",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."goal_subtasks" as t ("user_id", "id", "goal_id", "title", "done_at", "sort", "created_at", "updated_at", "event_id", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."goal_id",
    r."title",
    r."done_at",
    r."sort",
    r."created_at",
    r."updated_at",
    r."event_id",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."goal_subtasks", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'goal_subtasks'
  on conflict (user_id, "id") do update set
    "goal_id" = excluded."goal_id",
    "title" = excluded."title",
    "done_at" = excluded."done_at",
    "sort" = excluded."sort",
    "created_at" = excluded."created_at",
    "updated_at" = excluded."updated_at",
    "event_id" = excluded."event_id",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."skills" as t ("user_id", "id", "name", "sort", "hidden", "builtin", "created_at", "updated_at", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."name",
    r."sort",
    r."hidden",
    r."builtin",
    r."created_at",
    r."updated_at",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."skills", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'skills'
  on conflict (user_id, "id") do update set
    "name" = excluded."name",
    "sort" = excluded."sort",
    "hidden" = excluded."hidden",
    "builtin" = excluded."builtin",
    "created_at" = excluded."created_at",
    "updated_at" = excluded."updated_at",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."rewards" as t ("user_id", "id", "task_id", "goal_id", "skill_id", "points", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."task_id",
    r."goal_id",
    r."skill_id",
    r."points",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."rewards", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'rewards'
  on conflict (user_id, "id") do update set
    "task_id" = excluded."task_id",
    "goal_id" = excluded."goal_id",
    "skill_id" = excluded."skill_id",
    "points" = excluded."points",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."earnings" as t ("user_id", "id", "skill_id", "points", "source_kind", "source_id", "title", "earned_at", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."skill_id",
    r."points",
    r."source_kind",
    r."source_id",
    r."title",
    r."earned_at",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."earnings", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'earnings'
  on conflict (user_id, "id") do update set
    "skill_id" = excluded."skill_id",
    "points" = excluded."points",
    "source_kind" = excluded."source_kind",
    "source_id" = excluded."source_id",
    "title" = excluded."title",
    "earned_at" = excluded."earned_at",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."agent_jobs" as t ("user_id", "id", "task_id", "instructions", "email_access", "status", "runner_device", "result_json", "error", "result_note_id", "created_at", "updated_at", "finished_at", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."task_id",
    r."instructions",
    r."email_access",
    r."status",
    r."runner_device",
    r."result_json",
    r."error",
    r."result_note_id",
    r."created_at",
    r."updated_at",
    r."finished_at",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."agent_jobs", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'agent_jobs'
  on conflict (user_id, "id") do update set
    "task_id" = excluded."task_id",
    "instructions" = excluded."instructions",
    "email_access" = excluded."email_access",
    "status" = excluded."status",
    "runner_device" = excluded."runner_device",
    "result_json" = excluded."result_json",
    "error" = excluded."error",
    "result_note_id" = excluded."result_note_id",
    "created_at" = excluded."created_at",
    "updated_at" = excluded."updated_at",
    "finished_at" = excluded."finished_at",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."event_exdates" as t ("user_id", "event_id", "date", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    split_part(c.item->>'key', chr(31), 2),
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."event_exdates", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'event_exdates'
  on conflict (user_id, "event_id", "date") do update set
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."links" as t ("user_id", "src_type", "src_id", "dst_type", "dst_id", "origin", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    split_part(c.item->>'key', chr(31), 2),
    split_part(c.item->>'key', chr(31), 3),
    split_part(c.item->>'key', chr(31), 4),
    r."origin",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."links", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'links'
  on conflict (user_id, "src_type", "src_id", "dst_type", "dst_id") do update set
    "origin" = excluded."origin",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."tags" as t ("user_id", "id", "name", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."name",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."tags", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'tags'
  on conflict (user_id, "id") do update set
    "name" = excluded."name",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."task_tags" as t ("user_id", "task_id", "tag_id", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    split_part(c.item->>'key', chr(31), 2),
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."task_tags", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'task_tags'
  on conflict (user_id, "task_id", "tag_id") do update set
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."note_tags" as t ("user_id", "note_id", "tag_id", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    split_part(c.item->>'key', chr(31), 2),
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."note_tags", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'note_tags'
  on conflict (user_id, "note_id", "tag_id") do update set
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."settings" as t ("user_id", "key", "value", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."value",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."settings", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'settings'
  on conflict (user_id, "key") do update set
    "value" = excluded."value",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  insert into public."attachments" as t ("user_id", "id", "mime", "width", "height", "created_at", "stamp", "deleted", "seq")
  select v_user,
    split_part(c.item->>'key', chr(31), 1),
    r."mime",
    r."width",
    r."height",
    r."created_at",
    (c.item->>'stamp')::bigint,
    coalesce((c.item->>'deleted')::boolean, false),
    v_seq + c.ord
  from jsonb_array_elements(p_changes) with ordinality as c(item, ord)
  cross join lateral jsonb_populate_record(
    null::public."attachments", coalesce(c.item->'data', '{}'::jsonb)) as r
  where c.item->>'table' = 'attachments'
  on conflict (user_id, "id") do update set
    "mime" = excluded."mime",
    "width" = excluded."width",
    "height" = excluded."height",
    "created_at" = excluded."created_at",
    "stamp" = excluded."stamp",
    "deleted" = excluded."deleted",
    "seq" = excluded."seq"
  where t.stamp < excluded.stamp;

  update public.sync_state s set last_seq = v_seq + jsonb_array_length(p_changes)
    where s.user_id = v_user;
  return v_seq + jsonb_array_length(p_changes);
end;
$grove$;

-- Gives the changes of the person with a number above p_after, lowest
-- first, p_limit at most.
create or replace function public.sync_pull(p_after bigint, p_limit integer, p_schema integer)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $grove$
declare
  v_user uuid := auth.uid();
  v_to bigint;
  v_out jsonb;
begin
  if v_user is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;
  if p_schema is distinct from 12 then
    raise exception 'Grove schema: the server has 12, the app has %.', p_schema
      using errcode = 'GRV01';
  end if;
  select max(z.seq) into v_to from (
    select u.seq from (
      select t.seq from public."lists" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."notes" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."goals" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."tasks" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."events" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."block_subtasks" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."goal_subtasks" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."skills" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."rewards" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."earnings" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."agent_jobs" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."event_exdates" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."links" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."tags" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."task_tags" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."note_tags" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."settings" t where t.user_id = v_user and t.seq > p_after
      union all
      select t.seq from public."attachments" t where t.user_id = v_user and t.seq > p_after
    ) u order by u.seq limit greatest(p_limit, 0)
  ) z;
  if v_to is null then
    return '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(u.item order by u.seq), '[]'::jsonb) into v_out from (
    select t.seq, jsonb_build_object(
      'table', 'lists', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."lists" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'notes', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."notes" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'goals', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."goals" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'tasks', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."tasks" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'events', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."events" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'block_subtasks', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."block_subtasks" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'goal_subtasks', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."goal_subtasks" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'skills', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."skills" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'rewards', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."rewards" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'earnings', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."earnings" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'agent_jobs', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."agent_jobs" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'event_exdates', 'key', t."event_id" || chr(31) || t."date",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."event_exdates" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'links', 'key', t."src_type" || chr(31) || t."src_id" || chr(31) || t."dst_type" || chr(31) || t."dst_id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."links" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'tags', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."tags" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'task_tags', 'key', t."task_id" || chr(31) || t."tag_id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."task_tags" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'note_tags', 'key', t."note_id" || chr(31) || t."tag_id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."note_tags" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'settings', 'key', t."key",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."settings" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
    union all
    select t.seq, jsonb_build_object(
      'table', 'attachments', 'key', t."id",
      'stamp', t.stamp, 'deleted', t.deleted, 'seq', t.seq,
      'data', case when t.deleted then '{}'::jsonb
        else to_jsonb(t) - '{user_id,stamp,deleted,seq}'::text[] end) as item
    from public."attachments" t
    where t.user_id = v_user and t.seq > p_after and t.seq <= v_to
  ) u;
  return v_out;
end;
$grove$;

revoke all on function public.sync_push(jsonb, integer) from public, anon;
revoke all on function public.sync_pull(bigint, integer, integer) from public, anon;
grant execute on function public.sync_push(jsonb, integer) to authenticated;
grant execute on function public.sync_pull(bigint, integer, integer) to authenticated;

-- The bytes of images. A private bucket. A person reads and writes only the
-- files in the folder with the person's own id.
insert into storage.buckets (id, name, public) values ('grove-attachments', 'grove-attachments', false)
  on conflict (id) do nothing;
drop policy if exists "grove images: own files, read" on storage.objects;
create policy "grove images: own files, read" on storage.objects for select to authenticated
  using (bucket_id = 'grove-attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "grove images: own files, add" on storage.objects;
create policy "grove images: own files, add" on storage.objects for insert to authenticated
  with check (bucket_id = 'grove-attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "grove images: own files, change" on storage.objects;
create policy "grove images: own files, change" on storage.objects for update to authenticated
  using (bucket_id = 'grove-attachments' and (storage.foldername(name))[1] = (select auth.uid())::text) with check (bucket_id = 'grove-attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);
