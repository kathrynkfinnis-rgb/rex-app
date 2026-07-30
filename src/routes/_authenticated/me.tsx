import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { HitList } from "@/components/HitList";
import { Globe2, ChevronRight } from "lucide-react";

export const Route = createFileRoute("/_authenticated/me")({
  head: () => ({
    meta: [
      { title: "My Collections — REX" },
      { name: "description", content: "Your saved books, films, places and recipes to get to." },
      { property: "og:title", content: "My Collections — REX" },
      { property: "og:description", content: "Your saved books, films, places and recipes to get to." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: MePage,
});

function MePage() {
  const { data: user } = useQuery({
    queryKey: ["me-user"],
    queryFn: async () => (await supabase.auth.getUser()).data.user,
  });



  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-6 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <h1 className="font-display text-3xl">My Collections</h1>
        <p className="mt-1 text-sm text-muted-foreground">Everything you want to read, watch, eat and do.</p>
      </header>

      <section className="px-4 pt-4">
        <Link
          to="/shared-collections"
          className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border transition-colors hover:bg-muted/60"
        >
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/10 text-primary">
            <Globe2 className="h-5 w-5" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="font-medium">Shared Collections</p>
            <p className="text-xs text-muted-foreground">Public collections from across REX, most read first</p>
          </div>
          <ChevronRight className="h-4 w-4 text-muted-foreground" />
        </Link>
      </section>

      <section className="p-4">
        {user ? <HitList userId={user.id} /> : null}
      </section>
    </div>
  );
}

