import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { CATEGORIES, type ItemType } from "@/lib/categories";
import { RecommendationCard, type FeedRow } from "@/components/RecommendationCard";
import { Sparkles } from "lucide-react";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/feed")({
  head: () => ({
    meta: [
      { title: "Your feed — Reco" },
      { name: "description", content: "The latest recommendations from your friends." },
    ],
  }),
  component: FeedPage,
});

function FeedPage() {
  const [filter, setFilter] = useState<ItemType | "all">("all");

  const { data, isLoading } = useQuery({
    queryKey: ["feed", filter],
    queryFn: async () => {
      let q = supabase
        .from("recommendations")
        .select("id, rating, note, created_at, photo_url, user_id, item_id, items!inner(id, type, title, subtitle, image_url), profiles!recommendations_user_id_fkey(username, display_name, avatar_url)")
        .order("created_at", { ascending: false })
        .limit(50);
      if (filter !== "all") q = q.eq("items.type", filter);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as unknown as FeedRow[];
    },
  });

  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-30 border-b border-border bg-background/90 px-5 pb-3 pt-[calc(env(safe-area-inset-top)+1rem)] backdrop-blur">
        <div className="flex items-center justify-between">
          <div>
            <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-widest text-primary">
              <Sparkles className="h-3 w-3" /> Reco
            </div>
            <h1 className="mt-0.5 font-display text-3xl">Your feed</h1>
          </div>
        </div>
        <div className="scrollbar-none mt-3 flex gap-2 overflow-x-auto -mx-5 px-5">
          <Chip active={filter === "all"} onClick={() => setFilter("all")}>All</Chip>
          {CATEGORIES.map((c) => (
            <Chip key={c.type} active={filter === c.type} onClick={() => setFilter(c.type)}>
              <c.icon className="h-3.5 w-3.5" />
              {c.plural}
            </Chip>
          ))}
        </div>
      </header>

      <div className="space-y-3 px-4 py-4">
        {isLoading && (
          <>
            <SkeletonCard />
            <SkeletonCard />
          </>
        )}
        {!isLoading && (data?.length ?? 0) === 0 && <EmptyState />}
        {data?.map((rec) => <RecommendationCard key={rec.id} rec={rec} />)}
      </div>
    </div>
  );
}

function Chip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "flex shrink-0 items-center gap-1.5 rounded-full border px-4 py-1.5 text-sm font-medium transition-colors",
        active
          ? "border-primary bg-primary text-primary-foreground"
          : "border-border bg-card text-foreground",
      )}
    >
      {children}
    </button>
  );
}

function SkeletonCard() {
  return <div className="h-40 animate-pulse rounded-2xl bg-muted" />;
}

function EmptyState() {
  return (
    <div className="mt-10 rounded-3xl border border-dashed border-border bg-card p-8 text-center">
      <h2 className="font-display text-2xl">Nothing here yet</h2>
      <p className="mt-2 text-sm text-muted-foreground">
        Add your first recommendation — or invite a friend so you can see theirs.
      </p>
    </div>
  );
}
