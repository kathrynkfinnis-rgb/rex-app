import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { HitList } from "@/components/HitList";

export const Route = createFileRoute("/_authenticated/me")({
  head: () => ({
    meta: [
      { title: "My List — REX" },
      { name: "description", content: "Your saved books, films, places and recipes to get to." },
      { property: "og:title", content: "My List — REX" },
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
        <h1 className="font-display text-3xl">My List</h1>
        <p className="mt-1 text-sm text-muted-foreground">Everything you want to read, watch, eat and do.</p>
      </header>

      <section className="p-4">
        {user ? <HitList userId={user.id} /> : null}
      </section>
    </div>
  );
}

