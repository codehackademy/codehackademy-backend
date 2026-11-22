import { describe, expect, it, vi } from "vitest";
import { handleInviteUser, type InviteDeps, type Caller } from "../../supabase/functions/_shared/invite-user.ts";

const COHORT = "3f2b8c1e-8f6a-4c1a-9a53-0a6c3b0b2f11";
const COURSE = "4a2b8c1e-8f6a-4c1a-9a53-0a6c3b0b2f12";
const admin: Caller = { id: "admin-1", role: "ADMIN", status: "ACTIVE" };

const req = (body: unknown, method = "POST") =>
  new Request("http://fn/invite-user", { method, headers: { "content-type": "application/json" }, body: method === "POST" ? JSON.stringify(body) : undefined });

function makeDeps(over: Partial<InviteDeps> = {}) {
  const deps: InviteDeps = {
    authenticate: vi.fn(async () => admin),
    findCohortCourse: vi.fn(async () => ({ id: "cc-1" })),
    inviteAuthUser: vi.fn(async () => ({ ok: true as const, id: "new-user" })),
    deleteAuthUser: vi.fn(async () => {}),
    insertProfile: vi.fn(async () => {}),
    addStudentToCohort: vi.fn(async () => {}),
    writeAudit: vi.fn(async () => {}),
    ...over,
  };
  return deps;
}
const student = { role: "STUDENT", name: "Ada Obi", email: "Ada@Example.com", cohortId: COHORT, courseId: COURSE };

describe("invite-user", () => {
  it("rejects unauthenticated callers (401) before touching anything", async () => {
    const deps = makeDeps({ authenticate: vi.fn(async () => null) });
    const res = await handleInviteUser(req(student), deps);
    expect(res.status).toBe(401);
    expect(deps.inviteAuthUser).not.toHaveBeenCalled();
  });
  it.each<Caller>([
    { id: "s", role: "STUDENT", status: "ACTIVE" },
    { id: "m", role: "MODERATOR", status: "ACTIVE" },
    { id: "a", role: "ADMIN", status: "SUSPENDED" },
  ])("forbids non-admin or suspended callers (%j)", async (caller) => {
    const deps = makeDeps({ authenticate: vi.fn(async () => caller) });
    const res = await handleInviteUser(req(student), deps);
    expect(res.status).toBe(403);
    expect(deps.inviteAuthUser).not.toHaveBeenCalled();
  });
  it("validates input and returns the standard error shape", async () => {
    const res = await handleInviteUser(req({ role: "ADMIN", name: "x", email: "bad" }), makeDeps());
    const body = await res.json();
    expect(res.status).toBe(400);
    expect(body.error.code).toBe("VALIDATION_FAILED");
    expect(body.error.details.fieldErrors).toBeTruthy();
  });
  it("404s when the course is not part of the cohort", async () => {
    const deps = makeDeps({ findCohortCourse: vi.fn(async () => null) });
    const res = await handleInviteUser(req(student), deps);
    expect(res.status).toBe(404);
    expect(deps.inviteAuthUser).not.toHaveBeenCalled();
  });
  it("invites a student, enrols them, lowercases the email and audits", async () => {
    const deps = makeDeps();
    const res = await handleInviteUser(req(student), deps);
    expect(res.status).toBe(201);
    expect(deps.inviteAuthUser).toHaveBeenCalledWith("ada@example.com", "Ada Obi", "STUDENT");
    expect(deps.insertProfile).toHaveBeenCalledWith({ id: "new-user", role: "STUDENT", name: "Ada Obi", email: "ada@example.com" });
    expect(deps.addStudentToCohort).toHaveBeenCalledWith("new-user", COHORT, "cc-1");
    expect(deps.writeAudit).toHaveBeenCalledWith(expect.objectContaining({ actor_id: "admin-1", action: "invite_user", entity_id: "new-user" }));
  });
  it("invites a moderator without cohort enrolment", async () => {
    const deps = makeDeps();
    const res = await handleInviteUser(req({ role: "MODERATOR", name: "Mo Dera", email: "mo@example.com" }), deps);
    expect(res.status).toBe(201);
    expect(deps.inviteAuthUser).toHaveBeenCalledWith("mo@example.com", "Mo Dera", "MODERATOR");
    expect(deps.addStudentToCohort).not.toHaveBeenCalled();
  });
  it("409s when the email already has an account", async () => {
    const deps = makeDeps({ inviteAuthUser: vi.fn(async () => ({ ok: false as const, reason: "EXISTS" as const, message: "registered" })) });
    const res = await handleInviteUser(req(student), deps);
    expect(res.status).toBe(409);
    expect(deps.insertProfile).not.toHaveBeenCalled();
  });
  it("rolls back the auth user when saving the profile or enrolment fails", async () => {
    const deps = makeDeps({ addStudentToCohort: vi.fn(async () => { throw new Error("db"); }) });
    const res = await handleInviteUser(req(student), deps);
    expect(res.status).toBe(500);
    expect(deps.deleteAuthUser).toHaveBeenCalledWith("new-user");
    expect(deps.writeAudit).not.toHaveBeenCalled();
  });
  it("only accepts POST", async () => {
    expect((await handleInviteUser(req({}, "GET"), makeDeps())).status).toBe(400);
  });
});
