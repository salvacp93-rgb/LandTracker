-- Run this AFTER SupabaseUserManagementSetup.sql.
-- Purpose: IoT foundation for real-time field devices in LandTracker.
-- Includes:
-- 1) Device registry per land (iot_devices)
-- 2) Time-series telemetry (iot_device_telemetry)
-- 3) Remote command queue (iot_device_commands)
-- 4) RLS + org role checks + helper RPCs for app ingestion

create extension if not exists "pgcrypto";

create table if not exists public.iot_devices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  land_id uuid not null references public.lands (id) on delete cascade,
  name text not null,
  type_raw text not null default 'other',
  manufacturer text not null default '',
  model text not null default '',
  serial_number text not null default '',
  metric_name text not null default '',
  metric_unit text not null default '',
  notes text not null default '',
  is_active boolean not null default true,
  installed_at timestamptz,
  last_seen_at timestamptz,
  last_metric_name text,
  last_metric_unit text,
  last_reading_value double precision,
  last_battery_level double precision,
  metadata jsonb not null default '{}'::jsonb,
  created_by_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.iot_device_telemetry (
  id bigserial primary key,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  land_id uuid not null references public.lands (id) on delete cascade,
  device_id uuid not null references public.iot_devices (id) on delete cascade,
  observed_at timestamptz not null default now(),
  metric_name text not null default '',
  metric_unit text not null default '',
  value_double double precision,
  value_text text,
  battery_level double precision,
  status_raw text not null default '',
  source_raw text not null default 'manual',
  payload jsonb not null default '{}'::jsonb,
  created_by_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.iot_device_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  land_id uuid not null references public.lands (id) on delete cascade,
  device_id uuid not null references public.iot_devices (id) on delete cascade,
  command_type text not null,
  command_payload jsonb not null default '{}'::jsonb,
  command_state text not null default 'pending',
  requested_by_user_id uuid references auth.users (id) on delete set null,
  requested_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  ack_payload jsonb,
  error_text text,
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'iot_device_telemetry_battery_range_check'
  ) then
    alter table public.iot_device_telemetry
      add constraint iot_device_telemetry_battery_range_check
      check (battery_level is null or (battery_level >= 0 and battery_level <= 100));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'iot_devices_last_battery_range_check'
  ) then
    alter table public.iot_devices
      add constraint iot_devices_last_battery_range_check
      check (last_battery_level is null or (last_battery_level >= 0 and last_battery_level <= 100));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'iot_device_commands_state_check'
  ) then
    alter table public.iot_device_commands
      add constraint iot_device_commands_state_check
      check (command_state in ('pending', 'sent', 'acknowledged', 'failed', 'canceled'));
  end if;
end $$;

create index if not exists idx_iot_devices_organization_id
  on public.iot_devices (organization_id);
create index if not exists idx_iot_devices_land_id
  on public.iot_devices (land_id);
create unique index if not exists idx_iot_devices_land_serial_unique
  on public.iot_devices (land_id, serial_number)
  where serial_number <> '';
create index if not exists idx_iot_devices_last_seen_at
  on public.iot_devices (last_seen_at desc);

create index if not exists idx_iot_telemetry_organization_observed
  on public.iot_device_telemetry (organization_id, observed_at desc);
create index if not exists idx_iot_telemetry_land_observed
  on public.iot_device_telemetry (land_id, observed_at desc);
create index if not exists idx_iot_telemetry_device_observed
  on public.iot_device_telemetry (device_id, observed_at desc);

create index if not exists idx_iot_commands_organization_requested
  on public.iot_device_commands (organization_id, requested_at desc);
create index if not exists idx_iot_commands_device_requested
  on public.iot_device_commands (device_id, requested_at desc);
create index if not exists idx_iot_commands_state_requested
  on public.iot_device_commands (command_state, requested_at asc);

create or replace function public.iot_assign_device_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
begin
  if new.land_id is null then
    raise exception 'land_id is required';
  end if;

  select l.organization_id
    into v_organization_id
  from public.lands l
  where l.id = new.land_id;

  if v_organization_id is null then
    raise exception 'land not found for IoT device';
  end if;

  new.organization_id := v_organization_id;
  return new;
end;
$$;

create or replace function public.iot_assign_scope_from_device()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_land_id uuid;
  v_organization_id uuid;
begin
  if new.device_id is null then
    raise exception 'device_id is required';
  end if;

  select d.land_id, d.organization_id
    into v_land_id, v_organization_id
  from public.iot_devices d
  where d.id = new.device_id;

  if v_land_id is null or v_organization_id is null then
    raise exception 'iot device not found';
  end if;

  new.land_id := v_land_id;
  new.organization_id := v_organization_id;
  return new;
end;
$$;

drop trigger if exists trg_iot_devices_updated_at on public.iot_devices;
create trigger trg_iot_devices_updated_at
before update on public.iot_devices
for each row execute function public.set_updated_at();

drop trigger if exists trg_iot_device_commands_updated_at on public.iot_device_commands;
create trigger trg_iot_device_commands_updated_at
before update on public.iot_device_commands
for each row execute function public.set_updated_at();

drop trigger if exists trg_iot_devices_assign_scope on public.iot_devices;
create trigger trg_iot_devices_assign_scope
before insert or update on public.iot_devices
for each row execute function public.iot_assign_device_scope();

drop trigger if exists trg_iot_telemetry_assign_scope on public.iot_device_telemetry;
create trigger trg_iot_telemetry_assign_scope
before insert or update on public.iot_device_telemetry
for each row execute function public.iot_assign_scope_from_device();

drop trigger if exists trg_iot_commands_assign_scope on public.iot_device_commands;
create trigger trg_iot_commands_assign_scope
before insert or update on public.iot_device_commands
for each row execute function public.iot_assign_scope_from_device();

create or replace function public.register_iot_device(
  p_land_id uuid,
  p_device_id uuid default null,
  p_name text default '',
  p_type_raw text default 'other',
  p_manufacturer text default '',
  p_model text default '',
  p_serial_number text default '',
  p_metric_name text default '',
  p_metric_unit text default '',
  p_installed_at timestamptz default null,
  p_is_active boolean default true,
  p_notes text default '',
  p_metadata_text text default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
  v_device_id uuid;
  v_name text;
  v_metadata jsonb;
begin
  if p_land_id is null then
    raise exception 'land_id is required';
  end if;

  select l.organization_id
    into v_organization_id
  from public.lands l
  where l.id = p_land_id;

  if v_organization_id is null then
    raise exception 'land not found';
  end if;

  if auth.role() = 'authenticated'
     and not public.has_organization_role(v_organization_id, 'member') then
    raise exception 'no permission to register IoT devices in this organization';
  end if;

  v_name := btrim(coalesce(p_name, ''));
  if v_name = '' then
    raise exception 'device name is required';
  end if;

  if btrim(coalesce(p_metadata_text, '')) = '' then
    v_metadata := '{}'::jsonb;
  else
    begin
      v_metadata := p_metadata_text::jsonb;
    exception
      when others then
        raise exception 'invalid metadata json';
    end;
  end if;

  v_device_id := coalesce(p_device_id, gen_random_uuid());

  insert into public.iot_devices (
    id,
    organization_id,
    land_id,
    name,
    type_raw,
    manufacturer,
    model,
    serial_number,
    metric_name,
    metric_unit,
    notes,
    is_active,
    installed_at,
    metadata,
    created_by_user_id,
    created_at,
    updated_at
  )
  values (
    v_device_id,
    v_organization_id,
    p_land_id,
    v_name,
    lower(btrim(coalesce(p_type_raw, 'other'))),
    btrim(coalesce(p_manufacturer, '')),
    btrim(coalesce(p_model, '')),
    btrim(coalesce(p_serial_number, '')),
    btrim(coalesce(p_metric_name, '')),
    btrim(coalesce(p_metric_unit, '')),
    btrim(coalesce(p_notes, '')),
    coalesce(p_is_active, true),
    p_installed_at,
    v_metadata,
    auth.uid(),
    now(),
    now()
  )
  on conflict (id) do update
    set land_id = excluded.land_id,
        organization_id = excluded.organization_id,
        name = excluded.name,
        type_raw = excluded.type_raw,
        manufacturer = excluded.manufacturer,
        model = excluded.model,
        serial_number = excluded.serial_number,
        metric_name = excluded.metric_name,
        metric_unit = excluded.metric_unit,
        notes = excluded.notes,
        is_active = excluded.is_active,
        installed_at = excluded.installed_at,
        metadata = excluded.metadata,
        updated_at = now()
  where public.iot_devices.organization_id = excluded.organization_id;

  return v_device_id;
end;
$$;

create or replace function public.append_iot_telemetry(
  p_device_id uuid,
  p_observed_at timestamptz default now(),
  p_metric_name text default null,
  p_metric_unit text default null,
  p_value_double double precision default null,
  p_value_text text default null,
  p_battery_level double precision default null,
  p_status_raw text default null,
  p_source_raw text default 'manual',
  p_payload_text text default '{}'
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_land_id uuid;
  v_organization_id uuid;
  v_default_metric_name text;
  v_default_metric_unit text;
  v_metric_name text;
  v_metric_unit text;
  v_payload jsonb;
  v_battery_level double precision;
  v_row_id bigint;
begin
  if p_device_id is null then
    raise exception 'device_id is required';
  end if;

  select
    d.land_id,
    d.organization_id,
    d.metric_name,
    d.metric_unit
    into
      v_land_id,
      v_organization_id,
      v_default_metric_name,
      v_default_metric_unit
  from public.iot_devices d
  where d.id = p_device_id;

  if v_land_id is null or v_organization_id is null then
    raise exception 'iot device not found';
  end if;

  if auth.role() = 'authenticated'
     and not public.has_organization_role(v_organization_id, 'member') then
    raise exception 'no permission to append telemetry for this device';
  end if;

  if btrim(coalesce(p_payload_text, '')) = '' then
    v_payload := '{}'::jsonb;
  else
    begin
      v_payload := p_payload_text::jsonb;
    exception
      when others then
        raise exception 'invalid payload json';
    end;
  end if;

  v_metric_name := coalesce(
    nullif(btrim(coalesce(p_metric_name, '')), ''),
    nullif(btrim(coalesce(v_default_metric_name, '')), ''),
    ''
  );
  v_metric_unit := coalesce(
    nullif(btrim(coalesce(p_metric_unit, '')), ''),
    nullif(btrim(coalesce(v_default_metric_unit, '')), ''),
    ''
  );
  v_battery_level := case
    when p_battery_level is null then null
    else greatest(0, least(100, p_battery_level))
  end;

  insert into public.iot_device_telemetry (
    organization_id,
    land_id,
    device_id,
    observed_at,
    metric_name,
    metric_unit,
    value_double,
    value_text,
    battery_level,
    status_raw,
    source_raw,
    payload,
    created_by_user_id,
    created_at
  )
  values (
    v_organization_id,
    v_land_id,
    p_device_id,
    coalesce(p_observed_at, now()),
    v_metric_name,
    v_metric_unit,
    p_value_double,
    nullif(btrim(coalesce(p_value_text, '')), ''),
    v_battery_level,
    btrim(coalesce(p_status_raw, '')),
    coalesce(nullif(btrim(coalesce(p_source_raw, '')), ''), 'manual'),
    v_payload,
    auth.uid(),
    now()
  )
  returning id into v_row_id;

  update public.iot_devices
  set
    last_seen_at = greatest(coalesce(last_seen_at, coalesce(p_observed_at, now())), coalesce(p_observed_at, now())),
    last_metric_name = case
      when v_metric_name <> '' then v_metric_name
      else last_metric_name
    end,
    last_metric_unit = case
      when v_metric_unit <> '' then v_metric_unit
      else last_metric_unit
    end,
    last_reading_value = coalesce(p_value_double, last_reading_value),
    last_battery_level = coalesce(v_battery_level, last_battery_level),
    updated_at = now()
  where id = p_device_id;

  return v_row_id;
end;
$$;

create or replace function public.enqueue_iot_device_command(
  p_device_id uuid,
  p_command_type text,
  p_command_payload_text text default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_land_id uuid;
  v_organization_id uuid;
  v_command_id uuid;
  v_command_type text;
  v_payload jsonb;
begin
  if p_device_id is null then
    raise exception 'device_id is required';
  end if;

  select d.land_id, d.organization_id
    into v_land_id, v_organization_id
  from public.iot_devices d
  where d.id = p_device_id;

  if v_land_id is null or v_organization_id is null then
    raise exception 'iot device not found';
  end if;

  if auth.role() = 'authenticated'
     and not public.has_organization_role(v_organization_id, 'member') then
    raise exception 'no permission to enqueue commands for this device';
  end if;

  v_command_type := lower(btrim(coalesce(p_command_type, '')));
  if v_command_type = '' then
    raise exception 'command_type is required';
  end if;

  if btrim(coalesce(p_command_payload_text, '')) = '' then
    v_payload := '{}'::jsonb;
  else
    begin
      v_payload := p_command_payload_text::jsonb;
    exception
      when others then
        raise exception 'invalid command payload json';
    end;
  end if;

  insert into public.iot_device_commands (
    organization_id,
    land_id,
    device_id,
    command_type,
    command_payload,
    command_state,
    requested_by_user_id,
    requested_at,
    updated_at
  )
  values (
    v_organization_id,
    v_land_id,
    p_device_id,
    v_command_type,
    v_payload,
    'pending',
    auth.uid(),
    now(),
    now()
  )
  returning id into v_command_id;

  return v_command_id;
end;
$$;

alter table public.iot_devices enable row level security;
alter table public.iot_device_telemetry enable row level security;
alter table public.iot_device_commands enable row level security;

drop policy if exists "iot_devices_select_org_member" on public.iot_devices;
create policy "iot_devices_select_org_member"
on public.iot_devices for select
using (organization_id is not null and public.has_organization_role(organization_id, 'viewer'));

drop policy if exists "iot_devices_insert_org_member" on public.iot_devices;
create policy "iot_devices_insert_org_member"
on public.iot_devices for insert
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "iot_devices_update_org_member" on public.iot_devices;
create policy "iot_devices_update_org_member"
on public.iot_devices for update
using (organization_id is not null and public.has_organization_role(organization_id, 'member'))
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "iot_devices_delete_org_member" on public.iot_devices;
create policy "iot_devices_delete_org_member"
on public.iot_devices for delete
using (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "iot_telemetry_select_org_member" on public.iot_device_telemetry;
create policy "iot_telemetry_select_org_member"
on public.iot_device_telemetry for select
using (organization_id is not null and public.has_organization_role(organization_id, 'viewer'));

drop policy if exists "iot_telemetry_insert_org_member" on public.iot_device_telemetry;
create policy "iot_telemetry_insert_org_member"
on public.iot_device_telemetry for insert
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "iot_telemetry_update_org_member" on public.iot_device_telemetry;
create policy "iot_telemetry_update_org_member"
on public.iot_device_telemetry for update
using (organization_id is not null and public.has_organization_role(organization_id, 'member'))
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "iot_commands_select_org_member" on public.iot_device_commands;
create policy "iot_commands_select_org_member"
on public.iot_device_commands for select
using (organization_id is not null and public.has_organization_role(organization_id, 'viewer'));

drop policy if exists "iot_commands_insert_org_member" on public.iot_device_commands;
create policy "iot_commands_insert_org_member"
on public.iot_device_commands for insert
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "iot_commands_update_org_member" on public.iot_device_commands;
create policy "iot_commands_update_org_member"
on public.iot_device_commands for update
using (organization_id is not null and public.has_organization_role(organization_id, 'member'))
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "iot_commands_delete_org_member" on public.iot_device_commands;
create policy "iot_commands_delete_org_member"
on public.iot_device_commands for delete
using (organization_id is not null and public.has_organization_role(organization_id, 'member'));

alter table public.iot_devices force row level security;
alter table public.iot_device_telemetry force row level security;
alter table public.iot_device_commands force row level security;

revoke all on function public.iot_assign_device_scope() from public;
grant execute on function public.iot_assign_device_scope() to authenticated, service_role;

revoke all on function public.iot_assign_scope_from_device() from public;
grant execute on function public.iot_assign_scope_from_device() to authenticated, service_role;

revoke all on function public.register_iot_device(
  uuid, uuid, text, text, text, text, text, text, text, timestamptz, boolean, text, text
) from public;
grant execute on function public.register_iot_device(
  uuid, uuid, text, text, text, text, text, text, text, timestamptz, boolean, text, text
) to authenticated, service_role;

revoke all on function public.append_iot_telemetry(
  uuid, timestamptz, text, text, double precision, text, double precision, text, text, text
) from public;
grant execute on function public.append_iot_telemetry(
  uuid, timestamptz, text, text, double precision, text, double precision, text, text, text
) to authenticated, service_role;

revoke all on function public.enqueue_iot_device_command(uuid, text, text) from public;
grant execute on function public.enqueue_iot_device_command(uuid, text, text) to authenticated, service_role;
