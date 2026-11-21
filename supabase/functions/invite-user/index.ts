import { handleInviteUser } from "../_shared/invite-user.ts";
import { inviteDeps } from "../_shared/runtime.ts";

Deno.serve((req: Request) => handleInviteUser(req, inviteDeps()));
