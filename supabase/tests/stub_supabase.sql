-- A small stand-in for the parts of Supabase that the Grove SQL uses: the
-- two roles, the login tables and the file store tables. It is for the
-- check in run.sh only. Never run it on a Supabase project.

do $$
begin
  if not exists (select from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end
$$;

grant usage on schema public to anon, authenticated;
-- Supabase gives both roles all rights on each new table and function of
-- "public". The Grove SQL has to take them away again.
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant execute on functions to anon, authenticated;

create schema auth;
grant usage on schema auth to anon, authenticated;
create table auth.users (
  id uuid primary key,
  email text
);
-- The id of the person of the request, as Supabase gives it.
create function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

create schema storage;
grant usage on schema storage to anon, authenticated;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text,
  name text,
  owner uuid,
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;
grant all on storage.objects, storage.buckets to anon, authenticated;
-- The folders of a file name, as Supabase gives them.
create function storage.foldername(name text) returns text[]
language plpgsql
as $$
declare
  _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1:array_length(_parts, 1) - 1];
end
$$;

-- Helpers of the checks.
create schema grove_test;
grant usage on schema grove_test to anon, authenticated;

create function grove_test.ok(p_ok boolean, p_what text) returns void
language plpgsql
as $$
begin
  if p_ok is not true then
    raise exception 'FAILED: %', p_what;
  end if;
  raise notice 'ok: %', p_what;
end
$$;

-- Runs p_sql and wants the error with the SQL state p_state.
create function grove_test.fails(p_sql text, p_state text, p_what text) returns void
language plpgsql
as $$
declare
  v_state text;
  v_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_state = p_state then
      raise notice 'ok: %', p_what;
      return;
    end if;
    raise exception 'FAILED: % (state %, wanted %: %)', p_what, v_state, p_state, v_message;
  end;
  raise exception 'FAILED: % (no error, wanted %)', p_what, p_state;
end
$$;

-- The person of the requests from here on. An empty text: nobody.
create function grove_test.sign_in(p_user text) returns void
language sql
as $$ select set_config('request.jwt.claim.sub', p_user, false) $$;
