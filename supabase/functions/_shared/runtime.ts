// Real wiring for the handlers (Deno on Supabase Edge Functions). Not imported by unit tests.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { Caller, InviteDeps } from "./invite-user.ts";
import type { GithubLookup, OnboardingDeps } from "./complete-onboarding.ts";

declare const Deno: { env: { get(k: string): string | undefined } };

const env = (k: string) => {
  const v = Deno.env.get(k);
  if (!v) throw new Error(`Missing environment variable ${k}`);
  return v;
};

/** Service-role client. Lives only inside Edge Functions; the key never reaches a browser. */
export const serviceClient = (): SupabaseClient =>
  createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false, autoRefreshToken: false } });

async function authenticate(sb: SupabaseClient, req: Request): Promise<(Caller & { onboarded: boolean }) | null> {
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data: auth } = await sb.auth.getUser(token);
  if (!auth.user) return null;
  const { data: p } = await sb.from("profiles").select("id, role, status, onboarded_at").eq("id", auth.user.id).maybeSingle();
  return p ? { id: p.id, role: p.role, status: p.status, onboarded: p.onboarded_at !== null } : null;
}

export function inviteDeps(): InviteDeps {
  const sb = serviceClient();
  return {
    authenticate: (req) => authenticate(sb, req),
    async findCohortCourse(cohortId, courseId) {
      const { data } = await sb.from("cohort_courses").select("id").eq("cohort_id", cohortId).eq("course_id", courseId).maybeSingle();
      return data;
    },
    async inviteAuthUser(email, name) {
      const { data, error } = await sb.auth.admin.inviteUserByEmail(email, {
        data: { name }, // display only: roles are never read from user metadata
        redirectTo: env("INVITE_REDIRECT_URL"),
      });
      if (error || !data.user) {
        return { ok: false, reason: /already|registered|exists/i.test(error?.message ?? "") ? "EXISTS" : "ERROR", message: error?.message ?? "unknown" };
      }
      return { ok: true, id: data.user.id };
    },
    async deleteAuthUser(id) { await sb.auth.admin.deleteUser(id); },
    async insertProfile(p) { const { error } = await sb.from("profiles").insert(p); if (error) throw error; },
    async addStudentToCohort(studentId, cohortId, cohortCourseId) {
      const m = await sb.from("cohort_members").insert({ cohort_id: cohortId, user_id: studentId, member_role: "STUDENT" });
      if (m.error) throw m.error;
      const e = await sb.from("enrollments").insert({ student_id: studentId, cohort_course_id: cohortCourseId });
      if (e.error) throw e.error;
    },
    async writeAudit(e) { await sb.from("audit_logs").insert(e); },
  };
}

export function onboardingDeps(): OnboardingDeps {
  const sb = serviceClient();
  return {
    authenticate: (req) => authenticate(sb, req) as ReturnType<OnboardingDeps["authenticate"]>,
    async fetchGithubUser(username): Promise<GithubLookup> {
      try {
        const token = Deno.env.get("GITHUB_API_TOKEN");
        const res = await fetch(`https://api.github.com/users/${encodeURIComponent(username)}`, {
          headers: { accept: "application/vnd.github+json", "user-agent": "codehackademy-onboarding", ...(token ? { authorization: `Bearer ${token}` } : {}) },
        });
        if (res.status === 404) return { status: "NOT_FOUND" };
        if (!res.ok) return { status: "UNAVAILABLE" }; // rate limit, 5xx, etc.
        const body = (await res.json()) as { login?: string; type?: string };
        if (!body.login || body.type !== "User") return { status: "NOT_FOUND" }; // organisations don't count
        return { status: "FOUND", login: body.login };
      } catch {
        return { status: "UNAVAILABLE" };
      }
    },
    async isGithubTaken(login, exceptUserId) {
      const { data } = await sb.from("profiles").select("id").ilike("github_username", login).neq("id", exceptUserId).limit(1);
      return (data?.length ?? 0) > 0;
    },
    async completeProfile(id, p) { const { error } = await sb.from("profiles").update(p).eq("id", id); if (error) throw error; },
    async writeAudit(e) { await sb.from("audit_logs").insert(e); },
    now: () => new Date(),
  };
}
