import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { categoryMeta, type ItemType } from "@/lib/categories";
import { ArrowLeft, Globe2, Lock, Users } from "lucide-react";

type Visibility = "draft" | "friends" | "public";

export const Route = createFileRoute("/_authenticated/list/$id")({
  head: () => ({
    meta: [
      { title: "Collection — REX 🦖💡" },
      { name: "description", content: "A REX collection of recommendations worth saving." },
      { property: "og:title", content: "A REX collection" },
      { property: "og:description", content: "A REX collection of recommendations worth saving." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: ListPage,
});

const VIS: Record<Visibility, { label: string; icon: typeof Lock }> = {
  draft: { label: "Only you", icon: Lock },
  friends: { label: "Friends", icon: Users },
  public: { label: "Public", icon: Globe2 },
};

function ListPage() {
  const { id } = Route.useParams();

  const { data: list, isLoading } = useQuery({
    queryKey: ["list", id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("hitlist_lists")
        .select("id, user_id, item_type, name, emoji, visibility")
        .eq("id", id)
        .maybeSingle();
      if (error) throw error;
      if (!data) return null;
      const { data: prof } = await supabase
        .from("profiles")
        .select("username, display_name")
        .eq("id", (data as any).user_id)
        .maybeSingle();
      return { ...(data as any), profiles: prof ?? null } as any;
    },
  });

  const { data: entries } = useQuery({
    queryKey: ["list-entries", id],
    enabled: !!list,
    queryFn: async () => {
      const [wants, saved] = await Promise.all([
        supabase
          .from("wants")
          .select("id, item_id, created_at, items!inner(id, type, title, subtitle, image_url)")
          .eq("list_id", id)
          .order("created_at", { ascending: false }),
        supabase
          .from("saved_posts")
          .select(
            "id, created_at, recommendations!inner(id, items!inner(id, type, title, subtitle, image_url))",
          )
          .eq("list_id", id)
          .order("created_at", { ascending: false }),
      ]);
      const out: {
        key: string;
        title: string;
        subtitle: string | null;
        image: string | null;
        type: ItemType;
        href: string;
        params: any;
      }[] = [];
      for (const w of (wants.data ?? []) as any[]) {
        out.push({
          key: `w-${w.id}`,
          title: w.items.title,
          subtitle: w.items.subtitle,
          image: w.items.image_url,
          type: w.items.type,
          href: "/item/$id",
          params: { id: w.item_id },
        });
      }
      for (const s of (saved.data ?? []) as any[]) {
        const it = s.recommendations?.items;
        if (!it) continue;
        out.push({
          key: `s-${s.id}`,
          title: it.title,
          subtitle: it.subtitle,
          image: it.image_url,
          type: it.type,
          href: "/r/$id",
          params: { id: s.recommendations.id },
        });
      }
      return out;
    },
  });

  if (isLoading) {
    return <div className="px-5 py-8 text-sm text-muted-foreground">Loading collection…</div>;
  }

  if (!list) {
    return (
      <div className="px-5 py-10 text-center">
        <h1 className="text-lg font-semibold">Collection not available</h1>
        <p className="mt-1 text-sm text-muted-foreground">It may be private or no longer exists.</p>
        <Link to="/feed" className="mt-4 inline-block text-sm font-medium text-primary">
          Back to feed
        </Link>
      </div>
    );
  }

  const V = VIS[(list.visibility as Visibility) ?? "draft"];
  const owner = list.profiles;

  return (
    <div className="pb-24">
      <header className="sticky top-0 z-10 border-b border-border bg-background/90 px-5 py-3 backdrop-blur">
        <Link to="/feed" className="mb-2 inline-flex items-center gap-1 text-sm text-muted-foreground">
          <ArrowLeft className="h-4 w-4" /> Back
        </Link>
        <h1 className="text-xl font-semibold">
          {list.emoji ? `${list.emoji} ` : ""}
          {list.name}
        </h1>
        <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
          <span className="inline-flex items-center gap-1 rounded-full bg-muted px-2 py-0.5">
            <V.icon className="h-3 w-3" /> {V.label}
          </span>
          <span>{categoryMeta(list.item_type as ItemType).plural}</span>
          {owner?.username && (
            <Link to="/profile/$username" params={{ username: owner.username }} className="text-primary">
              @{owner.username}
            </Link>
          )}
        </div>
      </header>

      <div className="space-y-2 px-4 py-4">
        {(entries ?? []).length === 0 && (
          <p className="rounded-2xl border border-dashed border-border bg-card p-6 text-center text-sm text-muted-foreground">
            Nothing in this collection yet.
          </p>
        )}
        {(entries ?? []).map((e) => (
          <Link
            key={e.key}
            to={e.href as any}
            params={e.params}
            className="flex items-center gap-3 rounded-2xl bg-card p-3 ring-1 ring-border transition-colors hover:bg-muted/60"
          >
            {e.image ? (
              <img src={e.image} alt="" className="h-12 w-12 rounded-xl object-cover" loading="lazy" />
            ) : (
              <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-secondary">
                {(() => {
                  const Icon = categoryMeta(e.type).icon;
                  return <Icon className="h-5 w-5 text-muted-foreground" />;
                })()}
              </div>
            )}
            <div className="min-w-0 flex-1">
              <p className="truncate font-medium">{e.title}</p>
              {e.subtitle && <p className="truncate text-xs text-muted-foreground">{e.subtitle}</p>}
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
