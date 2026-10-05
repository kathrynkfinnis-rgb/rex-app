import { createFileRoute, notFound, redirect } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";

// Oct 5 — "and can we truncate the link?"
//
// /s/<code> is the short form of every share link the app produces. It holds
// no content of its own: it resolves the code and redirects to the real page,
// which keeps one copy of each page rather than two that can drift apart.
//
// The redirect happens in the loader, so on the server it is a real HTTP
// redirect rather than something that only works once JavaScript has run.
// That matters more than it looks: WhatsApp fetches the link to build its
// preview, and it follows a 302 but would make nothing of a page that
// redirects itself after loading.

export const Route = createFileRoute("/s/$code")({
  loader: async ({ params }) => {
    // Cast: the generated Supabase types predate this function.
    const { data, error } = await (supabase.rpc as any)("resolve_share_code", {
      _code: params.code,
    });
    if (error || !data || !Array.isArray(data) || data.length === 0) throw notFound();

    const { kind, target_id } = data[0] as { kind: string; target_id: string };
    if (!target_id) throw notFound();

    // Spelled out rather than built from a lookup: the router types each
    // route path as a literal, so a computed string isn't a route it knows.
    const to = { id: target_id };
    switch (kind) {
      case "rec":
        throw redirect({ to: "/r/$id", params: to });
      case "trip":
        throw redirect({ to: "/t/$id", params: to });
      case "want":
        throw redirect({ to: "/w/$id", params: to });
      case "list":
        throw redirect({ to: "/c/$id", params: to });
      default:
        throw notFound();
    }
  },
  // Never rendered — the loader always either redirects or throws notFound.
  component: () => null,
});
