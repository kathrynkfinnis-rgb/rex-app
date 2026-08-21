// @lovable.dev/vite-tanstack-config already includes the following — do NOT add them manually
// or the app will break with duplicate plugins:
//   - TanStack devtools (dev-only, first), tanstackStart, viteReact, tailwindcss, tsConfigPaths,
//     nitro (build-only using cloudflare as a default target), VITE_* env injection, @ path alias,
//     React/TanStack dedupe, error logger plugins, and sandbox detection (port/host/strictPort).
// You can pass additional config via defineConfig({ vite: { ... }, etc... }) if needed.
import { defineConfig } from "@lovable.dev/vite-tanstack-config";

// Public Lovable Cloud connection values. The managed environment normally
// injects these, but keeping a build-time fallback prevents the entire app
// from blanking if that binding is temporarily missing.
const cloudUrl = "https://efkrlbyqqwpoxotrbtce.supabase.co";
const cloudPublishableKey = "sb_publishable_u7RY28T0bASs5l8agKd4Yw_cz4MhgPJ";

export default defineConfig({
  tanstackStart: {
    // Redirect TanStack Start's bundled server entry to src/server.ts (our SSR error wrapper).
    // nitro/vite builds from this
    server: { entry: "server" },
  },
  vite: {
    define: {
      "import.meta.env.VITE_SUPABASE_URL": JSON.stringify(cloudUrl),
      "import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY": JSON.stringify(cloudPublishableKey),
      "process.env.SUPABASE_URL": JSON.stringify(cloudUrl),
      "process.env.SUPABASE_PUBLISHABLE_KEY": JSON.stringify(cloudPublishableKey),
    },
    server: {
      allowedHosts: true,
    },
  },
});
