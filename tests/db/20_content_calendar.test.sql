\set ON_ERROR_STOP on

create function test.dates(p_cohort uuid, p_course uuid) returns text language sql stable as $$
  select string_agg(to_char(cp.unlock_at at time zone 'UTC', 'Dy YYYY-MM-DD'), ',' order by p.sequence_no)
  from public.cohort_projects cp join public.cohort_courses cc on cc.id = cp.cohort_course_id join public.projects p on p.id = cp.project_id
  where cc.cohort_id = p_cohort and cc.course_id = p_course $$;
grant execute on function test.dates(uuid, uuid) to public;
create function test.problems(p_sql text) returns text language plpgsql as $$
declare r text; begin execute 'select string_agg(code, '','' order by code) from (' || p_sql || ') q' into r; return coalesce(r, ''); end $$;
grant execute on function test.problems(text) to public;

-- fixtures: courses SA (3 projects), SB (2 projects), SP (publish flow)
insert into public.courses (id, name, slug, runtime_stack) values
  ('d1000000-0000-0000-0000-000000000001', 'Sched A', 'sched-a', 'NODE_BACKEND'), ('d1000000-0000-0000-0000-000000000002', 'Sched B', 'sched-b', 'FRONTEND_PLAIN'), ('d1000000-0000-0000-0000-000000000003', 'Publish Flow', 'publish-flow', 'NODE_BACKEND');
insert into public.projects (id, course_id, title, slug, summary) values
  ('a1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'A One', 'a-one', 's1'), ('a1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'A Two', 'a-two', 's2'), ('a1000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'A Three', 'a-three', 's3'),
  ('a1000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000002', 'B One', 'b-one', 's4'), ('a1000000-0000-0000-0000-000000000005', 'd1000000-0000-0000-0000-000000000002', 'B Two', 'b-two', 's5');

select test.eq((select string_agg(sequence_no::text, ',' order by sequence_no) from public.projects where course_id = 'd1000000-0000-0000-0000-000000000001'), '1,2,3', 'project sequence numbers are assigned automatically');

begin; reset role;
insert into public.cohorts (id, name, start_date) values ('e1000000-0000-0000-0000-000000000017', 'K17', '2026-12-06');  -- a Sunday
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.admin_add_course_to_cohort('e1000000-0000-0000-0000-000000000017', 'd1000000-0000-0000-0000-000000000001');
select test.eq(test.dates('e1000000-0000-0000-0000-000000000017', 'd1000000-0000-0000-0000-000000000001'), 'Mon 2026-12-07,Tue 2026-12-08,Wed 2026-12-09', 'vector 17: Sunday start schedules Monday, Tuesday, Wednesday');
select test.eq((select to_char(unlock_at at time zone 'UTC', 'HH24:MI') from public.cohort_projects limit 1), '05:00', 'projects unlock at 05:00 UTC');
rollback;

begin; reset role;
insert into public.cohorts (id, name, start_date) values ('e1000000-0000-0000-0000-000000000018', 'K18', '2026-12-06');
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.admin_add_holiday('e1000000-0000-0000-0000-000000000018', '2026-12-08', 'Holiday', false);   -- Tuesday
select public.admin_add_course_to_cohort('e1000000-0000-0000-0000-000000000018', 'd1000000-0000-0000-0000-000000000001');
select test.eq(test.dates('e1000000-0000-0000-0000-000000000018', 'd1000000-0000-0000-0000-000000000001'), 'Mon 2026-12-07,Wed 2026-12-09,Thu 2026-12-10', 'vector 18: a Tuesday holiday gives Monday, Wednesday, Thursday');
rollback;

begin; reset role;
insert into public.cohorts (id, name, start_date) values ('e1000000-0000-0000-0000-000000000019', 'K19', '2026-12-11');  -- a Friday
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.admin_add_course_to_cohort('e1000000-0000-0000-0000-000000000019', 'd1000000-0000-0000-0000-000000000002');
select test.eq((select to_char(unlock_at at time zone 'UTC', 'Dy HH24:MI') from public.cohort_projects where project_id = 'a1000000-0000-0000-0000-000000000004'), 'Fri 05:00', 'vector 19: Friday project unlocks Friday 05:00');
select test.eq((select to_char(phase1_ends_at at time zone 'UTC', 'Dy HH24:MI') from public.cohort_projects where project_id = 'a1000000-0000-0000-0000-000000000004'), 'Sat 05:00', 'vector 19: Phase 1 ends Saturday 05:00');
select test.eq((select to_char(phase2_ends_at at time zone 'UTC', 'Dy HH24:MI') from public.cohort_projects where project_id = 'a1000000-0000-0000-0000-000000000004'), 'Mon 05:00', 'vector 19: Phase 2 ends Monday 05:00');
select test.eq((select to_char(unlock_at at time zone 'UTC', 'Dy HH24:MI') from public.cohort_projects where project_id = 'a1000000-0000-0000-0000-000000000005'), 'Mon 05:00', 'vector 19: the next project unlocks Monday');
rollback;

begin; reset role;
insert into public.cohorts (id, name, start_date) values ('e1000000-0000-0000-0000-000000000020', 'K20', '2026-12-07');
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.admin_add_course_to_cohort('e1000000-0000-0000-0000-000000000020', 'd1000000-0000-0000-0000-000000000001');
select public.admin_add_course_to_cohort('e1000000-0000-0000-0000-000000000020', 'd1000000-0000-0000-0000-000000000002', '2026-12-14');
select test.eq(test.dates('e1000000-0000-0000-0000-000000000020', 'd1000000-0000-0000-0000-000000000001'), 'Mon 2026-12-07,Tue 2026-12-08,Wed 2026-12-09', 'vector 20: first course scheduled from its own start');
select test.eq(test.dates('e1000000-0000-0000-0000-000000000020', 'd1000000-0000-0000-0000-000000000002'), 'Mon 2026-12-14,Tue 2026-12-15', 'vector 20: second course scheduled separately from its own start');
select test.eq((select count(*) from public.cohort_projects cp join public.cohort_courses cc on cc.id = cp.cohort_course_id where cc.cohort_id = 'e1000000-0000-0000-0000-000000000020'), 5::bigint, 'each cohort course has its own cohort projects');
rollback;


begin; reset role;
insert into public.cohorts (id, name, start_date) values ('e1000000-0000-0000-0000-000000000021', 'K21', '2026-12-07');
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.admin_add_course_to_cohort('e1000000-0000-0000-0000-000000000021', 'd1000000-0000-0000-0000-000000000001');
select test.eq(public.admin_add_holiday('e1000000-0000-0000-0000-000000000021', '2026-12-08', 'Mid-week holiday', true), 2, 'shift later projects reports how many moved');
select test.eq(test.dates('e1000000-0000-0000-0000-000000000021', 'd1000000-0000-0000-0000-000000000001'), 'Mon 2026-12-07,Wed 2026-12-09,Thu 2026-12-10', 'shift later projects moves later projects to the next project day');
rollback;

begin; reset role;
insert into public.cohorts (id, name, start_date) values ('e1000000-0000-0000-0000-000000000022', 'K22', '2026-12-07');
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.admin_add_course_to_cohort('e1000000-0000-0000-0000-000000000022', 'd1000000-0000-0000-0000-000000000001');
select public.admin_set_project_dates((select id from public.cohort_projects where project_id = 'a1000000-0000-0000-0000-000000000002' and cohort_course_id in (select id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000022')),
  '2026-12-11 05:00+00', '2026-12-12 05:00+00', '2026-12-14 05:00+00');
select test.eq((select dates_locked from public.cohort_projects where project_id = 'a1000000-0000-0000-0000-000000000002' and cohort_course_id in (select id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000022')), true, 'hand-editing dates locks them');
select public.admin_set_course_start((select id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000022'), '2026-12-14');
select test.eq((select to_char(unlock_at at time zone 'UTC', 'Dy YYYY-MM-DD') from public.cohort_projects where project_id = 'a1000000-0000-0000-0000-000000000002' and cohort_course_id in (select id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000022')), 'Fri 2026-12-11', 'rescheduling keeps hand-edited dates');
select test.eq((select to_char(unlock_at at time zone 'UTC', 'Dy YYYY-MM-DD') from public.cohort_projects where project_id = 'a1000000-0000-0000-0000-000000000001' and cohort_course_id in (select id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000022')), 'Mon 2026-12-14', 'rescheduling still moves unlocked projects');
select test.throws($$select public.admin_set_project_dates((select id from public.cohort_projects limit 1), '2026-12-11 05:00+00', '2026-12-10 05:00+00', '2026-12-14 05:00+00')$$, '23514', 'dates must be in order');
rollback;


begin; reset role;
insert into public.cohorts (id, name, start_date, phase1_hours, phase2_hours) values ('e1000000-0000-0000-0000-000000000023', 'K23', '2026-12-07', 30, 50);
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.admin_add_course_to_cohort('e1000000-0000-0000-0000-000000000023', 'd1000000-0000-0000-0000-000000000001');
select public.admin_add_course_to_cohort('e1000000-0000-0000-0000-000000000023', 'd1000000-0000-0000-0000-000000000002');
reset role;
insert into public.cohort_members (cohort_id, user_id, member_role) values ('e1000000-0000-0000-0000-000000000023', 'c0000000-0000-0000-0000-000000000001', 'STUDENT');
insert into public.enrollments (student_id, cohort_course_id) select 'c0000000-0000-0000-0000-000000000001', id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000023' and course_id = 'd1000000-0000-0000-0000-000000000001';
insert into public.moderator_assignments (moderator_id, cohort_course_id) select 'b0000000-0000-0000-0000-000000000001', id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000023' and course_id = 'd1000000-0000-0000-0000-000000000001';
insert into public.calendar_events (cohort_id, title, starts_at, ends_at) values ('e1000000-0000-0000-0000-000000000023', 'Kickoff', '2026-12-07 09:00+00', '2026-12-07 10:00+00');
update public.cohort_projects set class_link_url = 'https://meet.example/class' where cohort_course_id in (select id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000023');
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.clone_cohort('e1000000-0000-0000-0000-000000000023', 'K23 clone', '2027-01-04', '{"d1000000-0000-0000-0000-000000000002": "2027-01-11"}');
reset role;
select test.eq((select cloned_from_cohort_id from public.cohorts where name = 'K23 clone'), 'e1000000-0000-0000-0000-000000000023'::uuid, 'clone records cloned_from_cohort_id');
select test.eq((select status::text from public.cohorts where name = 'K23 clone'), 'DRAFT', 'clone is saved as a draft');
select test.eq((select phase1_hours || '/' || phase2_hours from public.cohorts where name = 'K23 clone'), '30/50', 'clone keeps the phase settings');
select test.eq((select count(*) from public.cohort_courses where cohort_id = (select id from public.cohorts where name = 'K23 clone')), 2::bigint, 'clone copies the list of courses');
select test.eq(test.dates((select id from public.cohorts where name = 'K23 clone'), 'd1000000-0000-0000-0000-000000000001'), 'Mon 2027-01-04,Tue 2027-01-05,Wed 2027-01-06', 'clone schedules from the new start date');
select test.eq(test.dates((select id from public.cohorts where name = 'K23 clone'), 'd1000000-0000-0000-0000-000000000002'), 'Mon 2027-01-11,Tue 2027-01-12', 'a course can have a different start date in the clone');
select test.eq((select count(*) from public.cohort_members where cohort_id = (select id from public.cohorts where name = 'K23 clone')), 0::bigint, 'clone does not copy students');
select test.eq((select count(*) from public.moderator_assignments ma join public.cohort_courses cc on cc.id = ma.cohort_course_id where cc.cohort_id = (select id from public.cohorts where name = 'K23 clone')), 0::bigint, 'clone does not copy moderator assignments');
select test.eq((select count(*) from public.calendar_events where cohort_id = (select id from public.cohorts where name = 'K23 clone')), 0::bigint, 'clone does not copy calendar events');
select test.eq((select count(*) from public.cohort_projects cp join public.cohort_courses cc on cc.id = cp.cohort_course_id where cc.cohort_id = (select id from public.cohorts where name = 'K23 clone') and cp.class_link_url is not null), 0::bigint, 'clone does not copy class links');
rollback;

begin; reset role;
select test.as_user('c0000000-0000-0000-0000-000000000001');
select test.throws($$select public.admin_add_holiday(null, '2026-12-25', 'Christmas', false)$$, '42501', 'students cannot add holidays');
select test.throws($$select public.clone_cohort('e1000000-0000-0000-0000-000000000023', 'x', '2027-01-04')$$, '42501', 'students cannot clone cohorts');
select test.as_user('b0000000-0000-0000-0000-000000000001');
select test.throws($$select public.publish_cohort('e1000000-0000-0000-0000-000000000023')$$, '42501', 'moderators cannot publish cohorts');
rollback;


begin; reset role;
insert into public.projects (id, course_id, title, slug, summary, repo_name) values ('a1000000-0000-0000-0000-000000000010', 'd1000000-0000-0000-0000-000000000003', 'Publish P', 'publish-p', 'visible summary', 'publish-p');
insert into public.tasks (id, project_id, title, description_markdown, kind, judging_mode, language_runtime, entry_files, show_test_cases) values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000010', 'Peer task', 'Do the thing', 'FUNCTION', 'PEER', 'NODE', '{}', 'ALL'),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000010', 'Arbiter task', 'Make add()', 'FUNCTION', 'ARBITER', 'NODE', '{src/add.js}', 'SAMPLES_ONLY');
select test.as_user('a0000000-0000-0000-0000-000000000001');
select test.eq(test.problems($$select * from public.task_publish_problems('a2000000-0000-0000-0000-000000000001')$$), 'NO_RUBRIC', 'a peer task without rubric criteria is blocked');
select test.throws($$select public.publish_task('a2000000-0000-0000-0000-000000000001')$$, 'PB001', 'publishing a blocked task raises PUBLISH_BLOCKED');
insert into public.rubric_criteria (task_id, label) values ('a2000000-0000-0000-0000-000000000001', 'Correctness');
select public.publish_task('a2000000-0000-0000-0000-000000000001');
select test.eq((select status::text from public.tasks where id = 'a2000000-0000-0000-0000-000000000001'), 'PUBLISHED', 'a task with a rubric publishes');
select test.eq(test.problems($$select * from public.task_publish_problems('a2000000-0000-0000-0000-000000000002')$$), 'NO_TEST_CASES,REFERENCE_NOT_VALIDATED', 'an arbiter task needs test cases and a validated reference');
insert into public.test_cases (task_id, name, kind, input_spec, expected_spec, is_visible, sort_order) values
  ('a2000000-0000-0000-0000-000000000002', 'sample', 'FUNCTION', '{"function":"add","args":[2,3]}', '{"returns":5}', true, 1),
  ('a2000000-0000-0000-0000-000000000002', 'hidden', 'FUNCTION', '{"function":"add","args":[40,2]}', '{"returns":"SECRET42"}', false, 2);
select test.eq(test.problems($$select * from public.task_publish_problems('a2000000-0000-0000-0000-000000000002')$$), 'REFERENCE_NOT_VALIDATED', 'with test cases, only the reference validation remains');
insert into public.task_reference_solutions (task_id, files, validated_score) values ('a2000000-0000-0000-0000-000000000002', '{"src/add.js":"exports.add=(a,b)=>a+b"}', 100);
select test.eq((select validated_score from public.task_reference_solutions where task_id = 'a2000000-0000-0000-0000-000000000002'), null, 'admins cannot self-certify a reference solution');
reset role;
update public.task_reference_solutions set validated_score = 100, validated_at = now() where task_id = 'a2000000-0000-0000-0000-000000000002';   -- what Arbiter will do
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.publish_task('a2000000-0000-0000-0000-000000000002');
select test.eq((select status::text from public.tasks where id = 'a2000000-0000-0000-0000-000000000002'), 'PUBLISHED', 'an arbiter task publishes once the reference scored 100');
update public.test_cases set weight = 2 where task_id = 'a2000000-0000-0000-0000-000000000002' and name = 'sample';
select test.eq((select validated_score from public.task_reference_solutions where task_id = 'a2000000-0000-0000-0000-000000000002'), null, 'changing a test case invalidates the reference validation');
select test.throws($$update public.tasks set status = 'PUBLISHED' where id = 'a2000000-0000-0000-0000-000000000002' and false; insert into public.tasks (project_id, title, kind, judging_mode, language_runtime, status) values ('a1000000-0000-0000-0000-000000000010', 'Sneaky', 'FUNCTION', 'PEER', 'NODE', 'PUBLISHED')$$, '42501', 'status cannot be set to PUBLISHED directly');
select test.throws($$insert into public.test_cases (task_id, name, kind) values ('a2000000-0000-0000-0000-000000000001', 'wrong kind', 'HTTP')$$, '23514', 'test case kind must match the task kind');
select test.throws($$insert into public.tasks (project_id, title, kind, judging_mode, language_runtime) values ('a1000000-0000-0000-0000-000000000010', 'Bad runtime', 'FUNCTION', 'PEER', 'BROWSER')$$, '23514', 'task kind and runtime must be compatible');
select public.publish_project('a1000000-0000-0000-0000-000000000010');
select public.publish_course('d1000000-0000-0000-0000-000000000003');
select test.eq((select status::text from public.courses where id = 'd1000000-0000-0000-0000-000000000003'), 'PUBLISHED', 'project then course publish once their checks pass');
select test.throws($$update public.courses set status = 'PUBLISHED' where id = 'd1000000-0000-0000-0000-000000000001'$$, '42501', 'courses cannot be published by a direct update');
select test.eq(test.problems($$select * from public.project_publish_problems('a1000000-0000-0000-0000-000000000001')$$), 'NO_PUBLISHED_TASK,REPO_NAME_MISSING', 'a project needs a repo name and a published task');
select test.eq(test.problems($$select * from public.course_publish_problems('d1000000-0000-0000-0000-000000000001')$$), 'NO_PUBLISHED_PROJECT', 'a course needs a published project');

-- cohort publish
reset role;
insert into public.cohorts (id, name, start_date) values ('e1000000-0000-0000-0000-000000000024', 'K24', '2026-12-07'), ('e1000000-0000-0000-0000-000000000025', 'K25', '2026-12-07'), ('e1000000-0000-0000-0000-000000000026', 'K26', '2026-12-07');
select test.as_user('a0000000-0000-0000-0000-000000000001');
select test.eq(test.problems($$select * from public.cohort_publish_problems('e1000000-0000-0000-0000-000000000026')$$), 'NO_COURSES', 'a cohort without courses cannot be published');
select public.admin_add_course_to_cohort('e1000000-0000-0000-0000-000000000025', 'd1000000-0000-0000-0000-000000000001');
select test.eq(test.problems($$select * from public.cohort_publish_problems('e1000000-0000-0000-0000-000000000025')$$), 'COURSE_NOT_PUBLISHED', 'a cohort with an unpublished course cannot be published');
select public.admin_add_course_to_cohort('e1000000-0000-0000-0000-000000000024', 'd1000000-0000-0000-0000-000000000003');
select test.throws($$update public.cohorts set status = 'ACTIVE' where id = 'e1000000-0000-0000-0000-000000000024'$$, '42501', 'cohorts cannot be activated by a direct update');

-- enrol student 1 and assign moderator 1, then check visibility before and after publishing
reset role;
insert into public.cohort_members (cohort_id, user_id, member_role) values ('e1000000-0000-0000-0000-000000000024', 'c0000000-0000-0000-0000-000000000001', 'STUDENT');
insert into public.enrollments (student_id, cohort_course_id) select 'c0000000-0000-0000-0000-000000000001', id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000024';
insert into public.moderator_assignments (moderator_id, cohort_course_id) select 'b0000000-0000-0000-0000-000000000001', id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000024';
insert into public.projects (id, course_id, title, slug, summary, repo_name, status) values ('a1000000-0000-0000-0000-000000000011', 'd1000000-0000-0000-0000-000000000003', 'Locked P', 'locked-p', 'secret summary', 'locked-p', 'PUBLISHED');
insert into public.holidays (cohort_id, date, label) values (null, '2026-12-25', 'Global holiday'), ('e1000000-0000-0000-0000-000000000025', '2026-12-28', 'Other cohort holiday');
insert into public.calendar_events (id, cohort_id, cohort_course_id, title, starts_at, ends_at) values
  ('f1000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000024', null, 'Cohort-wide event', '2026-12-09 09:00+00', '2026-12-09 10:00+00'),
  ('f1000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000025', null, 'Other cohort event', '2026-12-09 09:00+00', '2026-12-09 10:00+00');
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.schedule_cohort_course((select id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000024'));
reset role;
update public.cohort_projects set unlock_at = now() - interval '2 days', phase1_ends_at = now() - interval '1 day', phase2_ends_at = now() + interval '1 day' where project_id = 'a1000000-0000-0000-0000-000000000010';
update public.cohort_projects set unlock_at = now() + interval '30 days', phase1_ends_at = now() + interval '31 days', phase2_ends_at = now() + interval '33 days' where project_id = 'a1000000-0000-0000-0000-000000000011';

select test.as_user('c0000000-0000-0000-0000-000000000001');
select test.eq(test.count('select 1 from public.projects'), 0::bigint, 'students see no projects while the cohort is a draft');
select test.eq(test.count('select 1 from public.cohort_projects'), 0::bigint, 'students see no schedule while the cohort is a draft');
select test.eq(test.count('select 1 from public.calendar_events'), 0::bigint, 'students see no events while the cohort is a draft');
reset role;
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.publish_cohort('e1000000-0000-0000-0000-000000000024');
select test.eq((select status::text from public.cohorts where id = 'e1000000-0000-0000-0000-000000000024'), 'ACTIVE', 'a valid cohort publishes and becomes ACTIVE');

select test.as_user('c0000000-0000-0000-0000-000000000001');
select test.eq(test.count('select 1 from public.projects'), 1::bigint, 'students see only unlocked projects');
select test.eq(test.count('select 1 from public.tasks'), 2::bigint, 'students see only the published tasks of unlocked projects');
select test.eq(test.count($$select 1 from public.tasks where status = 'DRAFT'$$), 0::bigint, 'students never see draft tasks');
select test.eq(test.count('select 1 from public.my_curriculum((select id from public.cohort_courses where cohort_id = ''e1000000-0000-0000-0000-000000000024''))'), 2::bigint, 'curriculum lists unlocked and locked projects');
select test.eq((select summary from public.my_curriculum((select id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000024')) where title = 'Locked P'), null, 'a locked project reveals no summary');
select test.eq((select unlocked from public.my_curriculum((select id from public.cohort_courses where cohort_id = 'e1000000-0000-0000-0000-000000000024')) where title = 'Locked P'), false, 'a locked project is marked locked and keeps its unlock date');
select test.eq(test.count('select 1 from public.test_cases'), 0::bigint, 'students cannot read the test_cases table');
select test.eq(test.count('select 1 from public.rubric_criteria'), 0::bigint, 'students cannot read rubric criteria');
select test.eq(test.count('select 1 from public.task_reference_solutions'), 0::bigint, 'students cannot read reference solutions');
select test.eq(test.count($$select 1 from public.get_task_test_cases('a2000000-0000-0000-0000-000000000002') where expected_spec::text like '%SECRET42%'$$), 0::bigint, 'hidden test case values never reach students');
select test.eq(test.count($$select 1 from public.get_task_test_cases('a2000000-0000-0000-0000-000000000002')$$), 1::bigint, 'SAMPLES_ONLY shows only the visible case');
select test.eq(test.count($$select 1 from public.holidays$$), 1::bigint, 'students see global holidays but not other cohorts');
select test.eq(test.count($$select 1 from public.calendar_events$$), 1::bigint, 'students see their cohort events but not other cohorts');
select test.throws($$insert into public.calendar_events (cohort_id, title, starts_at, ends_at) values ('e1000000-0000-0000-0000-000000000024', 'x', now(), now() + interval '1 hour')$$, '42501', 'students cannot create events');
reset role;
update public.tasks set show_test_cases = 'NONE' where id = 'a2000000-0000-0000-0000-000000000002';
select test.as_user('c0000000-0000-0000-0000-000000000001');
select test.eq(test.count($$select 1 from public.get_task_test_cases('a2000000-0000-0000-0000-000000000002')$$), 0::bigint, 'show_test_cases NONE reveals nothing');
reset role;
update public.tasks set show_test_cases = 'ALL' where id = 'a2000000-0000-0000-0000-000000000002';
select test.as_user('c0000000-0000-0000-0000-000000000001');
select test.eq(test.count($$select 1 from public.get_task_test_cases('a2000000-0000-0000-0000-000000000002')$$), 2::bigint, 'show_test_cases ALL reveals every case to enrolled students');
select test.as_user('c0000000-0000-0000-0000-000000000002');
select test.eq(test.count('select 1 from public.projects'), 0::bigint, 'a student of another cohort cannot see the projects');
select test.eq(test.count($$select 1 from public.get_task_test_cases('a2000000-0000-0000-0000-000000000002')$$), 0::bigint, 'a student of another cohort cannot fetch test cases');

select test.as_user('b0000000-0000-0000-0000-000000000001');
select test.eq(test.count('select 1 from public.projects'), 2::bigint, 'an assigned moderator sees the published projects of the course');
select test.eq(test.count('select 1 from public.rubric_criteria'), 1::bigint, 'an assigned moderator can read rubric criteria');
select test.eq(test.count('select 1 from public.test_cases'), 0::bigint, 'moderators cannot read raw test cases');
select test.as_user('b0000000-0000-0000-0000-000000000002');
select test.eq(test.count('select 1 from public.projects'), 0::bigint, 'an unassigned moderator sees no projects');
select test.eq(test.count('select 1 from public.rubric_criteria'), 0::bigint, 'an unassigned moderator sees no rubrics');
rollback;

begin; reset role;
select test.as_user('a0000000-0000-0000-0000-000000000001');
select public.reorder_projects('d1000000-0000-0000-0000-000000000001', array['a1000000-0000-0000-0000-000000000003','a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002']::uuid[]);
select test.eq((select string_agg(slug, ',' order by sequence_no) from public.projects where course_id = 'd1000000-0000-0000-0000-000000000001'), 'a-three,a-one,a-two', 'projects can be reordered');
select test.throws($$select public.reorder_projects('d1000000-0000-0000-0000-000000000001', array['a1000000-0000-0000-0000-000000000001']::uuid[])$$, '23514', 'a reorder must list every project');
rollback;

\echo ALL PHASE 1 DATABASE TESTS PASSED
