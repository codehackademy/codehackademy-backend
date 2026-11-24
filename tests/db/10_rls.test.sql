\set ON_ERROR_STOP on
create schema test;
grant usage on schema test to public;

create function test.as_user(p_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_id::text, ''), true);
  execute 'set local role authenticated';
end $$;
create function test.as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
end $$;
create function test.count(p_sql text) returns bigint language plpgsql as $$
declare n bigint; begin execute 'select count(*) from (' || p_sql || ') q' into n; return n; end $$;
create function test.eq(p_actual anyelement, p_expected anyelement, p_msg text) returns void language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'FAIL: % (expected %, got %)', p_msg, p_expected, p_actual;
  end if;
  raise notice 'ok - %', p_msg;
end $$;
-- Run p_sql and require it to fail with the given SQLSTATE.
create function test.throws(p_sql text, p_state text, p_msg text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate = p_state then raise notice 'ok - %', p_msg; return; end if;
    raise exception 'FAIL: % (expected SQLSTATE %, got % : %)', p_msg, p_state, sqlstate, sqlerrm;
  end;
  raise exception 'FAIL: % (statement succeeded but should have failed)', p_msg;
end $$;
grant execute on all functions in schema test to public;

------------------------------------------------------------------ fixtures (as superuser)
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'admin@t.test'),
  ('b0000000-0000-0000-0000-000000000001', 'm1@t.test'),
  ('b0000000-0000-0000-0000-000000000002', 'm2@t.test'),
  ('c0000000-0000-0000-0000-000000000001', 's1@t.test'),
  ('c0000000-0000-0000-0000-000000000002', 's2@t.test'),
  ('c0000000-0000-0000-0000-000000000003', 's3@t.test');
insert into public.profiles (id, role, name, email) values
  ('a0000000-0000-0000-0000-000000000001', 'ADMIN', 'Admin One', 'admin@t.test'),
  ('b0000000-0000-0000-0000-000000000001', 'MODERATOR', 'Mod One', 'm1@t.test'),
  ('b0000000-0000-0000-0000-000000000002', 'MODERATOR', 'Mod Two', 'm2@t.test'),
  ('c0000000-0000-0000-0000-000000000001', 'STUDENT', 'Student One', 's1@t.test'),
  ('c0000000-0000-0000-0000-000000000002', 'STUDENT', 'Student Two', 's2@t.test'),
  ('c0000000-0000-0000-0000-000000000003', 'STUDENT', 'Student Three', 's3@t.test');
insert into public.courses (id, name, slug, runtime_stack) values
  ('d0000000-0000-0000-0000-000000000001', 'Frontend Engineering', 'frontend', 'FRONTEND_REACT'),
  ('d0000000-0000-0000-0000-000000000002', 'Backend Engineering', 'backend', 'NODE_BACKEND');
insert into public.cohorts (id, name, start_date) values
  ('e0000000-0000-0000-0000-000000000003', 'Cohort 3', '2026-12-07'),
  ('e0000000-0000-0000-0000-000000000004', 'Cohort 4', '2027-02-01');
insert into public.cohort_courses (id, cohort_id, course_id, course_start_date) values
  ('f0000000-0000-0000-0000-000000000031', 'e0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001', '2026-12-07'), -- C3 Frontend
  ('f0000000-0000-0000-0000-000000000032', 'e0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000002', '2026-12-07'), -- C3 Backend
  ('f0000000-0000-0000-0000-000000000041', 'e0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000001', '2027-02-01'); -- C4 Frontend
insert into public.cohort_members (cohort_id, user_id, member_role) values
  ('e0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001', 'STUDENT'),
  ('e0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000002', 'STUDENT'),
  ('e0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000003', 'STUDENT');
insert into public.enrollments (student_id, cohort_course_id) values
  ('c0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000031'),
  ('c0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000032'),
  ('c0000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000041');
-- Moderator One handles Cohort 3 FRONTEND only (spec vector 21)
insert into public.moderator_assignments (moderator_id, cohort_course_id) values
  ('b0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000031');

------------------------------------------------------------------ student isolation
begin;
select test.as_user('c0000000-0000-0000-0000-000000000001');
select test.eq(test.count('select 1 from public.profiles'), 1::bigint, 'student sees only their own profile');
select test.eq(test.count('select 1 from public.cohorts'), 1::bigint, 'student sees only their own cohort');
select test.eq(test.count('select 1 from public.cohort_courses'), 1::bigint, 'student sees only the course they are enrolled in');
select test.eq(test.count('select 1 from public.courses'), 1::bigint, 'student sees only their own course');
select test.eq(test.count('select 1 from public.enrollments'), 1::bigint, 'student sees only their own enrolment');
select test.eq(test.count('select 1 from public.cohort_members'), 1::bigint, 'student sees only their own membership row');
select test.eq(test.count('select 1 from public.moderator_assignments'), 0::bigint, 'student sees no moderator assignments');
select test.eq(test.count('select 1 from public.audit_logs'), 0::bigint, 'student cannot read audit logs');
select test.eq(test.count('select 1 from public.interest_submissions'), 0::bigint, 'student cannot read interest submissions');
select test.throws($$update public.profiles set role = 'ADMIN' where id = 'c0000000-0000-0000-0000-000000000001'$$, '42501', 'student cannot promote themselves');
select test.throws($$update public.profiles set github_username = 'someone-else' where id = 'c0000000-0000-0000-0000-000000000001'$$, '42501', 'student cannot change GitHub username directly');
select test.throws($$update public.profiles set status = 'SUSPENDED', suspension_reason = 'self' where id = 'c0000000-0000-0000-0000-000000000001'$$, '42501', 'student cannot change their own status');
select test.throws($$insert into public.cohorts (name, start_date) values ('Hack', '2027-01-01')$$, '42501', 'student cannot create cohorts');
select test.throws($$insert into public.audit_logs (action, entity_type) values ('x', 'y')$$, '42501', 'student cannot write audit logs');
update public.profiles set name = 'Renamed Student', timezone = 'Africa/Lagos' where id = 'c0000000-0000-0000-0000-000000000001';
select test.eq((select name from public.profiles where id = 'c0000000-0000-0000-0000-000000000001'), 'Renamed Student', 'student may update their own display name and time zone');
do $$ declare n int; begin
  update public.profiles set name = 'Hacked Name' where id = 'c0000000-0000-0000-0000-000000000002';
  get diagnostics n = row_count;
  perform test.eq(n, 0, 'student cannot update another student');
end $$;
do $$ declare n int; begin
  update public.settings set value = '1' where key = 'phase1_hours';
  get diagnostics n = row_count;
  perform test.eq(n, 0, 'student cannot change settings');
end $$;
select test.eq(test.count('select 1 from public.settings'), 7::bigint, 'student can read settings');
rollback;

------------------------------------------------------------------ moderator scope (spec vector 21)
begin;
select test.as_user('b0000000-0000-0000-0000-000000000001');
select test.eq(test.count('select 1 from public.cohorts'), 1::bigint, 'moderator sees only assigned cohort');
select test.eq(test.count($$select 1 from public.cohort_courses where id = 'f0000000-0000-0000-0000-000000000031'$$), 1::bigint, 'moderator sees Cohort 3 Frontend');
select test.eq(test.count($$select 1 from public.cohort_courses where id = 'f0000000-0000-0000-0000-000000000032'$$), 0::bigint, 'moderator cannot see Cohort 3 Backend');
select test.eq(test.count($$select 1 from public.cohorts where id = 'e0000000-0000-0000-0000-000000000004'$$), 0::bigint, 'moderator cannot see Cohort 4');
select test.eq(test.count($$select 1 from public.enrollments where cohort_course_id = 'f0000000-0000-0000-0000-000000000032'$$), 0::bigint, 'moderator cannot see Backend enrolments');
select test.eq(test.count($$select 1 from public.profiles where id = 'c0000000-0000-0000-0000-000000000001'$$), 1::bigint, 'moderator sees their Frontend student');
select test.eq(test.count($$select 1 from public.profiles where id in ('c0000000-0000-0000-0000-000000000002','c0000000-0000-0000-0000-000000000003')$$), 0::bigint, 'moderator cannot see Backend or Cohort 4 students');
select test.eq(test.count($$select 1 from public.courses where id = 'd0000000-0000-0000-0000-000000000002'$$), 0::bigint, 'moderator cannot see the Backend course');
select test.throws($$insert into public.courses (name, slug, runtime_stack) values ('X', 'xx', 'NODE_BACKEND')$$, '42501', 'moderator cannot create courses');
do $$ declare n int; begin
  update public.profiles set status = 'SUSPENDED', suspension_reason = 'x' where id = 'c0000000-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  perform test.eq(n, 0, 'moderators cannot suspend by direct update (audited RPC comes in Phase 3)');
end $$;
rollback;

begin;
select test.as_user('b0000000-0000-0000-0000-000000000002');
select test.eq(test.count('select 1 from public.cohorts'), 0::bigint, 'unassigned moderator sees no cohorts');
select test.eq(test.count('select 1 from public.profiles'), 1::bigint, 'unassigned moderator sees only themselves');
rollback;

------------------------------------------------------------------ admin + audit
begin;
select test.as_user('a0000000-0000-0000-0000-000000000001');
select test.eq(test.count('select 1 from public.profiles'), 6::bigint, 'admin sees every profile');
select test.eq(test.count('select 1 from public.cohorts'), 2::bigint, 'admin sees every cohort');
insert into public.cohorts (name, start_date) values ('Cohort 5', '2027-03-01');
select test.eq(test.count($$select 1 from public.audit_logs where entity_type = 'cohorts' and action = 'insert' and actor_id = 'a0000000-0000-0000-0000-000000000001'$$), 1::bigint, 'cohort creation is audited with the admin as actor');
update public.settings set value = '36' where key = 'phase1_hours';
select test.eq(test.count($$select 1 from public.audit_logs where entity_type = 'settings' and action = 'update'$$), 1::bigint, 'settings changes are audited');
select test.eq((select (after_json ->> 'value')::int from public.audit_logs where entity_type = 'settings' limit 1), 36, 'audit rows keep after-state JSON');
select test.throws($$delete from public.audit_logs$$, '42501', 'admin cannot delete audit rows (no privilege)');
select test.throws($$update public.audit_logs set action = 'tamper'$$, '42501', 'admin cannot edit audit rows');
rollback;

begin; -- even the table owner cannot rewrite history
select test.throws($$update public.audit_logs set action = 'tamper'$$, '42501', 'audit rows are immutable even for the owner');
select test.throws($$truncate public.audit_logs$$, '42501', 'audit table cannot be truncated');
rollback;

------------------------------------------------------------------ integrity rules
begin;
select test.throws($$insert into public.enrollments (student_id, cohort_course_id) values ('a0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000031')$$, '23514', 'only students can be enrolled');
select test.throws($$insert into public.enrollments (student_id, cohort_course_id) values ('c0000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000031')$$, '23514', 'student must belong to the cohort before enrolment');
select test.throws($$insert into public.moderator_assignments (moderator_id, cohort_course_id) values ('c0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000031')$$, '23514', 'only moderators can be assigned');
select test.throws($$insert into public.cohort_members (cohort_id, user_id, member_role) values ('e0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000001', 'MODERATOR')$$, '23514', 'member role must match user role');
insert into public.moderator_assignments (moderator_id, cohort_course_id) values ('b0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000041');
select test.eq(test.count($$select 1 from public.cohort_members where user_id = 'b0000000-0000-0000-0000-000000000002' and member_role = 'MODERATOR'$$), 1::bigint, 'assigning a moderator makes them a cohort member');
select test.throws($$update public.profiles set status = 'SUSPENDED' where id = 'c0000000-0000-0000-0000-000000000001'$$, '23514', 'suspension requires a reason');
select test.throws($$insert into public.cohorts (name, start_date, end_date) values ('Bad', '2027-01-10', '2027-01-01')$$, '23514', 'cohort end date cannot precede start date');
select test.throws($$insert into public.cohort_courses (cohort_id, course_id, course_start_date) values ('e0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001', '2026-12-07')$$, '23505', 'a course can be added to a cohort only once');
select test.throws($$update public.profiles set github_username = 'octocat' where id = 'c0000000-0000-0000-0000-000000000001'; update public.profiles set github_username = 'OctoCat' where id = 'c0000000-0000-0000-0000-000000000002'$$, '23505', 'GitHub usernames are unique, case-insensitively');
rollback;

------------------------------------------------------------------ public interest form
begin;
select test.as_anon();
insert into public.interest_submissions (full_name, email, country, city, programme, experience, reason, availability)
values ('Ada Obi', 'Ada@Example.com', 'Nigeria', 'Lagos', 'BACKEND_ENGINEERING', 'BEGINNER', 'I want to build real software with a serious community.', 'H10_20');
select test.throws($$insert into public.interest_submissions (full_name, email, country, city, programme, experience, reason, availability) values ('Ada Again', 'ada@example.com', 'Nigeria', 'Lagos', 'FRONTEND_ENGINEERING', 'BEGINNER', 'Second attempt with the same email address here.', 'H10_20')$$, '23505', 'the same email cannot be submitted twice (case-insensitive)');
select test.throws($$select count(*) from public.interest_submissions$$, '42501', 'anonymous visitors cannot read submissions');
select test.throws($$insert into public.profiles (id, role, name, email) values (gen_random_uuid(), 'ADMIN', 'Evil', 'e@e.co')$$, '42501', 'anonymous visitors cannot create profiles');
select test.throws($$insert into public.interest_submissions (full_name, email, country, city, programme, experience, reason, availability) values ('A', 'a@b.co', 'NG', 'Lagos', 'BACKEND_ENGINEERING', 'BEGINNER', 'too short', 'H10_20')$$, '23514', 'invalid submissions are rejected by the database');
select test.throws($$insert into public.interest_submissions (full_name, email, country, city, programme, experience, reason, availability, status) values ('Ada Obi', 'x@y.co', 'Nigeria', 'Lagos', 'BACKEND_ENGINEERING', 'BEGINNER', 'I want to build real software with a serious community.', 'H10_20', 'CONTACTED')$$, '42501', 'visitors cannot pre-set a triage status');
reset role;
select test.eq((select count(*) from public.interest_submissions), 1::bigint, 'exactly one row stored for the email');
rollback;

begin;
select test.as_user('a0000000-0000-0000-0000-000000000001');
select test.eq(test.count('select 1 from public.interest_submissions'), 0::bigint, 'admin can query interest submissions');
rollback;

\echo ALL DATABASE TESTS PASSED
