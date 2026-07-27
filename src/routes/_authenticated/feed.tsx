import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { CATEGORIES, type ItemType } from "@/lib/categories";
import { RecommendationCard, type FeedRow } from "@/components/RecommendationCard";
import { TRexLogo } from "@/components/TRexLogo";
import { Button } from "@/components/ui/button";
import { UserPlus, Mic, Plus } from "lucide-react";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/feed")({
  head: () => ({
    meta: [
      { title: "Your feed — REX" },
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
        .select("id, rating, note, created_at, photo_url, user_id, item_id, items!inner(id, type, title, subtitle, image_url, genre), profiles!recommendations_user_id_fkey(username, display_name, avatar_url), creators(slug, name, color, emoji)")
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
              <TRexLogo className="h-4 w-4" /> REX
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
    <div className="mt-8 rounded-3xl border border-dashed border-border bg-card p-6 text-center">
      <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-primary/10">
        <TRexLogo className="h-7 w-7" />
      </div>
      <h2 className="mt-3 font-display text-2xl">Your feed is empty</h2>
      <p className="mx-auto mt-2 max-w-xs text-sm text-muted-foreground">
        Add friends or follow a creator — their picks will land here.
      </p>
      <div className="mt-5 grid gap-2">
        <Button asChild className="h-11 rounded-full">
          <Link to="/friends"><UserPlus className="mr-1.5 h-4 w-4" /> Add friends</Link>
        </Button>
        <Button asChild variant="outline" className="h-11 rounded-full">
          <Link to="/creators"><Mic className="mr-1.5 h-4 w-4" /> Follow creators</Link>
        </Button>
        <Button asChild variant="ghost" className="h-11 rounded-full">
          <Link to="/add"><Plus className="mr-1.5 h-4 w-4" /> Add your first rec</Link>
        </Button>
      </div>
    </div>
  );
}
