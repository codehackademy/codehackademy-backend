# Architecture, design system and setup

## Repositories (siblings in one folder)
`codehackademy` (public, codehackademy.app) · `codehackademy-student` (intranet.) · `codehackademy-admin` (admin.) ·
`codehackademy-shared` (submodule at `shared/` in the three web apps and the backend) · `codehackademy-backend` (Supabase).
Submodule URLs are relative (`../codehackademy-shared`), so create all five repos under the same GitHub organisation.
Bump the shared pin per repo by pull request (`git -C shared pull && git add shared`).

## Edge Functions and the shared submodule
Supabase's GitHub integration (Preview/branching) bundles functions from a checkout **without git submodules**, so functions never import from `shared/` directly.
`pnpm sync:shared` copies the Deno-safe files (constants, time helpers, Zod schemas) into `supabase/functions/_shared/vendor/shared/`; CI runs `pnpm check:shared` and fails if the copy drifts.
After bumping the `shared` pin: `git -C shared pull && pnpm sync:shared`, then commit both. Do not edit the vendored files by hand.
If the sibling repos are private, `actions/checkout` needs a token that can read `codehackademy-shared` (a PAT or deploy key), not the default `GITHUB_TOKEN`.

## Boundaries
- Browser/server code in the apps uses only the **anon key** with the user's session; RLS decides everything.
- Privileged work (creating auth users, GitHub verification, audit writes by services) runs in **Edge Functions** with the service-role key.
- Student code is never executed by any of these components (Judge0 arrives in Phase 2).
- Sessions: cookies `sb-student` / `sb-admin`, host-only, HttpOnly, SameSite=Lax, Secure in production.
- Roles are read from `profiles.role`, never from user-editable auth metadata. Open sign-up is off; accounts come from invitations.
- Admins are bootstrapped once with `select public.bootstrap_first_admin('email','Name')` after creating the auth user in the dashboard.

## Navigation (Phase 0)
Public: Home · About · Programmes (+2 detail pages) · Learning experience · Community · Contact · FAQ · Apply; Student sign-in button; Staff sign-in in the footer only.
Student: Dashboard (more as phases land). Admin: Dashboard · Cohorts (overview+courses | people) · Courses · Users (+invite) · Interest · Audit log. Moderator: Overview only.

## Design system (`shared/src/design`, `shared/src/ui`)
One set of Tailwind v4 tokens (orange `#FD5000`, ink, charcoal, steel, paper, line; status colours with AA-safe pairs; radii; Archivo + JetBrains Mono).
Each app sets `data-app` to adjust density: public = expressive (hard-offset "sticker" buttons, arch/pill shapes), student = friendlier radii,
admin = tighter radii and tables. Components follow shadcn/ui conventions (cva + tailwind-merge + Radix Slot), written by hand because the shadcn CLI registry is not reachable
from the build environment; they can be swapped for CLI-generated versions later. Reference uploads were used as follows: the dark sidebar + card layout of the
intranet screenshot informed the app shell; the Mentors/Learnix pages informed the arch/pill shape language and orange-led editorial hero. No photos or layouts were copied.

## Environment variables
Public: `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_STUDENT_APP_URL`, `NEXT_PUBLIC_ADMIN_APP_URL`, `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
Student/Admin: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SITE_URL`. Edge Functions: `STUDENT_APP_URL`, `ADMIN_APP_URL`, optional `GITHUB_API_TOKEN`.

## Bringing it online (needs your accounts)
1. Create the Supabase project; `supabase link`; `supabase db push` (applies `20261122000100_foundations.sql`).
2. `supabase functions deploy invite-user complete-onboarding`; set function secrets from `.env.example`. Turn **sign-up off** and apply `config.toml` (redirect URLs, templates).
3. Configure custom SMTP (Resend) in Supabase Auth for invite/reset emails.
4. Create the first admin (auth user + `bootstrap_first_admin`).
5. Create three Vercel projects (public, student, admin) with the env vars above and the domains from the spec.
6. Set `contact.email` in the public site's `config/site.ts` when an enquiry address exists.

## Assumptions made (not in the spec)
- The interest-form table, its field set and the dedupe-by-email rule are ours; fields are configurable in `config/interest-form.ts`.
- The registration window (confirmed by the academy) stays in `config/site.ts`; `/apply` shows it together with the interest form.
- Moderators don't go through onboarding (spec describes student onboarding only).
- Students may read their own cohort/course rows even while the cohort is a draft; project content will be gated in Phase 1.
- Shared code imports use explicit `.ts` extensions so Deno (Edge Functions) can import the same Zod schemas.
