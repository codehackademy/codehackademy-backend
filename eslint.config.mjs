import tseslint from "typescript-eslint";
export default tseslint.config({ ignores: ["node_modules/**", "shared/**", "supabase/functions/_shared/runtime.ts", "supabase/functions/*/index.ts"] }, ...tseslint.configs.recommended);
