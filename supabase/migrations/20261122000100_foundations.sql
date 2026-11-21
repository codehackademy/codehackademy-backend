-- Phase 0 foundations (spec v1.4 §3, §4, §16.2, §18): roles, profiles, courses, cohorts,
-- membership, enrolments, moderator assignments, audit log, settings, public interest form.
-- Every table has Row Level Security. Nothing here relies on the apps hiding buttons.

------------------------------------------------------------------ enums
create type public.user_role as enum ('STUDENT', 'MODERATOR', 'ADMIN');
create type public.user_status as enum ('ACTIVE', 'SUSPENDED');
create type public.course_status as enum ('DRAFT', 'PUBLISHED');
create type public.runtime_stack as enum ('NODE_BACKEND', 'PYTHON_BACKEND', 'FRONTEND_PLAIN', 'FRONTEND_REACT');
create type public.cohort_status as enum ('DRAFT', 'ACTIVE', 'COMPLETED');
create type public.member_role as enum ('STUDENT', 'MODERATOR');
create type public.enrollment_status as enum ('ACTIVE', 'DROPPED');

------------------------------------------------------------------ tables
-- "users" in the spec. One row per auth user. Created only by trusted server code (never by signup).
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role public.user_role not null,
  name text not null check (char_length(name) between 2 and 120),
  email text not null check (char_length(email) <= 254),
  github_username text check (github_username ~* '^[a-z\d](?:[a-z\d]|-(?=[a-z\d])){0,38}$'),
  country text check (char_length(country) <= 80),
  city text check (char_length(city) <= 80),
  timezone text,                       -- IANA name, e.g. Africa/Lagos
  status public.user_status not null default 'ACTIVE',
  suspension_reason text,
  consented_at timestamptz,            -- consent recorded at onboarding (NDPA 2023)
  onboarded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint profiles_suspension_reason check (status = 'ACTIVE' or suspension_reason is not null)
);
create unique index profiles_email_key on public.profiles (lower(email));
create unique index profiles_github_key on public.profiles (lower(github_username)) where github_username is not null;

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  description text not null default '' check (char_length(description) <= 2000),
  runtime_stack public.runtime_stack not null,
  status public.course_status not null default 'DRAFT',
  created_at timestamptz not null default now()
);

create table public.cohorts (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  start_date date not null,
  end_date date,
  unlock_time_utc time not null default '05:00',          -- 06:00 in Lagos
  phase1_hours integer not null default 24 check (phase1_hours > 0),
  phase2_hours integer not null default 48 check (phase2_hours > 0),
  cloned_from_cohort_id uuid references public.cohorts (id) on delete set null,
  status public.cohort_status not null default 'DRAFT',
  created_at timestamptz not null default now(),
  constraint cohorts_dates check (end_date is null or end_date >= start_date)
);

create table public.cohort_courses (
  id uuid primary key default gen_random_uuid(),
  cohort_id uuid not null references public.cohorts (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete restrict,
  course_start_date date not null,
  unique (cohort_id, course_id)
);

create table public.cohort_members (
  cohort_id uuid not null references public.cohorts (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  member_role public.member_role not null,
  joined_at timestamptz not null default now(),
  primary key (cohort_id, user_id)
);

create table public.enrollments (
  student_id uuid not null references public.profiles (id) on delete cascade,
  cohort_course_id uuid not null references public.cohort_courses (id) on delete cascade,
  status public.enrollment_status not null default 'ACTIVE',
  primary key (student_id, cohort_course_id)
);

create table public.moderator_assignments (
  moderator_id uuid not null references public.profiles (id) on delete cascade,
  cohort_course_id uuid not null references public.cohort_courses (id) on delete cascade,
  primary key (moderator_id, cohort_course_id)
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid,                        -- null when written by a trusted service
  action text not null,
  entity_type text not null,
  entity_id text,
  before_json jsonb,
  after_json jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_created_idx on public.audit_logs (created_at desc);

create table public.settings (
  key text primary key,
  value jsonb not null,
  description text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);

-- Public interest form. NOT an account and never an enrolment.
create table public.interest_submissions (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (char_length(full_name) between 2 and 120),
  email text not null check (char_length(email) between 5 and 254 and email like '%_@_%._%'),
  email_key text generated always as (lower(email)) stored unique,
  phone text check (char_length(phone) <= 40),
  country text not null check (char_length(country) between 2 and 80),
  city text not null check (char_length(city) between 2 and 80),
  programme text not null check (programme in ('BACKEND_ENGINEERING', 'FRONTEND_ENGINEERING', 'UNDECIDED')),
  experience text not null check (experience in ('NONE', 'BEGINNER', 'INTERMEDIATE', 'ADVANCED')),
  reason text not null check (char_length(reason) between 20 and 1500),
  goals text check (char_length(goals) <= 1500),
  availability text not null check (availability in ('LT_5', 'H5_10', 'H10_20', 'GT_20')),
  portfolio_url text check (portfolio_url ~* '^https?://[^\s]+$' and char_length(portfolio_url) <= 300),
  consented_at timestamptz not null default now(),
  status text not null default 'NEW' check (status in ('NEW', 'CONTACTED', 'ARCHIVED')),
  created_at timestamptz not null default now()
);

------------------------------------------------------------------ settings defaults (spec §15, all configurable)
insert into public.settings (key, value, description) values
  ('phase1_hours', '24', 'Default Phase 1 length in hours'),
  ('phase2_hours', '48', 'Default Phase 2 length in hours (starts right after Phase 1)'),
  ('unlock_time_utc', '"05:00"', 'Default project unlock time, UTC (06:00 in Lagos)'),
  ('max_concurrent_submissions', '3', 'Maximum non-terminal submissions per student'),
  ('submission_cooldown_seconds', '30', 'Cooldown between two submissions of the same task'),
  ('leaderboard_reveal_utc', '"17:00"', 'Default leaderboard reveal time, UTC (18:00 in Lagos)'),
  ('event_reminder_minutes', '60', 'Minutes before an event that students are reminded');

------------------------------------------------------------------ helper functions
-- SECURITY DEFINER so policies can ask "who is this user?" without recursive RLS.
create function public.auth_role() returns public.user_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid() and status is not null
$$;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'ADMIN')
$$;

create function public.is_cohort_member(p_cohort uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.cohort_members where cohort_id = p_cohort and user_id = auth.uid())
$$;

create function public.moderates_cohort_course(p_cc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.moderator_assignments where cohort_course_id = p_cc and moderator_id = auth.uid())
$$;

create function public.moderates_cohort(p_cohort uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.moderator_assignments ma join public.cohort_courses cc on cc.id = ma.cohort_course_id
    where ma.moderator_id = auth.uid() and cc.cohort_id = p_cohort)
$$;

-- Moderators see only students enrolled in a cohort course they are assigned to.
create function public.moderates_student(p_student uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.enrollments e join public.moderator_assignments ma on ma.cohort_course_id = e.cohort_course_id
    where e.student_id = p_student and ma.moderator_id = auth.uid())
$$;

create function public.can_access_cohort_course(p_cc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.moderates_cohort_course(p_cc)
      or exists (select 1 from public.enrollments where cohort_course_id = p_cc and student_id = auth.uid())
$$;

create function public.can_access_course(p_course uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.cohort_courses cc where cc.course_id = p_course and public.can_access_cohort_course(cc.id))
$$;

------------------------------------------------------------------ integrity triggers
create function public.enforce_profile_columns() returns trigger language plpgsql as $$
begin
  -- Trusted server code (service role / migrations) and admins may change anything.
  if current_user in ('service_role', 'postgres', 'supabase_admin') or public.is_admin() then
    return new;
  end if;
  if new.id is distinct from old.id or new.role is distinct from old.role or new.email is distinct from old.email
     or new.status is distinct from old.status or new.suspension_reason is distinct from old.suspension_reason
     or new.github_username is distinct from old.github_username or new.consented_at is distinct from old.consented_at
     or new.onboarded_at is distinct from old.onboarded_at or new.created_at is distinct from old.created_at then
    raise exception 'FORBIDDEN: protected profile columns cannot be changed' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger profiles_protect before update on public.profiles for each row execute function public.enforce_profile_columns();

create function public.check_member_role() returns trigger language plpgsql security definer set search_path = public as $$
declare r public.user_role;
begin
  select role into r from public.profiles where id = new.user_id;
  if r is null or r::text <> new.member_role::text then
    raise exception 'member_role must match the user role' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger cohort_members_role before insert or update on public.cohort_members for each row execute function public.check_member_role();

create function public.check_enrollment() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.profiles where id = new.student_id and role = 'STUDENT') then
    raise exception 'only students can be enrolled' using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.cohort_courses cc join public.cohort_members m on m.cohort_id = cc.cohort_id
    where cc.id = new.cohort_course_id and m.user_id = new.student_id) then
    raise exception 'student must be a member of the cohort first' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger enrollments_check before insert on public.enrollments for each row execute function public.check_enrollment();

-- Assigning a moderator to a cohort course also makes them a cohort member.
create function public.check_assignment() returns trigger language plpgsql security definer set search_path = public as $$
declare v_cohort uuid;
begin
  if not exists (select 1 from public.profiles where id = new.moderator_id and role = 'MODERATOR') then
    raise exception 'only moderators can be assigned' using errcode = '23514';
  end if;
  select cohort_id into v_cohort from public.cohort_courses where id = new.cohort_course_id;
  insert into public.cohort_members (cohort_id, user_id, member_role) values (v_cohort, new.moderator_id, 'MODERATOR')
  on conflict do nothing;
  return new;
end $$;
create trigger moderator_assignments_check before insert on public.moderator_assignments for each row execute function public.check_assignment();

------------------------------------------------------------------ audit log (append-only, spec §16.2)
create function public.audit_row_change() returns trigger language plpgsql security definer set search_path = public as $$
declare
  j_new jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  j_old jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  src jsonb := coalesce(j_new, j_old);
  key_parts text[] := '{}';
  col text;
begin
  foreach col in array tg_argv loop key_parts := key_parts || coalesce(src ->> col, ''); end loop;
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, before_json, after_json)
  values (auth.uid(), lower(tg_op), tg_table_name, array_to_string(key_parts, ':'), j_old, j_new);
  return null;
end $$;

create trigger audit_courses after insert or update or delete on public.courses for each row execute function public.audit_row_change('id');
create trigger audit_cohorts after insert or update or delete on public.cohorts for each row execute function public.audit_row_change('id');
create trigger audit_cohort_courses after insert or update or delete on public.cohort_courses for each row execute function public.audit_row_change('id');
create trigger audit_cohort_members after insert or update or delete on public.cohort_members for each row execute function public.audit_row_change('cohort_id', 'user_id');
create trigger audit_enrollments after insert or update or delete on public.enrollments for each row execute function public.audit_row_change('student_id', 'cohort_course_id');
create trigger audit_moderator_assignments after insert or update or delete on public.moderator_assignments for each row execute function public.audit_row_change('moderator_id', 'cohort_course_id');
create trigger audit_settings after insert or update or delete on public.settings for each row execute function public.audit_row_change('key');
-- Profiles: log role, status, suspension and GitHub username changes (not routine settings edits).
create trigger audit_profiles_insert after insert on public.profiles for each row execute function public.audit_row_change('id');
create trigger audit_profiles_update after update on public.profiles for each row
  when (old.role is distinct from new.role or old.status is distinct from new.status
        or old.suspension_reason is distinct from new.suspension_reason or old.github_username is distinct from new.github_username)
  execute function public.audit_row_change('id');

create function public.audit_logs_immutable() returns trigger language plpgsql as $$
begin
  raise exception 'audit_logs is append-only' using errcode = '42501';
end $$;
create trigger audit_logs_no_update before update or delete on public.audit_logs for each row execute function public.audit_logs_immutable();
create trigger audit_logs_no_truncate before truncate on public.audit_logs for each statement execute function public.audit_logs_immutable();

------------------------------------------------------------------ privileges (least privilege; RLS does the rest)
alter default privileges in schema public revoke all on tables from anon, authenticated;
revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public;

grant usage on schema public to anon, authenticated, service_role;
grant select on public.profiles, public.courses, public.cohorts, public.cohort_courses, public.cohort_members,
  public.enrollments, public.moderator_assignments, public.audit_logs, public.settings to authenticated;
grant update (name, country, city, timezone) on public.profiles to authenticated;   -- column-level; admins edit more via service code
grant update (role, status, suspension_reason, email, github_username) on public.profiles to authenticated; -- gated by enforce_profile_columns + RLS (admin only)
grant insert, update, delete on public.courses, public.cohorts, public.cohort_courses, public.cohort_members,
  public.enrollments, public.moderator_assignments to authenticated;
grant update on public.settings to authenticated;
grant select, update on public.interest_submissions to authenticated;
grant insert on public.interest_submissions to anon, authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on all functions in schema public to authenticated, service_role;
revoke execute on function public.enforce_profile_columns(), public.audit_row_change(), public.audit_logs_immutable(),
  public.check_member_role(), public.check_enrollment(), public.check_assignment() from authenticated;

------------------------------------------------------------------ Row Level Security
alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.cohorts enable row level security;
alter table public.cohort_courses enable row level security;
alter table public.cohort_members enable row level security;
alter table public.enrollments enable row level security;
alter table public.moderator_assignments enable row level security;
alter table public.audit_logs enable row level security;
alter table public.settings enable row level security;
alter table public.interest_submissions enable row level security;

-- profiles
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin() or public.moderates_student(id));
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());

-- courses
create policy courses_select on public.courses for select to authenticated
  using (public.is_admin() or public.can_access_course(id));
create policy courses_admin_write on public.courses for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- cohorts
create policy cohorts_select on public.cohorts for select to authenticated
  using (public.is_admin() or public.is_cohort_member(id) or public.moderates_cohort(id));
create policy cohorts_admin_write on public.cohorts for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- cohort_courses
create policy cohort_courses_select on public.cohort_courses for select to authenticated
  using (public.is_admin() or public.can_access_cohort_course(id));
create policy cohort_courses_admin_write on public.cohort_courses for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- cohort_members: own row, or students of courses the moderator handles
create policy cohort_members_select on public.cohort_members for select to authenticated
  using (public.is_admin() or user_id = auth.uid() or public.moderates_student(user_id));
create policy cohort_members_admin_write on public.cohort_members for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- enrollments
create policy enrollments_select on public.enrollments for select to authenticated
  using (public.is_admin() or student_id = auth.uid() or public.moderates_cohort_course(cohort_course_id));
create policy enrollments_admin_write on public.enrollments for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- moderator_assignments
create policy moderator_assignments_select on public.moderator_assignments for select to authenticated
  using (public.is_admin() or moderator_id = auth.uid());
create policy moderator_assignments_admin_write on public.moderator_assignments for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- audit_logs: admins read; nobody writes directly (triggers and trusted services only)
create policy audit_logs_select on public.audit_logs for select to authenticated using (public.is_admin());

-- settings: any signed-in user may read; only admins change
create policy settings_select on public.settings for select to authenticated using (true);
create policy settings_admin_update on public.settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- interest_submissions: anyone may submit; only admins read or triage
create policy interest_insert on public.interest_submissions for insert to anon, authenticated
  with check (status = 'NEW');
create policy interest_admin_select on public.interest_submissions for select to authenticated using (public.is_admin());
create policy interest_admin_update on public.interest_submissions for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

------------------------------------------------------------------ first admin bootstrap
-- Admins are never created through the apps. After creating the auth user in the Supabase
-- dashboard, run:  select public.bootstrap_first_admin('you@example.com', 'Your Name');
create function public.bootstrap_first_admin(p_email text, p_name text) returns uuid
language plpgsql security definer set search_path = public, auth as $$
declare v_id uuid;
begin
  if exists (select 1 from public.profiles where role = 'ADMIN') then
    raise exception 'an admin already exists';
  end if;
  select id into v_id from auth.users where lower(email) = lower(p_email);
  if v_id is null then raise exception 'create the auth user for % first', p_email; end if;
  insert into public.profiles (id, role, name, email, onboarded_at) values (v_id, 'ADMIN', p_name, lower(p_email), now());
  return v_id;
end $$;
revoke execute on function public.bootstrap_first_admin(text, text) from public, anon, authenticated;
