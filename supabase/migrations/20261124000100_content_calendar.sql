-- Phase 1: content (projects, tasks, test cases, rubrics) and calendar (cohort projects, holidays, events),
-- scheduling (spec 5.1-5.5), cloning (5.4) and publish checks (spec 15). All business rules live here, once.

------------------------------------------------------------------ enums
create type public.content_status as enum ('DRAFT', 'PUBLISHED');
create type public.task_kind as enum ('FUNCTION', 'STDIO', 'HTTP', 'BROWSER', 'GIT');
create type public.judging_mode as enum ('ARBITER', 'PEER', 'MODERATOR');
create type public.language_runtime as enum ('NODE', 'PYTHON', 'BROWSER', 'REACT', 'GIT');
create type public.show_test_cases as enum ('ALL', 'SAMPLES_ONLY', 'NONE');
create type public.event_type as enum ('CLASS', 'WORKSHOP', 'GUEST_TALK', 'MEETUP', 'OTHER');

------------------------------------------------------------------ tables
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  title text not null check (char_length(title) between 2 and 160),
  slug text not null check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  summary text not null default '' check (char_length(summary) <= 500),
  notes_markdown text not null default '' check (char_length(notes_markdown) <= 100000),
  instructions_markdown text not null default '' check (char_length(instructions_markdown) <= 100000),
  pdf_url text,
  weight numeric not null default 1 check (weight > 0),
  sequence_no integer not null,
  repo_name text check (repo_name ~ '^[a-z0-9][a-z0-9._-]{0,99}$'),
  status public.content_status not null default 'DRAFT',
  created_at timestamptz not null default now(),
  unique (course_id, slug),
  constraint projects_sequence unique (course_id, sequence_no) deferrable initially deferred
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  title text not null check (char_length(title) between 2 and 160),
  description_markdown text not null default '' check (char_length(description_markdown) <= 100000),
  sequence_no integer not null,
  kind public.task_kind not null,
  judging_mode public.judging_mode not null,
  entry_files text[] not null default '{}',
  language_runtime public.language_runtime not null,
  dependencies jsonb not null default '[]' check (jsonb_typeof(dependencies) = 'array'),
  complexity_check_enabled boolean not null default false,
  show_test_cases public.show_test_cases not null default 'ALL',
  time_limit_ms integer not null default 2000 check (time_limit_ms between 100 and 30000),
  memory_limit_mb integer not null default 256 check (memory_limit_mb between 16 and 1024),
  class_link_url text check (class_link_url is null or class_link_url ~* '^https?://'),
  status public.content_status not null default 'DRAFT',
  created_at timestamptz not null default now(),
  constraint tasks_sequence unique (project_id, sequence_no) deferrable initially deferred,
  constraint tasks_kind_runtime check (
    (kind in ('FUNCTION', 'STDIO', 'HTTP') and language_runtime in ('NODE', 'PYTHON'))
    or (kind = 'BROWSER' and language_runtime in ('BROWSER', 'REACT'))
    or (kind = 'GIT' and language_runtime = 'GIT'))
);

create table public.test_cases (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 200),
  kind public.task_kind not null,
  input_spec jsonb not null default '{}',
  expected_spec jsonb not null default '{}',
  weight numeric not null default 1 check (weight > 0),
  is_visible boolean not null default true,
  sort_order integer not null default 0
);
create index test_cases_task_idx on public.test_cases (task_id, sort_order);

create table public.rubric_criteria (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks (id) on delete cascade,
  label text not null check (char_length(label) between 1 and 200),
  description text not null default '' check (char_length(description) <= 2000),
  weight numeric not null default 1 check (weight > 0),
  sort_order integer not null default 0
);
create index rubric_criteria_task_idx on public.rubric_criteria (task_id, sort_order);

-- Admin-only. `validated_score` is written by the Arbiter service (Phase 2) after running the reference solution.
create table public.task_reference_solutions (
  task_id uuid primary key references public.tasks (id) on delete cascade,
  files jsonb not null default '{}' check (jsonb_typeof(files) = 'object'),
  validated_score numeric check (validated_score between 0 and 100),
  validated_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.cohort_projects (
  id uuid primary key default gen_random_uuid(),
  cohort_course_id uuid not null references public.cohort_courses (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  unlock_at timestamptz not null,
  phase1_ends_at timestamptz not null,
  phase2_ends_at timestamptz not null,
  dates_locked boolean not null default false,
  class_link_url text check (class_link_url is null or class_link_url ~* '^https?://'),
  unique (cohort_course_id, project_id),
  constraint cohort_projects_order check (unlock_at < phase1_ends_at and phase1_ends_at < phase2_ends_at)
);

create table public.holidays (
  id uuid primary key default gen_random_uuid(),
  cohort_id uuid references public.cohorts (id) on delete cascade,   -- null = global
  date date not null,
  label text not null check (char_length(label) between 1 and 120),
  unique nulls not distinct (cohort_id, date)
);

create table public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  cohort_id uuid not null references public.cohorts (id) on delete cascade,
  cohort_course_id uuid references public.cohort_courses (id) on delete cascade,  -- null = whole cohort
  title text not null check (char_length(title) between 2 and 160),
  description text not null default '' check (char_length(description) <= 4000),
  event_type public.event_type not null default 'OTHER',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location_or_link text check (char_length(location_or_link) <= 500),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint calendar_events_time check (ends_at > starts_at)
);
create index calendar_events_cohort_idx on public.calendar_events (cohort_id, starts_at);

------------------------------------------------------------------ integrity triggers
-- sequence_no is NOT NULL: callers may omit it (0 = "append"), and the trigger assigns the next number.
alter table public.projects alter column sequence_no set default 0;
alter table public.tasks alter column sequence_no set default 0;

create function public.projects_assign_sequence() returns trigger language plpgsql as $$
begin
  if new.sequence_no = 0 then
    select coalesce(max(sequence_no), 0) + 1 into new.sequence_no from public.projects where course_id = new.course_id;
  end if;
  return new;
end $$;
create trigger projects_seq before insert on public.projects for each row execute function public.projects_assign_sequence();

create function public.tasks_assign_sequence() returns trigger language plpgsql as $$
begin
  if new.sequence_no = 0 then
    select coalesce(max(sequence_no), 0) + 1 into new.sequence_no from public.tasks where project_id = new.project_id;
  end if;
  return new;
end $$;
create trigger tasks_seq before insert on public.tasks for each row execute function public.tasks_assign_sequence();

create function public.check_test_case_kind() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.tasks where id = new.task_id and kind = new.kind) then
    raise exception 'test case kind must match the task kind' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger test_cases_kind before insert or update on public.test_cases for each row execute function public.check_test_case_kind();

create function public.check_task_kind_change() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind is distinct from old.kind and exists (select 1 from public.test_cases where task_id = new.id) then
    raise exception 'remove the test cases before changing the task kind' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger tasks_kind_change before update on public.tasks for each row execute function public.check_task_kind_change();

-- Any change to the test set or reference solution makes an earlier validation stale.
create function public.invalidate_reference() returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.task_reference_solutions set validated_score = null, validated_at = null
  where task_id = coalesce(new.task_id, old.task_id) and validated_score is not null;
  return null;
end $$;
create trigger test_cases_invalidate after insert or update or delete on public.test_cases for each row execute function public.invalidate_reference();

create function public.guard_reference_solution() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if current_user in ('service_role', 'postgres', 'supabase_admin') then return new; end if;
  if tg_op = 'INSERT' then
    new.validated_score := null; new.validated_at := null;
  elsif new.files is distinct from old.files then
    new.validated_score := null; new.validated_at := null;
  else
    new.validated_score := old.validated_score; new.validated_at := old.validated_at;  -- only Arbiter may validate
  end if;
  return new;
end $$;
create trigger reference_guard before insert or update on public.task_reference_solutions for each row execute function public.guard_reference_solution();

-- Publishing happens only through the publish_* functions (which check the rules). Direct status writes by users are refused.
create function public.guard_publish() returns trigger language plpgsql as $$
declare v_target text := case tg_table_name when 'cohorts' then 'ACTIVE' else 'PUBLISHED' end;
begin
  if current_user in ('service_role', 'postgres', 'supabase_admin') then return new; end if;
  if new.status::text = v_target and (tg_op = 'INSERT' or old.status::text <> v_target) then
    raise exception 'FORBIDDEN: use the publish action, which runs the publish checks' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger courses_publish_guard before insert or update on public.courses for each row execute function public.guard_publish();
create trigger projects_publish_guard before insert or update on public.projects for each row execute function public.guard_publish();
create trigger tasks_publish_guard before insert or update on public.tasks for each row execute function public.guard_publish();
create trigger cohorts_publish_guard before insert or update on public.cohorts for each row execute function public.guard_publish();

create function public.check_event_course() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.cohort_course_id is not null and not exists (select 1 from public.cohort_courses where id = new.cohort_course_id and cohort_id = new.cohort_id) then
    raise exception 'the course does not belong to that cohort' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger calendar_events_course before insert or update on public.calendar_events for each row execute function public.check_event_course();

------------------------------------------------------------------ audit
create trigger audit_projects after insert or update or delete on public.projects for each row execute function public.audit_row_change('id');
create trigger audit_tasks after insert or update or delete on public.tasks for each row execute function public.audit_row_change('id');
create trigger audit_test_cases after insert or update or delete on public.test_cases for each row execute function public.audit_row_change('id');
create trigger audit_rubric_criteria after insert or update or delete on public.rubric_criteria for each row execute function public.audit_row_change('id');
create trigger audit_cohort_projects after insert or update or delete on public.cohort_projects for each row execute function public.audit_row_change('id');
create trigger audit_holidays after insert or update or delete on public.holidays for each row execute function public.audit_row_change('id');
create trigger audit_calendar_events after insert or update or delete on public.calendar_events for each row execute function public.audit_row_change('id');

------------------------------------------------------------------ access helpers
create function public.cohort_is_active(p_cohort uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.cohorts where id = p_cohort and status = 'ACTIVE')
$$;

-- A published cohort course the signed-in student is actively enrolled in.
create function public.student_in_active_cohort_course(p_cc uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.enrollments e join public.cohort_courses cc on cc.id = e.cohort_course_id join public.cohorts c on c.id = cc.cohort_id
    where e.cohort_course_id = p_cc and e.student_id = auth.uid() and e.status = 'ACTIVE' and c.status = 'ACTIVE')
$$;

create function public.can_read_project(p_project uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (
    select 1 from public.projects p where p.id = p_project and p.status = 'PUBLISHED' and (
      exists (select 1 from public.cohort_courses cc join public.moderator_assignments ma on ma.cohort_course_id = cc.id
              where cc.course_id = p.course_id and ma.moderator_id = auth.uid())
      or exists (select 1 from public.cohort_projects cp
                 where cp.project_id = p.id and cp.unlock_at <= now() and public.student_in_active_cohort_course(cp.cohort_course_id))))
$$;

create function public.can_read_task(p_task uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (select 1 from public.tasks t where t.id = p_task and t.status = 'PUBLISHED' and public.can_read_project(t.project_id))
$$;

------------------------------------------------------------------ calendar logic (spec 5.1, 5.3)
-- The one and only nextProjectDay: first date on or after p_date that is Mon-Fri and not a (global or cohort) holiday.
create function public.next_project_day(p_date date, p_cohort uuid) returns date language plpgsql stable security definer set search_path = public as $$
declare d date := p_date; n int := 0;
begin
  loop
    exit when extract(isodow from d) between 1 and 5
      and not exists (select 1 from public.holidays h where h.date = d and (h.cohort_id is null or h.cohort_id = p_cohort));
    d := d + 1; n := n + 1;
    if n > 3660 then raise exception 'no project day found within ten years'; end if;
  end loop;
  return d;
end $$;

create function public.require_admin() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN: administrators only' using errcode = '42501'; end if;
end $$;

-- Schedules every project of the cohort course in sequence order (5.3). Projects whose dates were edited by hand
-- (dates_locked) are kept. With p_from, projects that unlock before that date are also kept ("shift later projects").
create function public.schedule_cohort_course(p_cc uuid, p_from date default null) returns integer
language plpgsql security definer set search_path = public as $$
declare
  cc public.cohort_courses%rowtype; c public.cohorts%rowtype;
  v_cursor date; v_day date; v_ud date; v_unlock timestamptz; v_p1 timestamptz; v_n integer := 0; r record; v_new uuid[];
begin
  perform public.require_admin();
  select * into cc from public.cohort_courses where id = p_cc;
  if not found then raise exception 'cohort course not found' using errcode = 'P0002'; end if;
  select * into c from public.cohorts where id = cc.cohort_id;

  with ins as (
    insert into public.cohort_projects (cohort_course_id, project_id, unlock_at, phase1_ends_at, phase2_ends_at)
    select p_cc, p.id, now(), now() + interval '1 hour', now() + interval '2 hours'
    from public.projects p where p.course_id = cc.course_id
    on conflict (cohort_course_id, project_id) do nothing
    returning id)
  select coalesce(array_agg(id), '{}') into v_new from ins;

  v_cursor := public.next_project_day(cc.course_start_date, c.id);
  for r in select cp.id, cp.dates_locked, cp.unlock_at from public.cohort_projects cp join public.projects p on p.id = cp.project_id
           where cp.cohort_course_id = p_cc order by p.sequence_no loop
    v_ud := (r.unlock_at at time zone 'UTC')::date;
    if not (r.id = any (v_new)) and (r.dates_locked or (p_from is not null and v_ud < p_from)) then
      v_cursor := greatest(v_cursor, public.next_project_day(v_ud + 1, c.id));
    else
      v_day := public.next_project_day(v_cursor, c.id);
      v_unlock := (v_day + c.unlock_time_utc) at time zone 'UTC';
      v_p1 := v_unlock + make_interval(hours => c.phase1_hours);
      update public.cohort_projects set unlock_at = v_unlock, phase1_ends_at = v_p1,
        phase2_ends_at = v_p1 + make_interval(hours => c.phase2_hours) where id = r.id;
      v_cursor := public.next_project_day(v_day + 1, c.id);
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $$;

create function public.admin_add_course_to_cohort(p_cohort uuid, p_course uuid, p_start date default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_start date; v_id uuid;
begin
  perform public.require_admin();
  select coalesce(p_start, start_date) into v_start from public.cohorts where id = p_cohort;
  if v_start is null then raise exception 'cohort not found' using errcode = 'P0002'; end if;
  insert into public.cohort_courses (cohort_id, course_id, course_start_date) values (p_cohort, p_course, v_start) returning id into v_id;
  perform public.schedule_cohort_course(v_id);
  return v_id;
end $$;

create function public.admin_set_course_start(p_cc uuid, p_start date) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  update public.cohort_courses set course_start_date = p_start where id = p_cc;
  perform public.schedule_cohort_course(p_cc);
end $$;

-- Hand-editing dates locks them so later rescheduling does not overwrite them (5.3).
create function public.admin_set_project_dates(p_cp uuid, p_unlock timestamptz, p_phase1 timestamptz, p_phase2 timestamptz) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  if not (p_unlock < p_phase1 and p_phase1 < p_phase2) then
    raise exception 'dates must be in order: unlock, then Phase 1 end, then Phase 2 end' using errcode = '23514';
  end if;
  update public.cohort_projects set unlock_at = p_unlock, phase1_ends_at = p_phase1, phase2_ends_at = p_phase2, dates_locked = true where id = p_cp;
  if not found then raise exception 'cohort project not found' using errcode = 'P0002'; end if;
end $$;

create function public.admin_unlock_project_dates(p_cp uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  update public.cohort_projects set dates_locked = false where id = p_cp;
end $$;

-- Adds a holiday; with p_shift, later unlocked-by-hand-free projects move to the next project day (5.5).
-- A global holiday (null cohort) shifts every cohort that has not been archived.
create function public.admin_add_holiday(p_cohort uuid, p_date date, p_label text, p_shift boolean default false) returns integer
language plpgsql security definer set search_path = public as $$
declare v_moved integer := 0; r record;
begin
  perform public.require_admin();
  insert into public.holidays (cohort_id, date, label) values (p_cohort, p_date, p_label);
  if p_shift then
    for r in select cc.id from public.cohort_courses cc join public.cohorts c on c.id = cc.cohort_id
             where c.status <> 'COMPLETED' and (p_cohort is null or cc.cohort_id = p_cohort) loop
      v_moved := v_moved + public.schedule_cohort_course(r.id, p_date);
    end loop;
  end if;
  return v_moved;
end $$;

------------------------------------------------------------------ cloning (spec 5.4)
-- Copies phase settings and the list of courses. Students, moderators, class links and events are NOT copied.
create function public.clone_cohort(p_source uuid, p_name text, p_start date, p_course_starts jsonb default '{}') returns uuid
language plpgsql security definer set search_path = public as $$
declare s public.cohorts%rowtype; v_new uuid; r record; v_cc uuid;
begin
  perform public.require_admin();
  select * into s from public.cohorts where id = p_source;
  if not found then raise exception 'source cohort not found' using errcode = 'P0002'; end if;
  insert into public.cohorts (name, start_date, unlock_time_utc, phase1_hours, phase2_hours, cloned_from_cohort_id, status)
  values (p_name, p_start, s.unlock_time_utc, s.phase1_hours, s.phase2_hours, p_source, 'DRAFT') returning id into v_new;
  for r in select course_id from public.cohort_courses where cohort_id = p_source order by course_start_date loop
    insert into public.cohort_courses (cohort_id, course_id, course_start_date)
    values (v_new, r.course_id, coalesce((p_course_starts ->> r.course_id::text)::date, p_start)) returning id into v_cc;
    perform public.schedule_cohort_course(v_cc);
  end loop;
  return v_new;
end $$;

------------------------------------------------------------------ publish checks (spec 15)
create function public.task_publish_problems(p_task uuid) returns table (code text, message text)
language plpgsql stable security definer set search_path = public as $$
declare t public.tasks%rowtype; v_score numeric;
begin
  perform public.require_admin();
  select * into t from public.tasks where id = p_task;
  if not found then return; end if;
  if char_length(btrim(t.description_markdown)) = 0 then code := 'DESCRIPTION_MISSING'; message := 'Add a task description.'; return next; end if;
  if t.judging_mode = 'ARBITER' then
    if t.kind <> 'GIT' and cardinality(t.entry_files) = 0 then code := 'NO_ENTRY_FILES'; message := 'List the files students must provide.'; return next; end if;
    if not exists (select 1 from public.test_cases where task_id = p_task) then code := 'NO_TEST_CASES'; message := 'Add at least one test case.'; return next; end if;
    select validated_score into v_score from public.task_reference_solutions where task_id = p_task;
    if v_score is distinct from 100 then
      code := 'REFERENCE_NOT_VALIDATED';
      message := 'The reference solution must score 100 against the test cases. Running it requires Arbiter, which is not connected yet.';
      return next;
    end if;
  else
    if not exists (select 1 from public.rubric_criteria where task_id = p_task) then code := 'NO_RUBRIC'; message := 'Add at least one rubric criterion.'; return next; end if;
  end if;
end $$;

create function public.project_publish_problems(p_project uuid) returns table (code text, message text)
language plpgsql stable security definer set search_path = public as $$
declare p public.projects%rowtype;
begin
  perform public.require_admin();
  select * into p from public.projects where id = p_project;
  if not found then return; end if;
  if p.repo_name is null then code := 'REPO_NAME_MISSING'; message := 'Set the repository name students will use.'; return next; end if;
  if not exists (select 1 from public.tasks where project_id = p_project and status = 'PUBLISHED') then
    code := 'NO_PUBLISHED_TASK'; message := 'Publish at least one task.'; return next;
  end if;
end $$;

create function public.course_publish_problems(p_course uuid) returns table (code text, message text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_admin();
  if not exists (select 1 from public.projects where course_id = p_course and status = 'PUBLISHED') then
    code := 'NO_PUBLISHED_PROJECT'; message := 'Publish at least one project.'; return next;
  end if;
end $$;

create function public.cohort_publish_problems(p_cohort uuid) returns table (code text, message text)
language plpgsql stable security definer set search_path = public as $$
declare r record;
begin
  perform public.require_admin();
  if not exists (select 1 from public.cohort_courses where cohort_id = p_cohort) then
    code := 'NO_COURSES'; message := 'Add at least one course to the cohort.'; return next; return;
  end if;
  for r in select cc.id, c.name, c.status from public.cohort_courses cc join public.courses c on c.id = cc.course_id where cc.cohort_id = p_cohort loop
    if r.status <> 'PUBLISHED' then code := 'COURSE_NOT_PUBLISHED'; message := r.name || ' is not published.'; return next; end if;
    if exists (select 1 from public.projects p where p.course_id = (select course_id from public.cohort_courses where id = r.id) and p.status = 'PUBLISHED'
               and not exists (select 1 from public.cohort_projects cp where cp.cohort_course_id = r.id and cp.project_id = p.id)) then
      code := 'PROJECTS_NOT_SCHEDULED'; message := r.name || ' has projects without dates. Re-run the schedule.'; return next;
    end if;
  end loop;
end $$;

create function public.raise_if_blocked(p_problems text) returns void language plpgsql as $$
begin
  if p_problems is not null and p_problems <> '' then
    raise exception 'PUBLISH_BLOCKED' using errcode = 'PB001', detail = p_problems;
  end if;
end $$;

create function public.publish_task(p_task uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.raise_if_blocked((select string_agg(code || ': ' || message, E'\n') from public.task_publish_problems(p_task)));
  update public.tasks set status = 'PUBLISHED' where id = p_task;
end $$;
create function public.publish_project(p_project uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.raise_if_blocked((select string_agg(code || ': ' || message, E'\n') from public.project_publish_problems(p_project)));
  update public.projects set status = 'PUBLISHED' where id = p_project;
end $$;
create function public.publish_course(p_course uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.raise_if_blocked((select string_agg(code || ': ' || message, E'\n') from public.course_publish_problems(p_course)));
  update public.courses set status = 'PUBLISHED' where id = p_course;
end $$;
create function public.publish_cohort(p_cohort uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.raise_if_blocked((select string_agg(code || ': ' || message, E'\n') from public.cohort_publish_problems(p_cohort)));
  update public.cohorts set status = 'ACTIVE' where id = p_cohort;
end $$;
create function public.archive_cohort(p_cohort uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  update public.cohorts set status = 'COMPLETED' where id = p_cohort;
end $$;

create function public.reorder_projects(p_course uuid, p_ids uuid[]) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  if (select count(*) from public.projects where course_id = p_course) <> cardinality(p_ids)
     or exists (select 1 from unnest(p_ids) i where not exists (select 1 from public.projects where id = i and course_id = p_course)) then
    raise exception 'the list must contain exactly the course projects' using errcode = '23514';
  end if;
  update public.projects p set sequence_no = o.n from unnest(p_ids) with ordinality as o (id, n) where p.id = o.id;
end $$;
create function public.reorder_tasks(p_project uuid, p_ids uuid[]) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  if (select count(*) from public.tasks where project_id = p_project) <> cardinality(p_ids)
     or exists (select 1 from unnest(p_ids) i where not exists (select 1 from public.tasks where id = i and project_id = p_project)) then
    raise exception 'the list must contain exactly the project tasks' using errcode = '23514';
  end if;
  update public.tasks t set sequence_no = o.n from unnest(p_ids) with ordinality as o (id, n) where t.id = o.id;
end $$;

------------------------------------------------------------------ student-facing reads (spec 5.6, 18)
-- Curriculum: unlocked projects in full, locked ones show only title and unlock time.
create function public.my_curriculum(p_cc uuid) returns table (project_id uuid, sequence_no integer, title text, summary text, unlock_at timestamptz, unlocked boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.sequence_no, p.title, case when cp.unlock_at <= now() then p.summary end, cp.unlock_at, cp.unlock_at <= now()
  from public.cohort_projects cp join public.projects p on p.id = cp.project_id
  where cp.cohort_course_id = p_cc and p.status = 'PUBLISHED'
    and (public.is_admin() or public.moderates_cohort_course(p_cc) or public.student_in_active_cohort_course(p_cc))
  order by p.sequence_no
$$;

-- Test cases a student may see, with hidden ones removed on the server (spec 18).
create function public.get_task_test_cases(p_task uuid) returns table (id uuid, name text, kind public.task_kind, input_spec jsonb, expected_spec jsonb, sort_order integer)
language sql stable security definer set search_path = public as $$
  select tc.id, tc.name, tc.kind, tc.input_spec, tc.expected_spec, tc.sort_order
  from public.test_cases tc join public.tasks t on t.id = tc.task_id
  where tc.task_id = p_task and public.can_read_task(p_task)
    and (public.is_admin() or t.show_test_cases = 'ALL' or (t.show_test_cases = 'SAMPLES_ONLY' and tc.is_visible))
  order by tc.sort_order, tc.name
$$;

------------------------------------------------------------------ privileges
revoke all on all functions in schema public from public;
grant execute on function
  public.is_admin(), public.auth_role(), public.is_cohort_member(uuid), public.moderates_cohort_course(uuid), public.moderates_cohort(uuid),
  public.moderates_student(uuid), public.can_access_cohort_course(uuid), public.can_access_course(uuid),
  public.cohort_is_active(uuid), public.student_in_active_cohort_course(uuid), public.can_read_project(uuid), public.can_read_task(uuid),
  public.next_project_day(date, uuid), public.require_admin(),
  public.schedule_cohort_course(uuid, date), public.admin_add_course_to_cohort(uuid, uuid, date), public.admin_set_course_start(uuid, date),
  public.admin_set_project_dates(uuid, timestamptz, timestamptz, timestamptz), public.admin_unlock_project_dates(uuid),
  public.admin_add_holiday(uuid, date, text, boolean), public.clone_cohort(uuid, text, date, jsonb),
  public.task_publish_problems(uuid), public.project_publish_problems(uuid), public.course_publish_problems(uuid), public.cohort_publish_problems(uuid),
  public.publish_task(uuid), public.publish_project(uuid), public.publish_course(uuid), public.publish_cohort(uuid), public.archive_cohort(uuid),
  public.reorder_projects(uuid, uuid[]), public.reorder_tasks(uuid, uuid[]), public.my_curriculum(uuid), public.get_task_test_cases(uuid)
  to authenticated, service_role;
grant execute on function public.raise_if_blocked(text) to authenticated, service_role;

grant select, insert, update, delete on public.projects, public.tasks, public.test_cases, public.rubric_criteria,
  public.task_reference_solutions, public.cohort_projects, public.holidays, public.calendar_events to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

------------------------------------------------------------------ Row Level Security
alter table public.projects enable row level security;
alter table public.tasks enable row level security;
alter table public.test_cases enable row level security;
alter table public.rubric_criteria enable row level security;
alter table public.task_reference_solutions enable row level security;
alter table public.cohort_projects enable row level security;
alter table public.holidays enable row level security;
alter table public.calendar_events enable row level security;

create policy projects_select on public.projects for select to authenticated using (public.can_read_project(id));
create policy projects_admin_write on public.projects for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy tasks_select on public.tasks for select to authenticated using (public.can_read_task(id));
create policy tasks_admin_write on public.tasks for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Test cases hold hidden expected values: admins only. Students use get_task_test_cases().
create policy test_cases_admin on public.test_cases for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy reference_admin on public.task_reference_solutions for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Rubrics: admins, and moderators of the course (peer access arrives with review links in Phase 3).
create policy rubric_select on public.rubric_criteria for select to authenticated using (
  public.is_admin() or exists (
    select 1 from public.tasks t join public.projects p on p.id = t.project_id join public.cohort_courses cc on cc.course_id = p.course_id
    where t.id = rubric_criteria.task_id and t.status = 'PUBLISHED' and public.moderates_cohort_course(cc.id)));
create policy rubric_admin_write on public.rubric_criteria for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy cohort_projects_select on public.cohort_projects for select to authenticated
  using (public.is_admin() or public.moderates_cohort_course(cohort_course_id) or public.student_in_active_cohort_course(cohort_course_id));
create policy cohort_projects_admin_write on public.cohort_projects for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy holidays_select on public.holidays for select to authenticated
  using (public.is_admin() or cohort_id is null or public.is_cohort_member(cohort_id) or public.moderates_cohort(cohort_id));
create policy holidays_admin_write on public.holidays for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy calendar_events_select on public.calendar_events for select to authenticated using (
  public.is_admin() or (public.cohort_is_active(cohort_id) and (
    (cohort_course_id is null and public.is_cohort_member(cohort_id))
    or (cohort_course_id is not null and public.can_access_cohort_course(cohort_course_id)))));
create policy calendar_events_admin_write on public.calendar_events for all to authenticated using (public.is_admin()) with check (public.is_admin());
