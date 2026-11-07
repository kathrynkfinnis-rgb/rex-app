import js from "@eslint/js";
import eslintPluginPrettier from "eslint-plugin-prettier/recommended";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import tseslint from "typescript-eslint";

export default tseslint.config(
  // Nov 7 — this listed three build directories and nothing else, so
  // `eslint .` walked the whole repository: android/app/build (tens of
  // thousands of generated files), the iOS tree, and supabase/functions,
  // which is Deno and fails these rules by design. A lint that takes over
  // five minutes and reports on generated code is one nobody runs, and it
  // could not have gone in CI as it stood.
  //
  // This config is the web app's. The other three have their own tools —
  // Gradle's lint, Xcode's warnings, and `deno check`.
  {
    ignores: [
      "dist",
      ".output",
      ".vinxi",
      "android/**",
      "ios/**",
      "supabase/**",
      "**/routeTree.gen.ts",
    ],
  },
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
    },
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "no-restricted-imports": [
        "error",
        {
          paths: [
            {
              name: "server-only",
              message:
                "TanStack Start does not use the Next.js `server-only` package. Rename the module to `*.server.ts` or mark it with `@tanstack/react-start/server-only`.",
            },
          ],
        },
      ],
      "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],
      "@typescript-eslint/no-unused-vars": "off",
    },
  },
  eslintPluginPrettier,
);
