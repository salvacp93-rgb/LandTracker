-- Run this AFTER:
-- 1) SupabaseCloudSetup.sql
-- 2) SupabaseUserManagementSetup.sql
--
-- Goal (phase 2):
-- - Harden against abusive write traffic from compromised accounts/sessions.
-- - Reduce blast radius of oversized payloads.
-- - Prevent concurrent abuse of internal workers (push cron).

create extension if not exists "pgcrypto";

create table if not exists public.security_events (
  id bigserial primary key,
  scope text not null,
  identifier text not null,
  table_name text,
  operation text,
  reason text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_security_events_created_at
  on public.security_events (created_at desc);

create table if not exists public.worker_job_locks (
  job_name text primary key,
  lock_token uuid not null,
  locked_until timestamptz not null,
  updated_at timestamptz not null default now()
);

create index if not exists idx_worker_job_locks_locked_until
  on public.worker_job_locks (locked_until);

create or replace function public.cleanup_security_telemetry(
  p_keep_events_days integer default 45
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_keep_days integer;
begin
  v_keep_days := greatest(coalesce(p_keep_events_days, 45), 7);

  delete from public.security_events
  where created_at < now() - make_interval(days => v_keep_days);

  delete from public.worker_job_locks
  where locked_until < now() - interval '1 day';
end;
$$;

create or replace function public.acquire_worker_job_lock(
  p_job_name text,
  p_lock_seconds integer default 90
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_name text;
  v_lock_seconds integer;
  v_token uuid;
begin
  v_job_name := lower(btrim(coalesce(p_job_name, '')));
  if v_job_name = '' then
    raise exception 'job_name is required';
  end if;

  v_lock_seconds := greatest(coalesce(p_lock_seconds, 90), 15);
  v_token := gen_random_uuid();

  insert into public.worker_job_locks (
    job_name,
    lock_token,
    locked_until,
    updated_at
  )
  values (
    v_job_name,
    v_token,
    now() + make_interval(secs => v_lock_seconds),
    now()
  )
  on conflict (job_name) do update
    set lock_token = excluded.lock_token,
        locked_until = excluded.locked_until,
        updated_at = now()
  where public.worker_job_locks.locked_until < now();

  if not found then
    return null;
  end if;

  return v_token;
end;
$$;

create or replace function public.release_worker_job_lock(
  p_job_name text,
  p_lock_token uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_name text;
begin
  v_job_name := lower(btrim(coalesce(p_job_name, '')));
  if v_job_name = '' or p_lock_token is null then
    return false;
  end if;

  delete from public.worker_job_locks
  where job_name = v_job_name
    and lock_token = p_lock_token;

  return found;
end;
$$;

create or replace function public.enforce_client_write_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid;
  v_identifier text;
  v_scope_prefix text;
  v_minute_limit integer;
  v_hour_limit integer;
begin
  -- Ignore non-authenticated contexts (maintenance/backfill/admin SQL editor).
  v_user_id := auth.uid();
  if v_user_id is null then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  -- Do not limit trusted server-side calls signed with service_role.
  if coalesce(auth.role(), '') = 'service_role' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  v_identifier := coalesce(
    'user:' || v_user_id::text,
    public.request_client_identifier(),
    'unknown'
  );

  -- Global caps across all operational writes.
  perform public.enforce_rate_limit('app_write_global_burst', v_identifier, 240, 60);
  perform public.enforce_rate_limit('app_write_global_hourly', v_identifier, 4000, 3600);

  v_scope_prefix := lower(btrim(tg_table_name));

  -- Table-specific caps (tighter on sensitive tables).
  if v_scope_prefix in ('organization_members', 'organization_invitations') then
    v_minute_limit := 30;
    v_hour_limit := 500;
  elsif v_scope_prefix in ('push_devices', 'land_task_push_deliveries') then
    v_minute_limit := 80;
    v_hour_limit := 2000;
  elsif v_scope_prefix in ('land_history_entries', 'land_tasks') then
    v_minute_limit := 140;
    v_hour_limit := 2600;
  else
    v_minute_limit := 90;
    v_hour_limit := 1800;
  end if;

  perform public.enforce_rate_limit('app_write_' || v_scope_prefix || '_burst', v_identifier, v_minute_limit, 60);
  perform public.enforce_rate_limit('app_write_' || v_scope_prefix || '_hourly', v_identifier, v_hour_limit, 3600);

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
exception
  when others then
    if sqlerrm = 'rate_limit_exceeded' then
      insert into public.security_events (
        scope,
        identifier,
        table_name,
        operation,
        reason,
        metadata
      )
      values (
        'write_rate_limit',
        coalesce(v_identifier, 'unknown'),
        tg_table_name,
        tg_op,
        'rate_limit_exceeded',
        jsonb_build_object(
          'user_id', v_user_id,
          'role', auth.role()
        )
      );
      raise exception 'rate_limit_exceeded';
    end if;
    raise;
end;
$$;

drop trigger if exists trg_land_groups_write_rate_limit on public.land_groups;
create trigger trg_land_groups_write_rate_limit
before insert or update or delete on public.land_groups
for each row execute function public.enforce_client_write_rate_limit();

drop trigger if exists trg_lands_write_rate_limit on public.lands;
create trigger trg_lands_write_rate_limit
before insert or update or delete on public.lands
for each row execute function public.enforce_client_write_rate_limit();

drop trigger if exists trg_land_history_write_rate_limit on public.land_history_entries;
create trigger trg_land_history_write_rate_limit
before insert or update or delete on public.land_history_entries
for each row execute function public.enforce_client_write_rate_limit();

drop trigger if exists trg_land_tasks_write_rate_limit on public.land_tasks;
create trigger trg_land_tasks_write_rate_limit
before insert or update or delete on public.land_tasks
for each row execute function public.enforce_client_write_rate_limit();

drop trigger if exists trg_push_devices_write_rate_limit on public.push_devices;
create trigger trg_push_devices_write_rate_limit
before insert or update or delete on public.push_devices
for each row execute function public.enforce_client_write_rate_limit();

drop trigger if exists trg_spreadsheet_sources_write_rate_limit on public.spreadsheet_sources;
create trigger trg_spreadsheet_sources_write_rate_limit
before insert or update or delete on public.spreadsheet_sources
for each row execute function public.enforce_client_write_rate_limit();

drop trigger if exists trg_org_members_write_rate_limit on public.organization_members;
create trigger trg_org_members_write_rate_limit
before insert or update or delete on public.organization_members
for each row execute function public.enforce_client_write_rate_limit();

drop trigger if exists trg_org_invitations_write_rate_limit on public.organization_invitations;
create trigger trg_org_invitations_write_rate_limit
before insert or update or delete on public.organization_invitations
for each row execute function public.enforce_client_write_rate_limit();

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'land_groups_name_length_check'
  ) then
    alter table public.land_groups
      add constraint land_groups_name_length_check
      check (char_length(name) between 1 and 120)
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'lands_name_length_check'
  ) then
    alter table public.lands
      add constraint lands_name_length_check
      check (char_length(name) between 1 and 160)
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'lands_notes_length_check'
  ) then
    alter table public.lands
      add constraint lands_notes_length_check
      check (char_length(notes) <= 4000)
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'land_history_notes_length_check'
  ) then
    alter table public.land_history_entries
      add constraint land_history_notes_length_check
      check (char_length(notes) <= 4000)
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'land_tasks_title_length_check'
  ) then
    alter table public.land_tasks
      add constraint land_tasks_title_length_check
      check (char_length(title) between 1 and 180)
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'land_tasks_notes_length_check'
  ) then
    alter table public.land_tasks
      add constraint land_tasks_notes_length_check
      check (char_length(notes) <= 4000)
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'org_invitations_email_length_check'
  ) then
    alter table public.organization_invitations
      add constraint org_invitations_email_length_check
      check (char_length(invited_email) between 3 and 320)
      not valid;
  end if;
end $$;

-- Optional: validate once you are sure current data passes.
-- alter table public.land_groups validate constraint land_groups_name_length_check;
-- alter table public.lands validate constraint lands_name_length_check;
-- alter table public.lands validate constraint lands_notes_length_check;
-- alter table public.land_history_entries validate constraint land_history_notes_length_check;
-- alter table public.land_tasks validate constraint land_tasks_title_length_check;
-- alter table public.land_tasks validate constraint land_tasks_notes_length_check;
-- alter table public.organization_invitations validate constraint org_invitations_email_length_check;

revoke all on table public.security_events from public;
revoke all on table public.security_events from anon;
revoke all on table public.security_events from authenticated;

revoke all on table public.worker_job_locks from public;
revoke all on table public.worker_job_locks from anon;
revoke all on table public.worker_job_locks from authenticated;

revoke all on function public.acquire_worker_job_lock(text, integer) from public;
grant execute on function public.acquire_worker_job_lock(text, integer) to service_role;

revoke all on function public.release_worker_job_lock(text, uuid) from public;
grant execute on function public.release_worker_job_lock(text, uuid) to service_role;

revoke all on function public.cleanup_security_telemetry(integer) from public;
grant execute on function public.cleanup_security_telemetry(integer) to service_role;

revoke all on function public.enforce_client_write_rate_limit() from public;
grant execute on function public.enforce_client_write_rate_limit() to authenticated, service_role;
