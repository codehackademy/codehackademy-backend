# Specification v1.4 → implementation checklist

Status: ✅ done and verified in this session · 🟡 partly done / needs external setup · ⬜ later phase.
Verification legend: **DB** = Postgres 16 RLS tests, **UT** = unit tests, **E2E** = browser run against a fake Supabase (not the real one).

## Phase 0 — Foundations (this release)
| Requirement | Repo | Status |
|---|---|---|
| Five-repository structure, shared repo as submodule | all | ✅ local repos + submodules; 🟡 remote URLs to be created |
| pnpm, TypeScript, ESLint, CI workflows | all | ✅ (CI files written; not run on GitHub) |
| Supabase migrations, RLS on every table | backend | ✅ DB (55 assertions) |
| Exactly three roles, one per user; role from DB not metadata | backend/apps | ✅ DB, E2E |
| Courses and cohorts independent; cohort↔course with own start date | backend | ✅ DB |
| Moderator limited to assigned cohort courses (vector 21) | backend | ✅ DB |
| Students see only their own data | backend | ✅ DB |
| Append-only audit log; audited admin actions | backend | ✅ DB |
| Platform settings seeded with spec defaults | backend | ✅ DB (admin settings UI ⬜) |
| Invite users (Edge Function, admin only, rollback on failure) | backend + admin | ✅ UT; 🟡 not run against live Supabase |
| Student onboarding: location, IANA time zone, consent, GitHub verified via API | backend + student | ✅ UT, E2E (form); 🟡 live GitHub/Supabase untested |
| Time zones: stored UTC, shown in the viewer's zone (vector 24) | shared | ✅ UT, E2E |
| Separate sessions per app, HttpOnly host-only cookies, sign-up disabled | apps/config | ✅ configured; 🟡 verify on real domains |
| Password reset and invite links (token-hash flow) | apps/backend | 🟡 implemented; needs real email run |
| Admin: create cohort, add course, enrol via invite, assign moderators, users, interest list, audit log | admin | ✅ E2E (rendering, routing, validation); 🟡 writes untested against real DB |
| Public website transformed; interest form with real backend, honest states | public | ✅ UT; 🟡 needs Supabase env |
| Staff 2FA (optional TOTP) | apps | 🟡 enabled in config; enrolment UI ⬜ (Phase 7) |
| Real rate limiting on public form | public | 🟡 per-instance limiter; shared limiter ⬜ (Phase 7) |
| CSV student import | admin | ⬜ not yet built (carried over) |

## Phase 1 — Content and calendar
| Requirement | Repo | Status |
|---|---|---|
| Projects, tasks, test cases, rubric criteria, reference solutions (private) | backend | ✅ DB |
| `nextProjectDay` implemented once (Mon–Fri, global and cohort holidays) | backend (SQL) | ✅ DB, vectors 17–19 |
| Per-course scheduling inside a cohort; independent courses (vector 20) | backend | ✅ DB |
| Phase 1/2 deadlines from plain hours; phases run through weekends | backend | ✅ DB |
| Hand-edited dates are locked and survive rescheduling | backend + admin | ✅ DB, E2E |
| Add holiday with "shift later projects" (cohort or global) | backend + admin | ✅ DB, E2E (rendering/validation) |
| Cohort cloning: copies courses + phase settings; NOT students, moderators, class links, events | backend + admin | ✅ DB |
| Publish checks for task, project, course, cohort; direct status writes refused | backend + admin | ✅ DB |
| ARBITER task publish requires reference solution scoring 100 | backend | 🟡 enforced, but **cannot be satisfied until Arbiter (Phase 2)**; the Run button is deliberately absent |
| Test-case editor (per-kind JSON specs, comparison modes, weights, visibility) | shared + admin | ✅ UT, E2E |
| Rubric editor, project builder (details / notes / tasks), task builder | admin | ✅ E2E |
| Markdown with live preview, sanitized (no raw HTML) | shared + admin | ✅ E2E (script tag not rendered or executed) |
| Drag-and-drop **and** keyboard/touch reordering of projects and tasks | admin | ✅ buttons E2E; mouse drag implemented, not browser-tested |
| Hidden test-case values never reach students (server-side filter) | backend | ✅ DB |
| Locked projects reveal only title and unlock time to students | backend | ✅ DB (`my_curriculum`) |
| Cohort calendar (month view), holidays, events (admin) | admin | ✅ E2E; read-only grid |
| Calendar drag-to-move, FullCalendar | admin | ⬜ not built; dates are edited on the Schedule tab |
| PDF upload for projects | admin | 🟡 https link only; R2 upload ⬜ |
| Cohort project recounting | backend | ⬜ arrives with scoring (Phase 2) |
| Settings page for the seeded platform settings | admin | ⬜ |

## Later phases (not started, per instruction)
| Phase | Scope | Status |
|---|---|---|
| 1 | Projects, tasks, rubrics, test cases, holidays, project-day calculation, scheduling, cohort cloning, calendar events, publish validations | ✅ see below |
| 2 | GitHub App, preflight, pgmq, Judge0, FUNCTION/STDIO, status machine, Realtime + polling, scoring package + vectors, scheduled counting | ⬜ |
| 3 | Peer links/reviews, moderator queue, overrides, invalidation, suspension RPCs, class links | ⬜ |
| 4 | Student dashboard (full), projects, curriculum, calendar, settings, notifications, PWA | ⬜ (foundation dashboard only) |
| 5 | HTTP/BROWSER/GIT tasks, Playwright runner, React runtime, performance cases | ⬜ |
| 6 | Saturday Challenge | ⬜ |
| 7 | Security review, RLS test expansion, backups, Sentry, a11y audit | ⬜ |
| 8 | Version 2 (AI detection etc.) | ⬜ not started, by design |
