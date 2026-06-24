-- Run this AFTER SupabaseCloudSetup.sql.
-- Goal: production-ready user model for startup growth.
-- Adds:
-- 1) organizations + organization_members
-- 2) account lifecycle states in profiles
-- 3) personal workspace bootstrap for each auth user
-- 4) organization_id columns and org-based RLS policies (without deleting your current user_id policies)

create extension if not exists "pgcrypto";

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  is_personal boolean not null default false,
  billing_state text not null default 'trialing',
  plan_code text not null default 'free',
  trial_ends_at timestamptz,
  current_period_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.organization_members (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member',
  member_state text not null default 'active',
  invited_email text,
  invited_by_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create table if not exists public.organization_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  invited_email text not null,
  role text not null default 'member',
  state text not null default 'pending',
  invited_by_user_id uuid not null references auth.users (id) on delete cascade,
  invited_at timestamptz not null default now(),
  accepted_at timestamptz,
  expires_at timestamptz not null default (now() + interval '14 days'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, invited_email)
);

create index if not exists idx_organizations_owner_user_id on public.organizations (owner_user_id);
create index if not exists idx_organizations_billing_state on public.organizations (billing_state);
create index if not exists idx_org_members_user_id on public.organization_members (user_id);
create index if not exists idx_org_members_role on public.organization_members (role);
create index if not exists idx_org_members_member_state on public.organization_members (member_state);
create index if not exists idx_org_invitations_org_id on public.organization_invitations (organization_id);
create index if not exists idx_org_invitations_email on public.organization_invitations (invited_email);
create index if not exists idx_org_invitations_state on public.organization_invitations (state);

do $$
begin
  if not exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'idx_organizations_one_personal_per_owner'
  ) then
    if exists (
      select 1
      from public.organizations
      where is_personal = true
      group by owner_user_id
      having count(*) > 1
    ) then
      raise notice 'Skipped unique personal-workspace index; duplicate personal organizations already exist.';
    else
      execute 'create unique index idx_organizations_one_personal_per_owner on public.organizations (owner_user_id) where is_personal = true';
    end if;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'organizations_billing_state_check'
  ) then
    alter table public.organizations
      add constraint organizations_billing_state_check
      check (billing_state in ('trialing', 'active', 'past_due', 'canceled', 'suspended'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'organization_members_role_check'
  ) then
    alter table public.organization_members
      add constraint organization_members_role_check
      check (role in ('owner', 'admin', 'member', 'viewer'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'organization_members_member_state_check'
  ) then
    alter table public.organization_members
      add constraint organization_members_member_state_check
      check (member_state in ('invited', 'active', 'suspended', 'left'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'organization_invitations_role_check'
  ) then
    alter table public.organization_invitations
      add constraint organization_invitations_role_check
      check (role in ('admin', 'member', 'viewer'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'organization_invitations_state_check'
  ) then
    alter table public.organization_invitations
      add constraint organization_invitations_state_check
      check (state in ('pending', 'accepted', 'revoked', 'expired'));
  end if;
end $$;

drop trigger if exists trg_organizations_updated_at on public.organizations;
create trigger trg_organizations_updated_at
before update on public.organizations
for each row execute function public.set_updated_at();

drop trigger if exists trg_organization_members_updated_at on public.organization_members;
create trigger trg_organization_members_updated_at
before update on public.organization_members
for each row execute function public.set_updated_at();

drop trigger if exists trg_organization_invitations_updated_at on public.organization_invitations;
create trigger trg_organization_invitations_updated_at
before update on public.organization_invitations
for each row execute function public.set_updated_at();

create or replace function public.prevent_organization_owner_user_change()
returns trigger
language plpgsql
as $$
begin
  if new.owner_user_id <> old.owner_user_id then
    raise exception 'owner_user_id cannot be changed once organization is created';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_organizations_owner_user_immutable on public.organizations;
create trigger trg_organizations_owner_user_immutable
before update on public.organizations
for each row execute function public.prevent_organization_owner_user_change();

create or replace function public.organization_role_rank(role_value text)
returns integer
language sql
immutable
as $$
  select case role_value
    when 'owner' then 400
    when 'admin' then 300
    when 'member' then 200
    when 'viewer' then 100
    else 0
  end;
$$;

create or replace function public.has_organization_role(
  p_organization_id uuid,
  p_min_role text default 'viewer'
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.member_state = 'active'
      and public.organization_role_rank(m.role) >= public.organization_role_rank(p_min_role)
  );
$$;

create or replace function public.is_organization_member(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_organization_role(p_organization_id, 'viewer');
$$;

create or replace function public.current_personal_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select o.id
  from public.organizations o
  where o.owner_user_id = auth.uid()
    and o.is_personal = true
  order by o.created_at asc
  limit 1;
$$;

create or replace function public.normalize_organization_invitation_email()
returns trigger
language plpgsql
as $$
begin
  new.invited_email := lower(btrim(coalesce(new.invited_email, '')));
  if new.invited_email = '' then
    raise exception 'invited_email cannot be empty';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_organization_invitations_normalize_email on public.organization_invitations;
create trigger trg_organization_invitations_normalize_email
before insert or update on public.organization_invitations
for each row execute function public.normalize_organization_invitation_email();

create or replace function public.apply_organization_invitation_if_user_exists()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid;
begin
  if new.state <> 'pending' then
    return new;
  end if;

  select u.id
    into v_user_id
  from auth.users u
  where lower(coalesce(u.email, '')) = new.invited_email
  order by u.created_at asc
  limit 1;

  if v_user_id is null then
    return new;
  end if;

  insert into public.organization_members (
    organization_id,
    user_id,
    role,
    member_state,
    invited_email,
    invited_by_user_id
  )
  values (
    new.organization_id,
    v_user_id,
    new.role,
    'active',
    new.invited_email,
    new.invited_by_user_id
  )
  on conflict (organization_id, user_id) do update
    set role = excluded.role,
        member_state = 'active',
        invited_email = excluded.invited_email,
        invited_by_user_id = excluded.invited_by_user_id,
        updated_at = now();

  update public.organization_invitations
  set state = 'accepted',
      accepted_at = coalesce(accepted_at, now()),
      updated_at = now()
  where id = new.id;

  return new;
end;
$$;

drop trigger if exists trg_organization_invitations_apply_existing_user on public.organization_invitations;
create trigger trg_organization_invitations_apply_existing_user
after insert or update of invited_email, role, state on public.organization_invitations
for each row execute function public.apply_organization_invitation_if_user_exists();

create or replace function public.apply_pending_invitations_for_user(
  p_user_id uuid,
  p_email text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  v_email := lower(btrim(coalesce(p_email, '')));
  if v_email = '' then
    return;
  end if;

  insert into public.organization_members (
    organization_id,
    user_id,
    role,
    member_state,
    invited_email,
    invited_by_user_id
  )
  select
    i.organization_id,
    p_user_id,
    i.role,
    'active',
    i.invited_email,
    i.invited_by_user_id
  from public.organization_invitations i
  where i.invited_email = v_email
    and i.state = 'pending'
    and i.expires_at > now()
  on conflict (organization_id, user_id) do update
    set role = excluded.role,
        member_state = 'active',
        invited_email = excluded.invited_email,
        invited_by_user_id = excluded.invited_by_user_id,
        updated_at = now();

  update public.organization_invitations
  set state = 'accepted',
      accepted_at = coalesce(accepted_at, now()),
      updated_at = now()
  where invited_email = v_email
    and state = 'pending'
    and expires_at > now();

  update public.organization_invitations
  set state = 'expired',
      updated_at = now()
  where invited_email = v_email
    and state = 'pending'
    and expires_at <= now();
end;
$$;

create table if not exists public.security_rate_limits (
  scope text not null,
  identifier text not null,
  window_starts_at timestamptz not null,
  hit_count integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (scope, identifier, window_starts_at)
);

create index if not exists idx_security_rate_limits_updated_at
  on public.security_rate_limits (updated_at desc);

create or replace function public.request_client_identifier()
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_headers_raw text;
  v_headers jsonb;
  v_ip text;
  v_sub text;
begin
  v_headers_raw := current_setting('request.headers', true);
  if v_headers_raw is not null and btrim(v_headers_raw) <> '' then
    v_headers := v_headers_raw::jsonb;
    v_ip := nullif(split_part(coalesce(v_headers ->> 'x-forwarded-for', v_headers ->> 'x-real-ip', ''), ',', 1), '');
  end if;

  v_sub := nullif(current_setting('request.jwt.claim.sub', true), '');
  if v_sub is not null then
    return 'user:' || v_sub;
  end if;

  if v_ip is not null then
    return 'ip:' || btrim(v_ip);
  end if;

  return 'unknown';
end;
$$;

create or replace function public.enforce_rate_limit(
  p_scope text,
  p_identifier text,
  p_max_hits integer,
  p_window_seconds integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scope text;
  v_identifier text;
  v_window integer;
  v_max integer;
  v_window_start timestamptz;
  v_hits integer;
begin
  v_scope := lower(btrim(coalesce(p_scope, '')));
  if v_scope = '' then
    raise exception 'rate limit scope is required';
  end if;

  v_identifier := btrim(coalesce(p_identifier, ''));
  if v_identifier = '' then
    v_identifier := 'unknown';
  end if;

  v_window := greatest(coalesce(p_window_seconds, 60), 1);
  v_max := greatest(coalesce(p_max_hits, 1), 1);
  v_window_start := to_timestamp(floor(extract(epoch from now()) / v_window) * v_window);

  insert into public.security_rate_limits (
    scope,
    identifier,
    window_starts_at,
    hit_count,
    updated_at
  )
  values (
    v_scope,
    v_identifier,
    v_window_start,
    1,
    now()
  )
  on conflict (scope, identifier, window_starts_at) do update
    set hit_count = public.security_rate_limits.hit_count + 1,
        updated_at = now()
  returning hit_count into v_hits;

  if v_hits > v_max then
    raise exception 'rate_limit_exceeded';
  end if;

  delete from public.security_rate_limits
  where updated_at < now() - interval '2 days';
end;
$$;

create or replace function public.invite_organization_employee(
  p_organization_id uuid,
  p_invited_email text,
  p_role text default 'member'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_role text;
  v_id uuid;
  v_identifier text;
begin
  if p_organization_id is null then
    raise exception 'organization_id is required';
  end if;

  v_email := lower(btrim(coalesce(p_invited_email, '')));
  if v_email = '' then
    raise exception 'email is required';
  end if;

  v_role := lower(btrim(coalesce(p_role, 'member')));
  if v_role not in ('admin', 'member', 'viewer') then
    raise exception 'invalid role';
  end if;

  if not public.has_organization_role(p_organization_id, 'owner') then
    raise exception 'only organization owner can invite employees';
  end if;

  v_identifier := coalesce(auth.uid()::text, public.request_client_identifier(), 'unknown');
  perform public.enforce_rate_limit('invite_employee_burst', v_identifier, 8, 60);
  perform public.enforce_rate_limit('invite_employee_hourly', v_identifier, 80, 3600);

  insert into public.organization_invitations (
    organization_id,
    invited_email,
    role,
    state,
    invited_by_user_id,
    invited_at,
    accepted_at,
    expires_at
  )
  values (
    p_organization_id,
    v_email,
    v_role,
    'pending',
    auth.uid(),
    now(),
    null,
    now() + interval '14 days'
  )
  on conflict (organization_id, invited_email) do update
    set role = excluded.role,
        state = 'pending',
        invited_by_user_id = excluded.invited_by_user_id,
        invited_at = now(),
        accepted_at = null,
        expires_at = excluded.expires_at,
        updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.can_register_employee(p_email text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_identifier text;
  v_exists boolean;
begin
  v_email := lower(btrim(coalesce(p_email, '')));
  if v_email = '' then
    return false;
  end if;

  v_identifier := coalesce(public.request_client_identifier(), 'unknown');
  perform public.enforce_rate_limit('can_register_employee_burst', v_identifier, 25, 60);
  perform public.enforce_rate_limit('can_register_employee_hourly', v_identifier, 600, 3600);

  select exists (
    select 1
    from public.organization_invitations i
    where i.invited_email = v_email
      and i.state = 'pending'
      and i.expires_at > now()
  )
  into v_exists;

  return coalesce(v_exists, false);
end;
$$;

create or replace function public.ensure_personal_organization(
  p_user_id uuid,
  p_email text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
  v_local_part text;
  v_workspace_name text;
begin
  select o.id
    into v_organization_id
  from public.organizations o
  where o.owner_user_id = p_user_id
    and o.is_personal = true
  order by o.created_at asc
  limit 1;

  if v_organization_id is null then
    v_local_part := split_part(coalesce(p_email, ''), '@', 1);
    if v_local_part is null or btrim(v_local_part) = '' then
      v_workspace_name := 'Personal Workspace';
    else
      v_workspace_name := initcap(replace(v_local_part, '.', ' ')) || ' Workspace';
    end if;

    insert into public.organizations (
      owner_user_id,
      name,
      is_personal,
      billing_state,
      plan_code
    )
    values (
      p_user_id,
      v_workspace_name,
      true,
      'trialing',
      'free'
    )
    returning id into v_organization_id;
  end if;

  insert into public.organization_members (
    organization_id,
    user_id,
    role,
    member_state,
    invited_email,
    invited_by_user_id
  )
  values (
    v_organization_id,
    p_user_id,
    'owner',
    'active',
    p_email,
    p_user_id
  )
  on conflict (organization_id, user_id) do update
    set role = 'owner',
        member_state = 'active',
        updated_at = now();

  return v_organization_id;
end;
$$;

create or replace function public.personal_organization_id_for_user(p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select o.id
  from public.organizations o
  where o.owner_user_id = p_user_id
    and o.is_personal = true
  order by o.created_at asc
  limit 1;
$$;

create or replace function public.assign_default_organization_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id uuid;
begin
  if new.organization_id is not null then
    return new;
  end if;

  if new.user_id is null then
    return new;
  end if;

  v_organization_id := public.personal_organization_id_for_user(new.user_id);
  if v_organization_id is null then
    v_organization_id := public.ensure_personal_organization(new.user_id, null);
  end if;

  new.organization_id := v_organization_id;
  return new;
end;
$$;

-- Account type is persisted in profiles and can be used to tailor onboarding/UX.
alter table public.profiles add column if not exists account_type text not null default 'individual';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_account_type_check'
  ) then
    alter table public.profiles
      add constraint profiles_account_type_check
      check (account_type in ('individual', 'organization'));
  end if;
end $$;

create or replace function public.bootstrap_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_type text;
begin
  v_account_type := lower(btrim(coalesce(new.raw_user_meta_data ->> 'account_type', '')));
  if v_account_type not in ('individual', 'organization') then
    v_account_type := 'individual';
  end if;

  insert into public.profiles (
    id,
    email,
    account_type,
    updated_at
  )
  values (
    new.id,
    new.email,
    v_account_type,
    now()
  )
  on conflict (id) do update
    set email = coalesce(excluded.email, public.profiles.email),
        account_type = coalesce(public.profiles.account_type, excluded.account_type),
        updated_at = now();

  perform public.apply_pending_invitations_for_user(new.id, new.email);
  if not exists (
    select 1
    from public.organization_members m
    where m.user_id = new.id
      and m.member_state = 'active'
  ) then
    perform public.ensure_personal_organization(new.id, new.email);
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_bootstrap on auth.users;
create trigger on_auth_user_bootstrap
after insert on auth.users
for each row execute function public.bootstrap_new_auth_user();

-- Backfill existing users and personal workspaces.
do $$
declare
  v_user record;
begin
  for v_user in
    select id, email
    from auth.users
  loop
    insert into public.profiles (id, email, account_type, updated_at)
    values (
      v_user.id,
      v_user.email,
      case
        when exists (
          select 1
          from public.organizations o
          where o.owner_user_id = v_user.id
            and o.is_personal = false
        ) then 'organization'
        else 'individual'
      end,
      now()
    )
    on conflict (id) do update
      set email = coalesce(excluded.email, public.profiles.email),
          account_type = coalesce(public.profiles.account_type, excluded.account_type),
          updated_at = now();

    perform public.apply_pending_invitations_for_user(v_user.id, v_user.email);
    if not exists (
      select 1
      from public.organization_members m
      where m.user_id = v_user.id
        and m.member_state = 'active'
    ) then
      perform public.ensure_personal_organization(v_user.id, v_user.email);
    end if;
  end loop;
end $$;

-- Account lifecycle status in profiles.
alter table public.profiles add column if not exists account_state text not null default 'active';
alter table public.profiles add column if not exists account_state_changed_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_account_state_check'
  ) then
    alter table public.profiles
      add constraint profiles_account_state_check
      check (account_state in ('active', 'invited', 'suspended', 'deleted'));
  end if;
end $$;

-- Add organization_id to domain tables, backfill from personal org, set safe defaults.
alter table public.land_groups add column if not exists organization_id uuid;
alter table public.lands add column if not exists organization_id uuid;
alter table public.land_history_entries add column if not exists organization_id uuid;
alter table public.land_tasks add column if not exists organization_id uuid;
alter table public.push_devices add column if not exists organization_id uuid;
alter table public.land_task_push_deliveries add column if not exists organization_id uuid;
alter table public.spreadsheet_sources add column if not exists organization_id uuid;

update public.land_groups g
set organization_id = o.id
from public.organizations o
where g.organization_id is null
  and g.user_id = o.owner_user_id
  and o.is_personal = true;

update public.lands l
set organization_id = o.id
from public.organizations o
where l.organization_id is null
  and l.user_id = o.owner_user_id
  and o.is_personal = true;

update public.land_history_entries h
set organization_id = o.id
from public.organizations o
where h.organization_id is null
  and h.user_id = o.owner_user_id
  and o.is_personal = true;

update public.land_tasks t
set organization_id = o.id
from public.organizations o
where t.organization_id is null
  and t.user_id = o.owner_user_id
  and o.is_personal = true;

update public.push_devices d
set organization_id = o.id
from public.organizations o
where d.organization_id is null
  and d.user_id = o.owner_user_id
  and o.is_personal = true;

update public.land_task_push_deliveries pd
set organization_id = o.id
from public.organizations o
where pd.organization_id is null
  and pd.user_id = o.owner_user_id
  and o.is_personal = true;

update public.spreadsheet_sources s
set organization_id = o.id
from public.organizations o
where s.organization_id is null
  and s.user_id = o.owner_user_id
  and o.is_personal = true;

alter table public.land_groups alter column organization_id set default public.current_personal_organization_id();
alter table public.lands alter column organization_id set default public.current_personal_organization_id();
alter table public.land_history_entries alter column organization_id set default public.current_personal_organization_id();
alter table public.land_tasks alter column organization_id set default public.current_personal_organization_id();
alter table public.push_devices alter column organization_id set default public.current_personal_organization_id();
alter table public.land_task_push_deliveries alter column organization_id set default public.current_personal_organization_id();
alter table public.spreadsheet_sources alter column organization_id set default public.current_personal_organization_id();

drop trigger if exists trg_land_groups_assign_org on public.land_groups;
create trigger trg_land_groups_assign_org
before insert or update on public.land_groups
for each row execute function public.assign_default_organization_id();

drop trigger if exists trg_lands_assign_org on public.lands;
create trigger trg_lands_assign_org
before insert or update on public.lands
for each row execute function public.assign_default_organization_id();

drop trigger if exists trg_land_history_assign_org on public.land_history_entries;
create trigger trg_land_history_assign_org
before insert or update on public.land_history_entries
for each row execute function public.assign_default_organization_id();

drop trigger if exists trg_land_tasks_assign_org on public.land_tasks;
create trigger trg_land_tasks_assign_org
before insert or update on public.land_tasks
for each row execute function public.assign_default_organization_id();

drop trigger if exists trg_push_devices_assign_org on public.push_devices;
create trigger trg_push_devices_assign_org
before insert or update on public.push_devices
for each row execute function public.assign_default_organization_id();

drop trigger if exists trg_task_push_deliveries_assign_org on public.land_task_push_deliveries;
create trigger trg_task_push_deliveries_assign_org
before insert or update on public.land_task_push_deliveries
for each row execute function public.assign_default_organization_id();

drop trigger if exists trg_spreadsheet_sources_assign_org on public.spreadsheet_sources;
create trigger trg_spreadsheet_sources_assign_org
before insert or update on public.spreadsheet_sources
for each row execute function public.assign_default_organization_id();

update public.land_groups g
set organization_id = coalesce(
  public.personal_organization_id_for_user(g.user_id),
  public.ensure_personal_organization(g.user_id, null)
)
where g.organization_id is null;

update public.lands l
set organization_id = coalesce(
  public.personal_organization_id_for_user(l.user_id),
  public.ensure_personal_organization(l.user_id, null)
)
where l.organization_id is null;

update public.land_history_entries h
set organization_id = coalesce(
  public.personal_organization_id_for_user(h.user_id),
  public.ensure_personal_organization(h.user_id, null)
)
where h.organization_id is null;

update public.land_tasks t
set organization_id = coalesce(
  public.personal_organization_id_for_user(t.user_id),
  public.ensure_personal_organization(t.user_id, null)
)
where t.organization_id is null;

update public.push_devices d
set organization_id = coalesce(
  public.personal_organization_id_for_user(d.user_id),
  public.ensure_personal_organization(d.user_id, null)
)
where d.organization_id is null;

update public.land_task_push_deliveries pd
set organization_id = coalesce(
  public.personal_organization_id_for_user(pd.user_id),
  public.ensure_personal_organization(pd.user_id, null)
)
where pd.organization_id is null;

update public.spreadsheet_sources s
set organization_id = coalesce(
  public.personal_organization_id_for_user(s.user_id),
  public.ensure_personal_organization(s.user_id, null)
)
where s.organization_id is null;

alter table public.land_groups alter column organization_id set not null;
alter table public.lands alter column organization_id set not null;
alter table public.land_history_entries alter column organization_id set not null;
alter table public.land_tasks alter column organization_id set not null;
alter table public.push_devices alter column organization_id set not null;
alter table public.land_task_push_deliveries alter column organization_id set not null;
alter table public.spreadsheet_sources alter column organization_id set not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'land_groups_organization_id_fkey') then
    alter table public.land_groups
      add constraint land_groups_organization_id_fkey
      foreign key (organization_id) references public.organizations (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'lands_organization_id_fkey') then
    alter table public.lands
      add constraint lands_organization_id_fkey
      foreign key (organization_id) references public.organizations (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'land_history_entries_organization_id_fkey') then
    alter table public.land_history_entries
      add constraint land_history_entries_organization_id_fkey
      foreign key (organization_id) references public.organizations (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'land_tasks_organization_id_fkey') then
    alter table public.land_tasks
      add constraint land_tasks_organization_id_fkey
      foreign key (organization_id) references public.organizations (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'push_devices_organization_id_fkey') then
    alter table public.push_devices
      add constraint push_devices_organization_id_fkey
      foreign key (organization_id) references public.organizations (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'land_task_push_deliveries_organization_id_fkey') then
    alter table public.land_task_push_deliveries
      add constraint land_task_push_deliveries_organization_id_fkey
      foreign key (organization_id) references public.organizations (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'spreadsheet_sources_organization_id_fkey') then
    alter table public.spreadsheet_sources
      add constraint spreadsheet_sources_organization_id_fkey
      foreign key (organization_id) references public.organizations (id) on delete cascade;
  end if;
end $$;

create index if not exists idx_land_groups_organization_id on public.land_groups (organization_id);
create index if not exists idx_lands_organization_id on public.lands (organization_id);
create index if not exists idx_land_history_organization_id on public.land_history_entries (organization_id);
create index if not exists idx_land_tasks_organization_id on public.land_tasks (organization_id);
create index if not exists idx_push_devices_organization_id on public.push_devices (organization_id);
create index if not exists idx_task_push_deliveries_organization_id on public.land_task_push_deliveries (organization_id);
create index if not exists idx_spreadsheet_sources_organization_id on public.spreadsheet_sources (organization_id);

-- RLS for org and membership models.
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.organization_invitations enable row level security;

drop policy if exists "organizations_select_member" on public.organizations;
create policy "organizations_select_member"
on public.organizations for select
using (public.has_organization_role(id, 'viewer'));

drop policy if exists "organizations_insert_owner" on public.organizations;
create policy "organizations_insert_owner"
on public.organizations for insert
with check (auth.uid() = owner_user_id);

drop policy if exists "organizations_update_admin" on public.organizations;
create policy "organizations_update_admin"
on public.organizations for update
using (public.has_organization_role(id, 'admin'))
with check (public.has_organization_role(id, 'admin'));

drop policy if exists "organizations_delete_owner" on public.organizations;
create policy "organizations_delete_owner"
on public.organizations for delete
using (public.has_organization_role(id, 'owner'));

drop policy if exists "organization_members_select_member" on public.organization_members;
create policy "organization_members_select_member"
on public.organization_members for select
using (public.has_organization_role(organization_id, 'viewer'));

drop policy if exists "organization_members_insert_admin" on public.organization_members;
create policy "organization_members_insert_admin"
on public.organization_members for insert
with check (
  public.has_organization_role(organization_id, 'admin')
  and (role <> 'owner' or public.has_organization_role(organization_id, 'owner'))
);

drop policy if exists "organization_members_update_admin" on public.organization_members;
create policy "organization_members_update_admin"
on public.organization_members for update
using (
  public.has_organization_role(organization_id, 'admin')
  and (role <> 'owner' or public.has_organization_role(organization_id, 'owner'))
)
with check (
  public.has_organization_role(organization_id, 'admin')
  and (role <> 'owner' or public.has_organization_role(organization_id, 'owner'))
);

drop policy if exists "organization_members_delete_admin" on public.organization_members;
create policy "organization_members_delete_admin"
on public.organization_members for delete
using (
  public.has_organization_role(organization_id, 'admin')
  and (role <> 'owner' or public.has_organization_role(organization_id, 'owner'))
);

drop policy if exists "organization_invitations_select_member" on public.organization_invitations;
create policy "organization_invitations_select_member"
on public.organization_invitations for select
using (public.has_organization_role(organization_id, 'viewer'));

drop policy if exists "organization_invitations_insert_owner" on public.organization_invitations;
create policy "organization_invitations_insert_owner"
on public.organization_invitations for insert
with check (public.has_organization_role(organization_id, 'owner'));

drop policy if exists "organization_invitations_update_owner" on public.organization_invitations;
drop policy if exists "organization_invitations_update_admin" on public.organization_invitations;
create policy "organization_invitations_update_admin"
on public.organization_invitations for update
using (public.has_organization_role(organization_id, 'admin'))
with check (public.has_organization_role(organization_id, 'admin'));

drop policy if exists "organization_invitations_delete_owner" on public.organization_invitations;
create policy "organization_invitations_delete_owner"
on public.organization_invitations for delete
using (public.has_organization_role(organization_id, 'owner'));

-- Optional org-based policies for operational data.
-- Keep your current user_id policies for now; these are additive for migration.
drop policy if exists "land_groups_select_org_member" on public.land_groups;
create policy "land_groups_select_org_member"
on public.land_groups for select
using (organization_id is not null and public.has_organization_role(organization_id, 'viewer'));

drop policy if exists "land_groups_insert_org_member" on public.land_groups;
create policy "land_groups_insert_org_member"
on public.land_groups for insert
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "land_groups_update_org_member" on public.land_groups;
create policy "land_groups_update_org_member"
on public.land_groups for update
using (organization_id is not null and public.has_organization_role(organization_id, 'member'))
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "land_groups_delete_org_member" on public.land_groups;
create policy "land_groups_delete_org_member"
on public.land_groups for delete
using (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "lands_select_org_member" on public.lands;
create policy "lands_select_org_member"
on public.lands for select
using (organization_id is not null and public.has_organization_role(organization_id, 'viewer'));

drop policy if exists "lands_insert_org_member" on public.lands;
create policy "lands_insert_org_member"
on public.lands for insert
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "lands_update_org_member" on public.lands;
create policy "lands_update_org_member"
on public.lands for update
using (organization_id is not null and public.has_organization_role(organization_id, 'member'))
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "lands_delete_org_member" on public.lands;
create policy "lands_delete_org_member"
on public.lands for delete
using (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "land_history_select_org_member" on public.land_history_entries;
create policy "land_history_select_org_member"
on public.land_history_entries for select
using (organization_id is not null and public.has_organization_role(organization_id, 'viewer'));

drop policy if exists "land_history_insert_org_member" on public.land_history_entries;
create policy "land_history_insert_org_member"
on public.land_history_entries for insert
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "land_history_update_org_member" on public.land_history_entries;
create policy "land_history_update_org_member"
on public.land_history_entries for update
using (organization_id is not null and public.has_organization_role(organization_id, 'member'))
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "land_history_delete_org_member" on public.land_history_entries;
create policy "land_history_delete_org_member"
on public.land_history_entries for delete
using (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "land_tasks_select_org_member" on public.land_tasks;
create policy "land_tasks_select_org_member"
on public.land_tasks for select
using (organization_id is not null and public.has_organization_role(organization_id, 'viewer'));

drop policy if exists "land_tasks_insert_org_member" on public.land_tasks;
create policy "land_tasks_insert_org_member"
on public.land_tasks for insert
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "land_tasks_update_org_member" on public.land_tasks;
create policy "land_tasks_update_org_member"
on public.land_tasks for update
using (organization_id is not null and public.has_organization_role(organization_id, 'member'))
with check (organization_id is not null and public.has_organization_role(organization_id, 'member'));

drop policy if exists "land_tasks_delete_org_member" on public.land_tasks;
create policy "land_tasks_delete_org_member"
on public.land_tasks for delete
using (organization_id is not null and public.has_organization_role(organization_id, 'member'));

-- Function grants
revoke all on function public.organization_role_rank(text) from public;
grant execute on function public.organization_role_rank(text) to authenticated, service_role;

revoke all on function public.has_organization_role(uuid, text) from public;
grant execute on function public.has_organization_role(uuid, text) to authenticated, service_role;

revoke all on function public.is_organization_member(uuid) from public;
grant execute on function public.is_organization_member(uuid) to authenticated, service_role;

revoke all on function public.current_personal_organization_id() from public;
grant execute on function public.current_personal_organization_id() to authenticated, service_role;

revoke all on function public.personal_organization_id_for_user(uuid) from public;
grant execute on function public.personal_organization_id_for_user(uuid) to authenticated, service_role;

revoke all on function public.normalize_organization_invitation_email() from public;
grant execute on function public.normalize_organization_invitation_email() to authenticated, service_role;

revoke all on function public.apply_organization_invitation_if_user_exists() from public;
grant execute on function public.apply_organization_invitation_if_user_exists() to authenticated, service_role;

revoke all on function public.apply_pending_invitations_for_user(uuid, text) from public;
grant execute on function public.apply_pending_invitations_for_user(uuid, text) to service_role;

revoke all on function public.invite_organization_employee(uuid, text, text) from public;
grant execute on function public.invite_organization_employee(uuid, text, text) to authenticated, service_role;

revoke all on function public.can_register_employee(text) from public;
grant execute on function public.can_register_employee(text) to anon, authenticated, service_role;

revoke all on function public.ensure_personal_organization(uuid, text) from public;
grant execute on function public.ensure_personal_organization(uuid, text) to service_role;

revoke all on function public.assign_default_organization_id() from public;
grant execute on function public.assign_default_organization_id() to authenticated, service_role;

revoke all on function public.prevent_organization_owner_user_change() from public;
grant execute on function public.prevent_organization_owner_user_change() to authenticated, service_role;

create or replace function public.ensure_row_user_has_org_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.user_id is null then
    raise exception 'user_id is required';
  end if;

  if new.organization_id is null then
    raise exception 'organization_id is required';
  end if;

  if not exists (
    select 1
    from public.organization_members m
    where m.organization_id = new.organization_id
      and m.user_id = new.user_id
      and m.member_state = 'active'
  ) then
    raise exception 'user is not an active member of organization';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_land_groups_member_guard on public.land_groups;
create trigger trg_land_groups_member_guard
before insert or update on public.land_groups
for each row execute function public.ensure_row_user_has_org_membership();

drop trigger if exists trg_lands_member_guard on public.lands;
create trigger trg_lands_member_guard
before insert or update on public.lands
for each row execute function public.ensure_row_user_has_org_membership();

drop trigger if exists trg_land_history_member_guard on public.land_history_entries;
create trigger trg_land_history_member_guard
before insert or update on public.land_history_entries
for each row execute function public.ensure_row_user_has_org_membership();

drop trigger if exists trg_land_tasks_member_guard on public.land_tasks;
create trigger trg_land_tasks_member_guard
before insert or update on public.land_tasks
for each row execute function public.ensure_row_user_has_org_membership();

drop trigger if exists trg_push_devices_member_guard on public.push_devices;
create trigger trg_push_devices_member_guard
before insert or update on public.push_devices
for each row execute function public.ensure_row_user_has_org_membership();

drop trigger if exists trg_task_push_deliveries_member_guard on public.land_task_push_deliveries;
create trigger trg_task_push_deliveries_member_guard
before insert or update on public.land_task_push_deliveries
for each row execute function public.ensure_row_user_has_org_membership();

drop trigger if exists trg_spreadsheet_sources_member_guard on public.spreadsheet_sources;
create trigger trg_spreadsheet_sources_member_guard
before insert or update on public.spreadsheet_sources
for each row execute function public.ensure_row_user_has_org_membership();

alter table public.profiles force row level security;
alter table public.organizations force row level security;
alter table public.organization_members force row level security;
alter table public.organization_invitations force row level security;
alter table public.land_groups force row level security;
alter table public.lands force row level security;
alter table public.land_history_entries force row level security;
alter table public.land_tasks force row level security;
alter table public.push_devices force row level security;
alter table public.land_task_push_deliveries force row level security;
alter table public.spreadsheet_sources force row level security;

revoke all on table public.security_rate_limits from public;
revoke all on table public.security_rate_limits from anon;
revoke all on table public.security_rate_limits from authenticated;

revoke all on function public.request_client_identifier() from public;
grant execute on function public.request_client_identifier() to authenticated, service_role;

revoke all on function public.enforce_rate_limit(text, text, integer, integer) from public;
grant execute on function public.enforce_rate_limit(text, text, integer, integer) to service_role;

revoke all on function public.ensure_row_user_has_org_membership() from public;
grant execute on function public.ensure_row_user_has_org_membership() to authenticated, service_role;
