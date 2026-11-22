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
| CSV student import | admin | ⬜ Phase 1 follow-up |

## Later phases (not started, per instruction)
| Phase | Scope | Status |
|---|---|---|
| 1 | Projects, tasks, rubrics, test cases, holidays, project-day calculation, scheduling, cohort cloning, calendar events, publish validations | ⬜ |
| 2 | GitHub App, preflight, pgmq, Judge0, FUNCTION/STDIO, status machine, Realtime + polling, scoring package + vectors, scheduled counting | ⬜ |
| 3 | Peer links/reviews, moderator queue, overrides, invalidation, suspension RPCs, class links | ⬜ |
| 4 | Student dashboard (full), projects, curriculum, calendar, settings, notifications, PWA | ⬜ (foundation dashboard only) |
| 5 | HTTP/BROWSER/GIT tasks, Playwright runner, React runtime, performance cases | ⬜ |
| 6 | Saturday Challenge | ⬜ |
| 7 | Security review, RLS test expansion, backups, Sentry, a11y audit | ⬜ |
| 8 | Version 2 (AI detection etc.) | ⬜ not started, by design |
