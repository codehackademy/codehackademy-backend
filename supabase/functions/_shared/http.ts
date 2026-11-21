import { apiError, type ErrorCode } from "../../../shared/src/constants.ts";

const STATUS: Partial<Record<ErrorCode, number>> = {
  UNAUTHENTICATED: 401, FORBIDDEN: 403, ACCOUNT_SUSPENDED: 403, VALIDATION_FAILED: 400,
  NOT_FOUND: 404, GITHUB_USER_NOT_FOUND: 422, CONFLICT: 409, GITHUB_UNAVAILABLE: 503, INTERNAL: 500,
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

export function fail(code: ErrorCode, message: string, details: Record<string, unknown> = {}): Response {
  return json(apiError(code, message, details), STATUS[code] ?? 400);
}

export async function readJson(req: Request): Promise<unknown> {
  try { return await req.json(); } catch { return undefined; }
}
