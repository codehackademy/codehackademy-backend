import { inviteUserSchema } from "./vendor/shared/schemas/admin.ts";
import { fail, json, readJson } from "./http.ts";

export type Caller = { id: string; role: "STUDENT" | "MODERATOR" | "ADMIN"; status: "ACTIVE" | "SUSPENDED" };

export type InviteDeps = {
  /** Verify the bearer token and load the caller's profile. Null when unauthenticated. */
  authenticate(req: Request): Promise<Caller | null>;
  findCohortCourse(cohortId: string, courseId: string): Promise<{ id: string } | null>;
  inviteAuthUser(email: string, name: string, role: "STUDENT" | "MODERATOR"): Promise<{ ok: true; id: string } | { ok: false; reason: "EXISTS" | "ERROR"; message: string }>;
  deleteAuthUser(id: string): Promise<void>;
  insertProfile(p: { id: string; role: "STUDENT" | "MODERATOR"; name: string; email: string }): Promise<void>;
  addStudentToCohort(studentId: string, cohortId: string, cohortCourseId: string): Promise<void>;
  writeAudit(e: { actor_id: string; action: string; entity_type: string; entity_id: string; after_json: unknown }): Promise<void>;
};

/** Admin-only. Creates an invited account + profile (+ cohort membership and enrolment for students). */
export async function handleInviteUser(req: Request, deps: InviteDeps): Promise<Response> {
  if (req.method !== "POST") return fail("VALIDATION_FAILED", "Use POST.");

  const caller = await deps.authenticate(req);
  if (!caller) return fail("UNAUTHENTICATED", "Sign in to continue.");
  if (caller.role !== "ADMIN" || caller.status !== "ACTIVE") return fail("FORBIDDEN", "Only administrators can invite users.");

  const parsed = inviteUserSchema.safeParse(await readJson(req));
  if (!parsed.success) {
    return fail("VALIDATION_FAILED", "Check the highlighted fields.", { fieldErrors: parsed.error.flatten().fieldErrors });
  }
  const input = parsed.data;

  let cohortCourseId: string | null = null;
  if (input.role === "STUDENT") {
    const cc = await deps.findCohortCourse(input.cohortId!, input.courseId!);
    if (!cc) return fail("NOT_FOUND", "That course has not been added to that cohort.");
    cohortCourseId = cc.id;
  }

  const email = input.email.toLowerCase();
  const invited = await deps.inviteAuthUser(email, input.name, input.role);
  if (!invited.ok) {
    return invited.reason === "EXISTS"
      ? fail("CONFLICT", "An account with this email already exists.")
      : fail("INTERNAL", "The invitation could not be sent. Try again shortly.");
  }

  try {
    await deps.insertProfile({ id: invited.id, role: input.role, name: input.name, email });
    if (input.role === "STUDENT") await deps.addStudentToCohort(invited.id, input.cohortId!, cohortCourseId!);
  } catch {
    // Never leave a half-created account behind.
    await deps.deleteAuthUser(invited.id);
    return fail("INTERNAL", "The account could not be created. Nothing was saved.");
  }

  await deps.writeAudit({
    actor_id: caller.id, action: "invite_user", entity_type: "profiles", entity_id: invited.id,
    after_json: { role: input.role, email, cohortId: input.cohortId ?? null, courseId: input.courseId ?? null },
  });
  return json({ id: invited.id, email, role: input.role }, 201);
}
