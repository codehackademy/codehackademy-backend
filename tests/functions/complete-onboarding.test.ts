import { describe, expect, it, vi } from "vitest";
import { handleCompleteOnboarding, type OnboardingDeps } from "../../supabase/functions/_shared/complete-onboarding.ts";

const valid = { country: "Nigeria", city: "Lagos", timezone: "Africa/Lagos", githubUsername: "ada-obi", consent: true };
const req = (body: unknown) => new Request("http://fn/onb", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
const NOW = new Date("2026-11-23T08:00:00.000Z");

function makeDeps(over: Partial<OnboardingDeps> = {}): OnboardingDeps {
  return {
    authenticate: vi.fn(async () => ({ id: "s1", role: "STUDENT" as const, status: "ACTIVE" as const, onboarded: false })),
    fetchGithubUser: vi.fn(async () => ({ status: "FOUND" as const, login: "Ada-Obi" })),
    isGithubTaken: vi.fn(async () => false),
    completeProfile: vi.fn(async () => {}),
    writeAudit: vi.fn(async () => {}),
    now: () => NOW,
    ...over,
  };
}

describe("complete-onboarding", () => {
  it("saves location, time zone, consent and the GitHub login as GitHub spells it", async () => {
    const deps = makeDeps();
    const res = await handleCompleteOnboarding(req(valid), deps);
    expect(res.status).toBe(200);
    expect(deps.completeProfile).toHaveBeenCalledWith("s1", {
      country: "Nigeria", city: "Lagos", timezone: "Africa/Lagos", github_username: "Ada-Obi",
      consented_at: NOW.toISOString(), onboarded_at: NOW.toISOString(),
    });
    expect(deps.writeAudit).toHaveBeenCalled();
  });
  it("401s when signed out and 403s for non-students", async () => {
    expect((await handleCompleteOnboarding(req(valid), makeDeps({ authenticate: vi.fn(async () => null) }))).status).toBe(401);
    const mod = makeDeps({ authenticate: vi.fn(async () => ({ id: "m", role: "MODERATOR" as const, status: "ACTIVE" as const, onboarded: false })) });
    expect((await handleCompleteOnboarding(req(valid), mod)).status).toBe(403);
  });
  it("refuses to run twice (username changes need moderator approval)", async () => {
    const deps = makeDeps({ authenticate: vi.fn(async () => ({ id: "s1", role: "STUDENT" as const, status: "ACTIVE" as const, onboarded: true })) });
    const res = await handleCompleteOnboarding(req(valid), deps);
    expect(res.status).toBe(409);
    expect(deps.fetchGithubUser).not.toHaveBeenCalled();
  });
  it("requires consent and a valid time zone", async () => {
    expect((await handleCompleteOnboarding(req({ ...valid, consent: false }), makeDeps())).status).toBe(400);
    expect((await handleCompleteOnboarding(req({ ...valid, timezone: "Mars/Base" }), makeDeps())).status).toBe(400);
  });
  it("rejects GitHub accounts that do not exist", async () => {
    const deps = makeDeps({ fetchGithubUser: vi.fn(async () => ({ status: "NOT_FOUND" as const })) });
    const res = await handleCompleteOnboarding(req(valid), deps);
    expect(res.status).toBe(422);
    expect((await res.json()).error.code).toBe("GITHUB_USER_NOT_FOUND");
    expect(deps.completeProfile).not.toHaveBeenCalled();
  });
  it("is honest when GitHub is unreachable instead of accepting or rejecting the name", async () => {
    const deps = makeDeps({ fetchGithubUser: vi.fn(async () => ({ status: "UNAVAILABLE" as const })) });
    const res = await handleCompleteOnboarding(req(valid), deps);
    expect(res.status).toBe(503);
    expect(deps.completeProfile).not.toHaveBeenCalled();
  });
  it("rejects a GitHub username linked to someone else", async () => {
    const deps = makeDeps({ isGithubTaken: vi.fn(async () => true) });
    const res = await handleCompleteOnboarding(req(valid), deps);
    expect(res.status).toBe(409);
    expect(deps.completeProfile).not.toHaveBeenCalled();
  });
  it("does not audit when saving fails", async () => {
    const deps = makeDeps({ completeProfile: vi.fn(async () => { throw new Error("db"); }) });
    expect((await handleCompleteOnboarding(req(valid), deps)).status).toBe(500);
    expect(deps.writeAudit).not.toHaveBeenCalled();
  });
});
