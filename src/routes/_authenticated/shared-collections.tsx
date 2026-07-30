import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { UserAvatar } from "@/components/UserAvatar";
import { ArrowLeft, Eye, Globe2 } from "lucide-react";

export const Route = createFileRoute("/_authenticated/shared-collections")({
  head: () => ({
    meta: [
      { title: "Shared Collections — REX 🦖💡" },
      { name: "description", content: "Public REX collections from the community, ranked by most read." },
      { property: "og:title", content: "Shared Collections — REX 🦖💡" },
      { property: "og:description", content: "Public REX collections from the community, ranked by most read." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: SharedCollectionsPage,
});

type Row = {
  id: string;
  name: string;
  emoji: string | null;
  view_count: number;
  owner_id: string | null;
  owner_username: string | null;
  owner_display_name: string | null;
  owner_avatar_url: string | null;
  item_count: number;
};

function SharedCollectionsPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["public-collections"],
    queryFn: async () => {
      const { data, error } = await (supabase as any).rpc("public_collections", { _limit: 100 });
      if (error) throw error;
      return (data ?? []) as Row[];
    },
  });

  return (
    <div className="pb-24">
      <header className="border-b border-border bg-background px-5 pb-6 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <Link to="/me" className="mb-2 inline-flex items-center gap-1 text-sm text-muted-foreground">
          <ArrowLeft className="h-4 w-4" /> My Collections
        </Link>
        <h1 className="font-display text-3xl">Shared Collections</h1>
        <p className="mt-1 text-sm text-muted-foreground">Public collections from across REX — most read first.</p>
      </header>

      <div className="space-y-2 p-4">
        {isLoading && <p className="text-sm text-muted-foreground">Loading collections…</p>}
        {!isLoading && (data ?? []).length === 0 && (
          <p className="rounded-2xl border border-dashed border-border bg-card p-6 text-center text-sm text-muted-foreground">
            No public collections yet — set one of yours to Public to share it here.
          </p>
        )}
        {(data ?? []).map((c) => (
          <Link
            key={c.id}
            to="/list/$id"
            params={{ id: c.id }}
            className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border transition-colors hover:bg-muted/60"
          >
            <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-secondary text-lg">
              {c.emoji ?? "✨"}
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate font-medium">{c.name}</p>
              <div className="mt-0.5 flex items-center gap-2 text-xs text-muted-foreground">
                {c.owner_username && (
                  <span className="inline-flex items-center gap-1">
                    <UserAvatar
                      url={c.owner_avatar_url}
                      name={c.owner_display_name ?? c.owner_username}
                      size="xs"
                    />
                    @{c.owner_username}
                  </span>
                )}
                <span>{Number(c.item_count)} items</span>
              </div>
            </div>
            <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-muted px-2 py-1 text-xs text-muted-foreground">
              <Eye className="h-3.5 w-3.5" /> {c.view_count}
            </span>
            <Globe2 className="h-4 w-4 shrink-0 text-primary" />
          </Link>
        ))}
      </div>
    </div>
  );
}
