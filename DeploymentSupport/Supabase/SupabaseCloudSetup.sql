-- Run this in Supabase SQL Editor once for LandTracker cloud sync.

create extension if not exists "pgcrypto";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text,
  show_income_in_list boolean not null default true,
  show_subtype_in_list boolean not null default true,
  profile_photo_path text,
  updated_at timestamptz not null default now()
);

create table if not exists public.land_groups (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  color_hex text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lands (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  group_id uuid references public.land_groups (id) on delete set null,
  name text not null,
  latitude double precision not null,
  longitude double precision not null,
  size_acres double precision not null default 0,
  activity_type text not null default 'Agricultural Operation',
  production_type text not null,
  production_subtype text not null default '',
  income_annual double precision not null default 0,
  annual_irrigation_cost double precision not null default 0,
  annual_fertilizer_cost double precision not null default 0,
  annual_labor_cost double precision not null default 0,
  annual_maintenance_cost double precision not null default 0,
  notes text not null default '',
  installed_capacity_kw double precision not null default 0,
  annual_electricity_production_kwh double precision not null default 0,
  self_consumption_rate double precision not null default 0,
  grid_export_rate double precision not null default 0,
  catastro_refcat14 text,
  catastro_area_value double precision,
  catastro_area_uom text,
  catastro_label text,
  catastro_rings jsonb not null default '[]'::jsonb,
  catastro_fetched_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.land_history_entries (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  land_id uuid not null references public.lands (id) on delete cascade,
  year integer not null,
  month integer not null check (month between 1 and 12),
  income_amount double precision not null default 0,
  production_amount double precision not null default 0,
  production_unit text not null default 't',
  electricity_kwh double precision not null default 0,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.land_tasks (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  land_id uuid not null references public.lands (id) on delete cascade,
  type_raw text not null default 'other',
  title text not null,
  due_date timestamptz not null,
  reminder_date timestamptz,
  notes text not null default '',
  is_completed boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.push_devices (
  user_id uuid not null references auth.users (id) on delete cascade,
  device_token text not null,
  platform text not null default 'ios',
  bundle_id text not null default '',
  locale_identifier text not null default '',
  timezone_identifier text not null default '',
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, device_token)
);

create table if not exists public.land_task_push_deliveries (
  id bigserial primary key,
  task_id uuid not null references public.land_tasks (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  device_token text not null,
  reminder_date timestamptz not null,
  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (task_id, device_token, reminder_date)
);

create table if not exists public.spreadsheet_sources (
  user_id uuid primary key references auth.users (id) on delete cascade,
  file_name text not null,
  storage_path text not null,
  file_hash text not null,
  updated_at timestamptz not null default now()
);

create or replace function public.pending_land_task_push_notifications(limit_count integer default 200)
returns table (
  task_id uuid,
  user_id uuid,
  device_token text,
  task_title text,
  land_name text,
  due_date timestamptz,
  reminder_date timestamptz
)
language sql
as $$
  select
    t.id as task_id,
    t.user_id,
    d.device_token,
    t.title as task_title,
    l.name as land_name,
    t.due_date,
    t.reminder_date
  from public.land_tasks t
  join public.lands l
    on l.id = t.land_id
   and l.user_id = t.user_id
  join public.push_devices d
    on d.user_id = t.user_id
  left join public.land_task_push_deliveries delivered
    on delivered.task_id = t.id
   and delivered.device_token = d.device_token
   and delivered.reminder_date = t.reminder_date
  where t.reminder_date is not null
    and t.is_completed = false
    and t.reminder_date <= now()
    and delivered.id is null
  order by t.reminder_date asc
  limit greatest(limit_count, 1);
$$;

revoke all on function public.pending_land_task_push_notifications(integer) from public;
grant execute on function public.pending_land_task_push_notifications(integer) to service_role;

alter table public.lands add column if not exists activity_type text not null default 'Agricultural Operation';
alter table public.lands add column if not exists annual_irrigation_cost double precision not null default 0;
alter table public.lands add column if not exists annual_fertilizer_cost double precision not null default 0;
alter table public.lands add column if not exists annual_labor_cost double precision not null default 0;
alter table public.lands add column if not exists annual_maintenance_cost double precision not null default 0;
alter table public.lands add column if not exists installed_capacity_kw double precision not null default 0;
alter table public.lands add column if not exists annual_electricity_production_kwh double precision not null default 0;
alter table public.lands add column if not exists self_consumption_rate double precision not null default 0;
alter table public.lands add column if not exists grid_export_rate double precision not null default 0;
alter table public.land_tasks add column if not exists type_raw text not null default 'other';
alter table public.land_tasks add column if not exists reminder_date timestamptz;
alter table public.land_tasks add column if not exists notes text not null default '';
alter table public.land_tasks add column if not exists is_completed boolean not null default false;
alter table public.land_tasks add column if not exists completed_at timestamptz;
alter table public.push_devices add column if not exists platform text not null default 'ios';
alter table public.push_devices add column if not exists bundle_id text not null default '';
alter table public.push_devices add column if not exists locale_identifier text not null default '';
alter table public.push_devices add column if not exists timezone_identifier text not null default '';
alter table public.push_devices add column if not exists last_seen_at timestamptz not null default now();

create index if not exists idx_land_groups_user_id on public.land_groups (user_id);
create index if not exists idx_lands_user_id on public.lands (user_id);
create index if not exists idx_lands_group_id on public.lands (group_id);
create index if not exists idx_land_history_user_id on public.land_history_entries (user_id);
create index if not exists idx_land_history_land_id on public.land_history_entries (land_id);
create unique index if not exists idx_land_history_land_period_unique on public.land_history_entries (land_id, year, month);
create index if not exists idx_land_tasks_user_id on public.land_tasks (user_id);
create index if not exists idx_land_tasks_land_id on public.land_tasks (land_id);
create index if not exists idx_land_tasks_due_date on public.land_tasks (due_date);
create index if not exists idx_push_devices_user_id on public.push_devices (user_id);
create index if not exists idx_task_push_deliveries_task_id on public.land_task_push_deliveries (task_id);
create index if not exists idx_task_push_deliveries_user_id on public.land_task_push_deliveries (user_id);
create index if not exists idx_task_push_deliveries_sent_at on public.land_task_push_deliveries (sent_at desc);
create index if not exists idx_spreadsheet_sources_updated_at on public.spreadsheet_sources (updated_at desc);

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists trg_land_groups_updated_at on public.land_groups;
create trigger trg_land_groups_updated_at
before update on public.land_groups
for each row execute function public.set_updated_at();

drop trigger if exists trg_lands_updated_at on public.lands;
create trigger trg_lands_updated_at
before update on public.lands
for each row execute function public.set_updated_at();

drop trigger if exists trg_land_history_updated_at on public.land_history_entries;
create trigger trg_land_history_updated_at
before update on public.land_history_entries
for each row execute function public.set_updated_at();

drop trigger if exists trg_land_tasks_updated_at on public.land_tasks;
create trigger trg_land_tasks_updated_at
before update on public.land_tasks
for each row execute function public.set_updated_at();

drop trigger if exists trg_push_devices_updated_at on public.push_devices;
create trigger trg_push_devices_updated_at
before update on public.push_devices
for each row execute function public.set_updated_at();

drop trigger if exists trg_spreadsheet_sources_updated_at on public.spreadsheet_sources;
create trigger trg_spreadsheet_sources_updated_at
before update on public.spreadsheet_sources
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.land_groups enable row level security;
alter table public.lands enable row level security;
alter table public.land_history_entries enable row level security;
alter table public.land_tasks enable row level security;
alter table public.push_devices enable row level security;
alter table public.land_task_push_deliveries enable row level security;
alter table public.spreadsheet_sources enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
on public.profiles for select
using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
on public.profiles for insert
with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles for update
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists "profiles_delete_own" on public.profiles;
create policy "profiles_delete_own"
on public.profiles for delete
using (auth.uid() = id);

drop policy if exists "land_groups_select_own" on public.land_groups;
create policy "land_groups_select_own"
on public.land_groups for select
using (auth.uid() = user_id);

drop policy if exists "land_groups_insert_own" on public.land_groups;
create policy "land_groups_insert_own"
on public.land_groups for insert
with check (auth.uid() = user_id);

drop policy if exists "land_groups_update_own" on public.land_groups;
create policy "land_groups_update_own"
on public.land_groups for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "land_groups_delete_own" on public.land_groups;
create policy "land_groups_delete_own"
on public.land_groups for delete
using (auth.uid() = user_id);

drop policy if exists "lands_select_own" on public.lands;
create policy "lands_select_own"
on public.lands for select
using (auth.uid() = user_id);

drop policy if exists "lands_insert_own" on public.lands;
create policy "lands_insert_own"
on public.lands for insert
with check (auth.uid() = user_id);

drop policy if exists "lands_update_own" on public.lands;
create policy "lands_update_own"
on public.lands for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "lands_delete_own" on public.lands;
create policy "lands_delete_own"
on public.lands for delete
using (auth.uid() = user_id);

drop policy if exists "land_history_select_own" on public.land_history_entries;
create policy "land_history_select_own"
on public.land_history_entries for select
using (auth.uid() = user_id);

drop policy if exists "land_history_insert_own" on public.land_history_entries;
create policy "land_history_insert_own"
on public.land_history_entries for insert
with check (auth.uid() = user_id);

drop policy if exists "land_history_update_own" on public.land_history_entries;
create policy "land_history_update_own"
on public.land_history_entries for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "land_history_delete_own" on public.land_history_entries;
create policy "land_history_delete_own"
on public.land_history_entries for delete
using (auth.uid() = user_id);

drop policy if exists "land_tasks_select_own" on public.land_tasks;
create policy "land_tasks_select_own"
on public.land_tasks for select
using (auth.uid() = user_id);

drop policy if exists "land_tasks_insert_own" on public.land_tasks;
create policy "land_tasks_insert_own"
on public.land_tasks for insert
with check (auth.uid() = user_id);

drop policy if exists "land_tasks_update_own" on public.land_tasks;
create policy "land_tasks_update_own"
on public.land_tasks for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "land_tasks_delete_own" on public.land_tasks;
create policy "land_tasks_delete_own"
on public.land_tasks for delete
using (auth.uid() = user_id);

drop policy if exists "push_devices_select_own" on public.push_devices;
create policy "push_devices_select_own"
on public.push_devices for select
using (auth.uid() = user_id);

drop policy if exists "push_devices_insert_own" on public.push_devices;
create policy "push_devices_insert_own"
on public.push_devices for insert
with check (auth.uid() = user_id);

drop policy if exists "push_devices_update_own" on public.push_devices;
create policy "push_devices_update_own"
on public.push_devices for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "push_devices_delete_own" on public.push_devices;
create policy "push_devices_delete_own"
on public.push_devices for delete
using (auth.uid() = user_id);

drop policy if exists "land_task_push_deliveries_select_own" on public.land_task_push_deliveries;
create policy "land_task_push_deliveries_select_own"
on public.land_task_push_deliveries for select
using (auth.uid() = user_id);

drop policy if exists "spreadsheet_sources_select_own" on public.spreadsheet_sources;
create policy "spreadsheet_sources_select_own"
on public.spreadsheet_sources for select
using (auth.uid() = user_id);

drop policy if exists "spreadsheet_sources_insert_own" on public.spreadsheet_sources;
create policy "spreadsheet_sources_insert_own"
on public.spreadsheet_sources for insert
with check (auth.uid() = user_id);

drop policy if exists "spreadsheet_sources_update_own" on public.spreadsheet_sources;
create policy "spreadsheet_sources_update_own"
on public.spreadsheet_sources for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "spreadsheet_sources_delete_own" on public.spreadsheet_sources;
create policy "spreadsheet_sources_delete_own"
on public.spreadsheet_sources for delete
using (auth.uid() = user_id);

insert into storage.buckets (id, name, public)
values ('profile-images', 'profile-images', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('spreadsheet-files', 'spreadsheet-files', false)
on conflict (id) do nothing;

drop policy if exists "profile_images_select_own" on storage.objects;
create policy "profile_images_select_own"
on storage.objects for select
using (
  bucket_id = 'profile-images'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "profile_images_insert_own" on storage.objects;
create policy "profile_images_insert_own"
on storage.objects for insert
with check (
  bucket_id = 'profile-images'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "profile_images_update_own" on storage.objects;
create policy "profile_images_update_own"
on storage.objects for update
using (
  bucket_id = 'profile-images'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'profile-images'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "profile_images_delete_own" on storage.objects;
create policy "profile_images_delete_own"
on storage.objects for delete
using (
  bucket_id = 'profile-images'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "spreadsheet_files_select_own" on storage.objects;
create policy "spreadsheet_files_select_own"
on storage.objects for select
using (
  bucket_id = 'spreadsheet-files'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "spreadsheet_files_insert_own" on storage.objects;
create policy "spreadsheet_files_insert_own"
on storage.objects for insert
with check (
  bucket_id = 'spreadsheet-files'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "spreadsheet_files_update_own" on storage.objects;
create policy "spreadsheet_files_update_own"
on storage.objects for update
using (
  bucket_id = 'spreadsheet-files'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'spreadsheet-files'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "spreadsheet_files_delete_own" on storage.objects;
create policy "spreadsheet_files_delete_own"
on storage.objects for delete
using (
  bucket_id = 'spreadsheet-files'
  and auth.uid()::text = (storage.foldername(name))[1]
);
