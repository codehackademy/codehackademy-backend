import { handleCompleteOnboarding } from "../_shared/complete-onboarding.ts";
import { onboardingDeps } from "../_shared/runtime.ts";

Deno.serve((req: Request) => handleCompleteOnboarding(req, onboardingDeps()));
