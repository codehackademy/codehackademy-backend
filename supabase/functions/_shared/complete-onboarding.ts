import { onboardingSchema } from "../../../shared/src/schemas/onboarding.ts";
import { fail, json, readJson } from "./http.ts";
import type { Caller } from "./invite-user.ts";

export type GithubLookup = { status: "FOUND"; login: string } | { status: "NOT_FOUND" } | { status: "UNAVAILABLE" };

export type OnboardingDeps = {
  authenticate(req: Request): Promise<(Caller & { onboarded: boolean }) | null>;
  fetchGithubUser(username: string): Promise<GithubLookup>;
  isGithubTaken(login: string, exceptUserId: string): Promise<boolean>;
  completeProfile(id: string, p: { country: string; city: string; timezone: string; github_username: string; consented_at: string; onboarded_at: string }): Promise<void>;
  writeAudit(e: { actor_id: string; action: string; entity_type: string; entity_id: string; after_json: unknown }): Promise<void>;
  now(): Date;
};

/** Student onboarding: location, confirmed time zone, consent, and a GitHub username verified against the GitHub API (spec §3). */
export async function handleCompleteOnboarding(req: Request, deps: OnboardingDeps): Promise<Response> {
  if (req.method !== "POST") return fail("VALIDATION_FAILED", "Use POST.");

  const caller = await deps.authenticate(req);
  if (!caller) return fail("UNAUTHENTICATED", "Sign in to continue.");
  if (caller.role !== "STUDENT") return fail("FORBIDDEN", "Onboarding is for students.");
  if (caller.onboarded) {
    return fail("CONFLICT", "You have already completed onboarding. Ask a moderator to approve a GitHub username change.");
  }

  const parsed = onboardingSchema.safeParse(await readJson(req));
  if (!parsed.success) {
    return fail("VALIDATION_FAILED", "Check the highlighted fields.", { fieldErrors: parsed.error.flatten().fieldErrors });
  }
  const input = parsed.data;

  const gh = await deps.fetchGithubUser(input.githubUsername);
  if (gh.status === "UNAVAILABLE") return fail("GITHUB_UNAVAILABLE", "We could not reach GitHub just now. Please try again in a minute.");
  if (gh.status === "NOT_FOUND") return fail("GITHUB_USER_NOT_FOUND", "We couldn't find that GitHub account. Check the spelling.", { fieldErrors: { githubUsername: ["We couldn't find that GitHub account."] } });

  if (await deps.isGithubTaken(gh.login, caller.id)) {
    return fail("CONFLICT", "That GitHub username is already linked to another student.", { fieldErrors: { githubUsername: ["Already linked to another account."] } });
  }

  const at = deps.now().toISOString();
  try {
    await deps.completeProfile(caller.id, {
      country: input.country, city: input.city, timezone: input.timezone,
      github_username: gh.login, consented_at: at, onboarded_at: at,
    });
  } catch {
    return fail("INTERNAL", "Your details could not be saved. Nothing was changed.");
  }
  await deps.writeAudit({
    actor_id: caller.id, action: "complete_onboarding", entity_type: "profiles", entity_id: caller.id,
    after_json: { country: input.country, city: input.city, timezone: input.timezone, github_username: gh.login },
  });
  return json({ ok: true, githubUsername: gh.login });
}
