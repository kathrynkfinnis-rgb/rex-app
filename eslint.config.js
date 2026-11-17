import js from "@eslint/js";
import eslintPluginPrettier from "eslint-plugin-prettier/recommended";
import globals from "globals";
import tseslint from "typescript-eslint";

export default tseslint.config(
  // Nov 7 — this listed three build directories and nothing else, so
  // `eslint .` walked the whole repository: android/app/build (tens of
  // thousands of generated files), the iOS tree, and supabase/functions,
  // which is Deno and fails these rules by design. A lint that takes over
  // five minutes and reports on generated code is one nobody runs, and it
  // could not have gone in CI as it stood.
  //
  // The other three codebases have their own tools — Gradle's lint, Xcode's
  // warnings, and `deno check`.
  {
    ignores: ["dist", ".output", ".vinxi", "android/**", "ios/**", "supabase/**"],
  },
  // Nov 17 — this block used to say files: ["**/*.{ts,tsx}"] and carry the
  // react-hooks and react-refresh plugins plus a rule about TanStack Start's
  // server-only imports. All of that went with the TanStack app on 7 November,
  // and the last .ts file in scope (capacitor.config.ts) went today, so the
  // block had been linting nothing at all for ten days. js.configs.recommended
  // sat inside it, which meant the only rules reaching the repository's actual
  // JavaScript were prettier's formatting ones — `npm run lint` was a format
  // check wearing a lint's clothes.
  //
  // So it points at the JavaScript that is really here: the Cloudflare Pages
  // Functions that render every share link, web/admin.js, and this file.
  {
    extends: [js.configs.recommended],
    files: ["**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      // Pages Functions run on workerd, not in a browser and not in Node:
      // fetch, Request, Response, URL and crypto are global, document is not.
      globals: { ...globals.worker, ...globals.browser },
    },
  },
  eslintPluginPrettier,
);
